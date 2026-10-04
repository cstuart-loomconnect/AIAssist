/*
Class Name: AIConversationVisibilityService

=================================================================
=================================================================

Description: Decides who may read a conversation they did not start. Reading only: a conversation can be
sent to, retried, closed, resumed, exported and acted on by the user who started it and nobody else.

Sharing decides first. Every conversation is read in user mode, so a viewer never reaches a conversation
the org's sharing (ownership, the role hierarchy, View All) does not already give them. The two settings
below only narrow that, and both must allow it:
[1] The agent (AIAgent__c.ConversationVisibility__c). Private, the default, means the starter only.
    Global means anyone the viewer's own scope reaches.
[2] The viewer's scope (ConversationVisibilityScope__c, resolved from their policies and their own row by
    AIUsagePolicyResolver). My Conversations Only, the default, reaches nobody else. My Subordinates
    Conversations reaches users in a role below the viewer's in the role hierarchy. All Conversations
    reaches every user, and is honoured only for a viewer who holds View All on AI Conversation or the
    AIAssistViewSharedConversations custom permission: without one of them it reaches nobody.
A conversation about a record is also readable only by a viewer who can read that record (UserRecordAccess),
so visibility never shows someone data they could not open themselves.

Anything unknown fails closed: a blank or unrecognised scope or agent setting is the narrowest one. The
viewer is always the signed-in user, because user mode answers for nobody else. Only the role hierarchy
and the viewer's own permissions are read in system mode: they are setup data, not conversations.

=================================================================
=================================================================
Applicable Classes:

AIChatConversationService, AIChatController

Version      Author                   Description
1.0          Chandler Stuart          Initial development. Gives ConversationVisibility__c and ConversationVisibilityScope__c an effect.
2.0          Chandler Stuart          With sharing and user mode: the scope narrows what sharing allows and never widens it. All Conversations needs View All or AIAssistViewSharedConversations. The viewer is the signed-in user.
*/

public with sharing class AIConversationVisibilityService {
  private static final Integer RECORD_ACCESS_BATCH = 200; // UserRecordAccess answers for at most 200 records per query.

  // The narrowest scope when nothing, or something unrecognised, is set.
  public static String getEffectiveScope(AIUserSettings__c userSettings) {
    String scope = userSettings?.ConversationVisibilityScope__c;

    return scope ==
      AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES ||
      scope == AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL
      ? scope
      : AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN;
  }

  // Role Ids below the signed-in user's role, at any depth. Empty for a user with no role.
  public static Set<Id> getSubordinateRoleIds() {
    Set<Id> subordinateRoleIds = new Set<Id>();

    if (UserInfo.getUserRoleId() == null)
      return subordinateRoleIds;

    Set<Id> currentLevel = new Set<Id>{ UserInfo.getUserRoleId() };
    for (
      Integer depth = 0;
      depth < AIAssistApplicationConstants.MAX_ROLE_HIERARCHY_DEPTH &&
      !currentLevel.isEmpty();
      depth++
    ) {
      Set<Id> nextLevel = new Set<Id>();
      for (UserRole childRole : [
        SELECT Id
        FROM UserRole
        WHERE ParentRoleId IN :currentLevel
        WITH SYSTEM_MODE
        LIMIT 2000
      ]) {
        if (subordinateRoleIds.add(childRole.Id))
          nextLevel.add(childRole.Id);
      }
      currentLevel = nextLevel;
    }

    return subordinateRoleIds;
  }

  // Whether the All Conversations scope is honoured for the signed-in user: the custom permission, or View All on AI Conversation from any permission set, permission set group or profile they hold (View All Data switches it on for every object).
  public static Boolean isAllScopeAllowed() {
    if (
      FeatureManagement.checkPermission(
        AIAssistApplicationConstants.PERMISSION_VIEW_SHARED_CONVERSATIONS
      )
    )
      return true;

    return [
        SELECT COUNT()
        FROM ObjectPermissions
        WHERE
          SobjectType = :String.valueOf(AIConversation__c.SObjectType)
          AND PermissionsViewAllRecords = TRUE
          AND ParentId IN (
            SELECT PermissionSetId
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
          )
        WITH SYSTEM_MODE
      ] > 0;
  }

  // Throws the "not found" refusal, the same answer as for a missing conversation, unless the signed-in user started the conversation or may read it under the rules above. Returns the conversation.
  public static AIConversation__c assertCanView(Id conversationId) {
    List<AIConversation__c> conversations = new List<AIConversation__c>();

    // User mode: a conversation sharing does not give the viewer is not found, and neither is anything for a user with no AI Assist permission set.
    try {
      if (
        conversationId != null &&
        conversationId.getSobjectType() == AIConversation__c.SObjectType
      )
        conversations = [
          SELECT
            Id,
            OwnerId,
            Status__c,
            AIAgent__c,
            AIAgent__r.ConversationVisibility__c,
            ProcessingLockedUntil__c,
            RelatedRecordId__c
          FROM AIConversation__c
          WHERE Id = :conversationId
          WITH USER_MODE
          LIMIT 1
        ];
    } catch (QueryException noAccess) {
      conversations.clear();
    }

    Boolean isReadable = false;
    if (!conversations.isEmpty()) {
      AIConversation__c conversation = conversations[0];
      String scope = getEffectiveScope(
        AIMessagingSelector.getUserSettings(UserInfo.getUserId())
      );

      if (conversation.OwnerId == UserInfo.getUserId()) {
        isReadable = true;
      } else if (
        conversation.AIAgent__r?.ConversationVisibility__c ==
        AIAssistApplicationConstants.AGENT_VISIBILITY_GLOBAL
      ) {
        Boolean isInScope = false;
        if (scope == AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL) {
          isInScope = isAllScopeAllowed();
        } else if (
          scope == AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES
        ) {
          Set<Id> subordinateRoleIds = getSubordinateRoleIds();
          isInScope =
            !subordinateRoleIds.isEmpty() &&
            [
              SELECT COUNT()
              FROM User
              WHERE
                Id = :conversation.OwnerId
                AND UserRoleId IN :subordinateRoleIds
              WITH SYSTEM_MODE
            ] == 1;
        }

        isReadable =
          isInScope &&
          filterReadableRecords(new List<AIConversation__c>{ conversation })
            .size() == 1;
      }
    }

    if (!isReadable)
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
        Label.AI_Error_Conversation_Not_Found
      );

    return conversations[0];
  }

  // The conversations the signed-in user may read that someone else started, newest first. Empty for the default scope, and for All Conversations without View All or the custom permission.
  public static List<AIConversation__c> getSharedConversations(
    String scope,
    String selectFields,
    Map<String, Object> binds,
    Integer maxRows
  ) {
    List<AIConversation__c> shared = new List<AIConversation__c>();

    Map<String, Object> queryBinds = new Map<String, Object>(binds);
    queryBinds.put('viewerId', UserInfo.getUserId());
    queryBinds.put(
      'globalVisibility',
      AIAssistApplicationConstants.AGENT_VISIBILITY_GLOBAL
    );

    String ownerFilter = '';
    if (scope == AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES) {
      Set<Id> subordinateRoleIds = getSubordinateRoleIds();
      if (subordinateRoleIds.isEmpty())
        return shared;
      queryBinds.put('subordinateRoleIds', subordinateRoleIds);
      ownerFilter = ' AND OwnerId IN (SELECT Id FROM User WHERE UserRoleId IN :subordinateRoleIds)';
    } else if (
      scope != AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL ||
      !isAllScopeAllowed()
    ) {
      return shared;
    }

    // Over-fetch because the record-access check below can remove rows; the final list is cut back to maxRows. User mode: sharing has already removed what the viewer cannot reach.
    queryBinds.put('candidateRows', maxRows * 4);
    List<AIConversation__c> candidates = Database.queryWithBinds(
      'SELECT ' +
        selectFields +
        ', OwnerId, Owner.Name, RelatedRecordId__c, AIAgent__r.ConversationVisibility__c FROM AIConversation__c' +
        ' WHERE OwnerId != :viewerId AND AIAgent__r.ConversationVisibility__c = :globalVisibility' +
        ownerFilter +
        ' ORDER BY LastModifiedDate DESC LIMIT :candidateRows',
      queryBinds,
      AccessLevel.USER_MODE
    );

    for (AIConversation__c readable : filterReadableRecords(candidates)) {
      shared.add(readable);
      if (shared.size() >= maxRows)
        break;
    }

    return shared;
  }

  // Keeps the conversations that are not about a record, and those about a record the viewer can read. UserRecordAccess answers with the viewer's real sharing, hierarchy and permissions.
  private static List<AIConversation__c> filterReadableRecords(
    List<AIConversation__c> conversations
  ) {
    List<AIConversation__c> readable = new List<AIConversation__c>();
    Set<Id> recordIds = new Set<Id>();

    for (AIConversation__c conversation : conversations) {
      Id recordId = AIChatDataStructure.toIdOrNull(
        conversation.RelatedRecordId__c
      );
      if (recordId != null)
        recordIds.add(recordId);
    }

    Set<Id> readableRecordIds = new Set<Id>();
    List<Id> pendingIds = new List<Id>(recordIds);
    for (
      Integer offset = 0;
      offset < pendingIds.size();
      offset += RECORD_ACCESS_BATCH
    ) {
      List<Id> batch = new List<Id>();
      for (
        Integer index = offset;
        index < Math.min(offset + RECORD_ACCESS_BATCH, pendingIds.size());
        index++
      )
        batch.add(pendingIds[index]);

      for (UserRecordAccess access : [
        SELECT RecordId, HasReadAccess
        FROM UserRecordAccess
        WHERE UserId = :UserInfo.getUserId() AND RecordId IN :batch
        WITH SYSTEM_MODE
      ]) {
        if (access.HasReadAccess == true)
          readableRecordIds.add(access.RecordId);
      }
    }

    for (AIConversation__c conversation : conversations) {
      Id recordId = AIChatDataStructure.toIdOrNull(
        conversation.RelatedRecordId__c
      );
      // A value that is not an Id cannot be checked, so it is not shown.
      if (
        String.isBlank(conversation.RelatedRecordId__c) ||
        (recordId != null && readableRecordIds.contains(recordId))
      )
        readable.add(conversation);
    }

    return readable;
  }
}
