/*
Class Name: AIConversationVisibilityService

=================================================================
=================================================================

Description: Decides who may read a conversation they did not start. Reading only: a conversation can be sent to, retried, closed, resumed, exported and acted on by the user who started it and nobody else.

Step 1: Read the conversation in user mode, so sharing decides first and a viewer never reaches one the org does not already give them
Step 2: Let the starter read their own conversation
Step 3: For anyone else, require a Global agent and either a direct share from the starter or a scope (own, subordinates or all) that reaches the starter
Step 4: Require that the viewer can read the record the conversation is about
Step 5: Refuse with the "not found" message when any check fails, and fail closed on anything unknown

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIConversationVisibilityService {

    public class AIConversationVisibilityServiceException extends Exception {}

    private static final Integer RECORD_ACCESS_BATCH = 200; // UserRecordAccess answers for at most 200 records per query.

    // The narrowest scope when nothing, or something unrecognised, is set.
    public static String getEffectiveScope(AIUserSettings__c userSettings) {

        // [1] Read the scope from the user's settings
        String scope = userSettings?.ConversationVisibilityScope__c;

        // [2] Keep the two wider scopes, and fall back to the narrowest for anything else
        return scope == AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES || scope == AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL ? scope : AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN;
    }

    // Role Ids below the signed-in user's role, at any depth. Empty for a user with no role.
    public static Set<Id> getSubordinateRoleIds() {

        // [1] Start with an empty result
        Set<Id> subordinateRoleIds = new Set<Id>();

        // [2] Nothing to find - the user has no role
        if (UserInfo.getUserRoleId() == null) return subordinateRoleIds;

        // [3] Start from the user's own role
        Set<Id> currentLevel = new Set<Id>{ UserInfo.getUserRoleId() };

        for (Integer depth = 0; depth < AIAssistApplicationConstants.MAX_ROLE_HIERARCHY_DEPTH && !currentLevel.isEmpty(); depth++) {

            // [4] Find the roles directly below the current level
            Set<Id> nextLevel = new Set<Id>();

            for (UserRole childRole : [SELECT Id FROM UserRole WHERE ParentRoleId IN :currentLevel WITH SYSTEM_MODE LIMIT 2000]) {

                if (subordinateRoleIds.add(childRole.Id)) nextLevel.add(childRole.Id);
            }

            // [5] Move down one level
            currentLevel = nextLevel;
        }

        return subordinateRoleIds;
    }

    // Whether the All Conversations scope is honoured for the signed-in user: the custom permission, or View All on AI Conversation from any permission set, permission set group or profile they hold (View All Data switches it on for every object).
    public static Boolean isAllScopeAllowed() {

        // [1] The custom permission is enough
        if (FeatureManagement.checkPermission(AIAssistApplicationConstants.PERMISSION_VIEW_SHARED_CONVERSATIONS)) return true;

        // [2] Otherwise look for View All on AI Conversation in any permission set the user holds
        return [SELECT COUNT() FROM ObjectPermissions WHERE SobjectType = :String.valueOf(AIConversation__c.SObjectType) AND PermissionsViewAllRecords = TRUE AND ParentId IN (SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId()) WITH SYSTEM_MODE] > 0;
    }

    // The conversation, if the signed-in user started it or may read it under the rules above. Throws the "not found" refusal, the same answer as for a missing conversation, otherwise.
    public static AIConversation__c getViewableConversation(Id conversationId) {

        List<AIConversation__c> conversations = new List<AIConversation__c>();

        // [1] Read the conversation in user mode: one sharing does not give the viewer is not found, and neither is anything for a user with no AI Assist permission set
        try {

            if (conversationId != null && conversationId.getSobjectType() == AIConversation__c.SObjectType) conversations = [SELECT Id, OwnerId, Status__c, AIAgent__c, AIAgent__r.ConversationVisibility__c, ProcessingLockedUntil__c, RelatedRecordId__c FROM AIConversation__c WHERE Id = :conversationId WITH USER_MODE LIMIT 1];

        } catch (QueryException ex) {
            conversations.clear();
        }

        Boolean isReadable = false;

        if (!conversations.isEmpty()) {

            // [2] Work out the viewer's scope
            AIConversation__c conversation = conversations[0];
            String scope = getEffectiveScope(AIUsagePolicyService.getUserSettings(UserInfo.getUserId()));

            if (conversation.OwnerId == UserInfo.getUserId()) {

                // [3] The starter always reads their own conversation
                isReadable = true;
            } else if (conversation.AIAgent__r?.ConversationVisibility__c == AIAssistApplicationConstants.AGENT_VISIBILITY_GLOBAL && AIConversationShareService.hasDirectShare(conversation.Id, UserInfo.getUserId())) {

                // [4] The starter chose this viewer, so no scope is needed, but the viewer must still be able to read the record and the agent must still be Global
                isReadable = filterReadableRecords(new List<AIConversation__c>{ conversation }).size() == 1;
            } else if (conversation.AIAgent__r?.ConversationVisibility__c == AIAssistApplicationConstants.AGENT_VISIBILITY_GLOBAL) {

                // [5] For anyone else, check the starter is within the viewer's scope
                Boolean isInScope = false;

                if (scope == AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL) {

                    isInScope = isAllScopeAllowed();
                } else if (scope == AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES) {

                    Set<Id> subordinateRoleIds = getSubordinateRoleIds();
                    isInScope = !subordinateRoleIds.isEmpty() && [SELECT COUNT() FROM User WHERE Id = :conversation.OwnerId AND UserRoleId IN :subordinateRoleIds WITH SYSTEM_MODE] == 1;
                }

                // [6] The viewer must also be able to read the record the conversation is about
                isReadable = isInScope && filterReadableRecords(new List<AIConversation__c>{ conversation }).size() == 1;
            }
        }

        // [7] Refuse with the same answer as for a missing conversation
        if (!isReadable) throw new AIConversationVisibilityServiceException(Label.AI_Error_Conversation_Not_Found);

        return conversations[0];
    }

    // The conversations the signed-in user may read that someone else started, newest first. Empty for the default scope, and for All Conversations without View All or the custom permission.
    public static List<AIConversation__c> getSharedConversations(String scope, String selectFields, Map<String, Object> binds, Integer maxRows) {

        List<AIConversation__c> shared = new List<AIConversation__c>();

        // [1] Add the viewer and the Global setting to the caller's binds
        Map<String, Object> queryBinds = new Map<String, Object>(binds);
        queryBinds.put('viewerId', UserInfo.getUserId());
        queryBinds.put('globalVisibility', AIAssistApplicationConstants.AGENT_VISIBILITY_GLOBAL);

        // [2] Narrow the owners to the viewer's scope, or return nothing when the scope reaches nobody
        String ownerFilter = '';

        if (scope == AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES) {

            Set<Id> subordinateRoleIds = getSubordinateRoleIds();
            if (subordinateRoleIds.isEmpty()) return shared;
            queryBinds.put('subordinateRoleIds', subordinateRoleIds);
            ownerFilter = ' AND OwnerId IN (SELECT Id FROM User WHERE UserRoleId IN :subordinateRoleIds)';
        } else if (scope != AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL || !isAllScopeAllowed()) {

            return shared;
        }

        // [3] Read more rows than needed, because the record-access check can remove some; user mode means sharing has already removed what the viewer cannot reach
        queryBinds.put('candidateRows', maxRows * 4);
        List<AIConversation__c> candidates = Database.queryWithBinds('SELECT ' + getSelectWithOwnerAndRecord(selectFields) + ' FROM AIConversation__c' + ' WHERE OwnerId != :viewerId AND AIAgent__r.ConversationVisibility__c = :globalVisibility' + ownerFilter + ' ORDER BY LastModifiedDate DESC LIMIT :candidateRows', queryBinds, AccessLevel.USER_MODE);

        // [4] Keep the ones about records the viewer can read, up to the row limit
        for (AIConversation__c readable : filterReadableRecords(candidates)) {

            shared.add(readable);
            if (shared.size() >= maxRows) break;
        }

        return shared;
    }

    // The conversations someone else started that they shared directly with the signed-in user, newest first, whatever the viewer's own scope. Only Global agents, and only about records the viewer can read.
    public static List<AIConversation__c> getDirectlySharedConversations(String selectFields, Map<String, Object> binds, Integer maxRows) {

        List<AIConversation__c> shared = new List<AIConversation__c>();

        // [1] Find the conversations shared directly with the viewer; the share rows are read in system mode because a user cannot read them
        Set<Id> sharedIds = AIConversationShareService.getConversationIdsSharedWith(UserInfo.getUserId(), maxRows * 4);
        if (sharedIds.isEmpty()) return shared;

        // [2] Add the viewer and the Global setting to the caller's binds
        Map<String, Object> queryBinds = new Map<String, Object>(binds);
        queryBinds.put('viewerId', UserInfo.getUserId());
        queryBinds.put('globalVisibility', AIAssistApplicationConstants.AGENT_VISIBILITY_GLOBAL);
        queryBinds.put('sharedIds', sharedIds);
        queryBinds.put('candidateRows', maxRows * 4);

        // [3] Read them in user mode, so sharing still decides what the viewer reaches
        List<AIConversation__c> candidates = Database.queryWithBinds('SELECT ' + getSelectWithOwnerAndRecord(selectFields) + ' FROM AIConversation__c' + ' WHERE Id IN :sharedIds AND OwnerId != :viewerId AND AIAgent__r.ConversationVisibility__c = :globalVisibility' + ' ORDER BY LastModifiedDate DESC LIMIT :candidateRows', queryBinds, AccessLevel.USER_MODE);

        // [4] Keep the ones about records the viewer can read, up to the row limit
        for (AIConversation__c readable : filterReadableRecords(candidates)) {

            shared.add(readable);
            if (shared.size() >= maxRows) break;
        }

        return shared;
    }

    // Keeps the conversations that are not about a record, and those about a record the viewer can read. UserRecordAccess answers with the viewer's real sharing, hierarchy and permissions.
    public static List<AIConversation__c> filterReadableRecords(List<AIConversation__c> conversations) {

        List<AIConversation__c> readable = new List<AIConversation__c>();

        // [1] Collect the records the conversations are about
        Set<Id> recordIds = new Set<Id>();

        for (AIConversation__c conversation : conversations) {

            Id recordId = AIChatDataStructure.getIdOrNull(conversation.RelatedRecordId__c);
            if (recordId != null) recordIds.add(recordId);
        }

        // [2] Ask which of those records the viewer can read, in batches
        Set<Id> readableRecordIds = new Set<Id>();
        List<Id> pendingIds = new List<Id>(recordIds);

        for (Integer offset = 0; offset < pendingIds.size(); offset += RECORD_ACCESS_BATCH) {

            List<Id> batch = new List<Id>();

            for (Integer index = offset; index < Math.min(offset + RECORD_ACCESS_BATCH, pendingIds.size()); index++) batch.add(pendingIds[index]);

            for (UserRecordAccess access : [SELECT RecordId, HasReadAccess FROM UserRecordAccess WHERE UserId = :UserInfo.getUserId() AND RecordId IN :batch WITH SYSTEM_MODE]) {

                if (access.HasReadAccess == true) readableRecordIds.add(access.RecordId);
            }
        }

        // [3] Keep the conversations with no record, or with a record the viewer can read
        for (AIConversation__c conversation : conversations) {

            Id recordId = AIChatDataStructure.getIdOrNull(conversation.RelatedRecordId__c);

            // A value that is not an Id cannot be checked, so it is not shown.
            if (String.isBlank(conversation.RelatedRecordId__c) || (recordId != null && readableRecordIds.contains(recordId))) readable.add(conversation);
        }

        return readable;
    }

    // The caller's fields plus the ones the checks need, each added only when the caller has not already selected it, because a field selected twice fails the query.
    private static String getSelectWithOwnerAndRecord(String selectFields) {

        // [1] Add each field the caller did not select
        String fields = selectFields;

        for (String neededField : new List<String>{ 'OwnerId', 'Owner.Name', 'RelatedRecordId__c', 'AIAgent__r.ConversationVisibility__c' }) {

            if (!selectFields.contains(neededField)) fields += ', ' + neededField;
        }

        return fields;
    }
}
