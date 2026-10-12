/*
Class Name: AIConversationShareService

=================================================================
=================================================================

Description: Lets the user who started a conversation share it, read-only, with individual users, and take that back.

Step 1: Check the user started the conversation, and that its agent keeps Global conversations, before anything is shared
Step 2: Search the users the conversation may be shared with: active standard users with an active AI User Setting, not the starter and not already chosen
Step 3: Share the conversation with a user, or stop sharing it, by adding or removing a Read share row with the DirectShare reason
Step 4: Answer whether a user has been chosen, for AIConversationVisibilityService, which still checks the record and the agent

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIConversationShareService {

    public class AIConversationShareServiceException extends Exception {}

    // The users the conversation is shared with, by name. Only the user who started the conversation may ask.
    public static List<AIChatDataStructure.ShareRecipient> getShares(Id conversationId) {

        // [1] Check the user started the conversation
        AIChatConversationService.getOwnedConversation(conversationId);

        // [2] Find the users it is shared with, by name
        Set<Id> sharedUserIds = getSharedUserIds(conversationId);
        List<AIChatDataStructure.ShareRecipient> recipients = new List<AIChatDataStructure.ShareRecipient>();
        if (sharedUserIds.isEmpty()) return recipients;

        for (User sharedUser : [SELECT Id, Name, Title, UserRole.Name FROM User WHERE Id IN :sharedUserIds WITH SYSTEM_MODE ORDER BY Name LIMIT 200]) recipients.add(buildRecipient(sharedUser));

        // [3] Return them
        return recipients;
    }

    // Up to ten users the conversation could be shared with, whose name contains the text. Needs two characters. Only the user who started the conversation may ask.
    public static List<AIChatDataStructure.ShareRecipient> searchShareableUsers(Id conversationId, String searchText) {

        // [1] Check the user started the conversation
        AIChatConversationService.getOwnedConversation(conversationId);

        // [2] Nothing to find when the text is too short
        List<AIChatDataStructure.ShareRecipient> recipients = new List<AIChatDataStructure.ShareRecipient>();
        String trimmedText = searchText == null ? '' : searchText.trim();
        if (trimmedText.length() < AIAssistApplicationConstants.SHARE_SEARCH_MIN_LENGTH) return recipients;

        // [3] Escape the text so a percent sign, underscore or backslash in it matches only itself
        String namePattern = '%' + trimmedText.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%';
        Set<Id> excludedIds = getSharedUserIds(conversationId);
        excludedIds.add(UserInfo.getUserId());

        // [4] Find active standard users with an active AI User Setting, who can therefore open the window
        for (User candidate : [SELECT Id, Name, Title, UserRole.Name FROM User WHERE IsActive = TRUE AND UserType = :AIAssistApplicationConstants.USER_TYPE_STANDARD AND Name LIKE :namePattern AND Id NOT IN :excludedIds AND Id IN (SELECT User__c FROM AIUserSettings__c WHERE IsActive__c = TRUE) WITH SYSTEM_MODE ORDER BY Name LIMIT :AIAssistApplicationConstants.SHARE_SEARCH_MAX_RESULTS]) recipients.add(buildRecipient(candidate));

        // [5] Return them
        return recipients;
    }

    // Shares the conversation, read-only, with the user. Sharing again with the same user changes nothing. The share row is written in system mode, because a user cannot write the share table of a private object.
    public static AIChatDataStructure.ShareRecipient shareConversation(Id conversationId, Id userId) {

        // [1] Check the user started the conversation
        AIConversation__c conversation = AIChatConversationService.getOwnedConversation(conversationId);

        // [2] Refuse unless the agent keeps Global conversations, so a private agent never leaks through a share
        List<AIAgent__c> agents = [SELECT ConversationVisibility__c FROM AIAgent__c WHERE Id = :conversation.AIAgent__c WITH SYSTEM_MODE LIMIT 1];
        if (agents.isEmpty() || agents[0].ConversationVisibility__c != AIAssistApplicationConstants.AGENT_VISIBILITY_GLOBAL) throw new AIConversationShareServiceException(Label.AI_Error_Share_Not_Global);

        // [3] Refuse sharing with oneself, with something that is not a user, and with a user who cannot open the window
        if (userId == null || userId.getSobjectType() != User.SObjectType) throw new AIConversationShareServiceException(Label.AI_Error_Share_User_Ineligible);
        if (userId == UserInfo.getUserId()) throw new AIConversationShareServiceException(Label.AI_Error_Share_Self);

        List<User> users = [SELECT Id, Name, Title, UserRole.Name FROM User WHERE Id = :userId AND IsActive = TRUE AND UserType = :AIAssistApplicationConstants.USER_TYPE_STANDARD WITH SYSTEM_MODE LIMIT 1];
        if (users.isEmpty() || AIUsagePolicyService.getAccessLevel(userId) == AIAssistApplicationConstants.ACCESS_LEVEL_NONE) throw new AIConversationShareServiceException(Label.AI_Error_Share_User_Ineligible);

        // [4] Do nothing more when the user already has it, and refuse a new share past the limit
        Set<Id> sharedUserIds = getSharedUserIds(conversationId);

        if (!sharedUserIds.contains(userId)) {

            if (sharedUserIds.size() >= AIAssistApplicationConstants.SHARE_MAX_PER_CONVERSATION) throw new AIConversationShareServiceException(Label.AI_Error_Share_Limit);

            // [5] Add the Read share row
            AIConversation__Share shareRow = new AIConversation__Share(ParentId = conversationId, UserOrGroupId = userId, AccessLevel = AIAssistApplicationConstants.SHARE_ACCESS_LEVEL_READ, RowCause = getDirectShareRowCause());
            Database.SaveResult saveResult = Database.insert(shareRow, false, AccessLevel.SYSTEM_MODE);

            if (!saveResult.isSuccess()) {

                AIPlatformLogManager.logCustomMessage('Conversation could not be shared: ' + saveResult.getErrors()[0].getMessage(), null, 'AIConversationShareService', 'shareConversation', conversationId);
                throw new AIConversationShareServiceException(Label.AI_Error_Share_Failed);
            }
        }

        // [6] Return who it is shared with
        return buildRecipient(users[0]);
    }

    // Stops sharing the conversation with the user. Only the user who started it may do this, and nothing happens when it was not shared with them.
    public static void unshareConversation(Id conversationId, Id userId) {

        // [1] Check the user started the conversation
        AIChatConversationService.getOwnedConversation(conversationId);

        // [2] Remove the user's direct share rows
        String rowCause = getDirectShareRowCause();
        List<AIConversation__Share> shareRows = [SELECT Id FROM AIConversation__Share WHERE ParentId = :conversationId AND UserOrGroupId = :userId AND RowCause = :rowCause WITH SYSTEM_MODE LIMIT 10];
        if (!shareRows.isEmpty()) Database.delete(shareRows, true, AccessLevel.SYSTEM_MODE);
    }

    // Whether the starter chose this user for the conversation.
    public static Boolean hasDirectShare(Id conversationId, Id userId) {

        // [1] Look for the user's direct share row
        String rowCause = getDirectShareRowCause();

        return [SELECT COUNT() FROM AIConversation__Share WHERE ParentId = :conversationId AND UserOrGroupId = :userId AND RowCause = :rowCause WITH SYSTEM_MODE LIMIT 1] > 0;
    }

    // The conversations that were shared directly with the user, up to maxRows.
    public static Set<Id> getConversationIdsSharedWith(Id userId, Integer maxRows) {

        // [1] Collect the parent of each of the user's direct share rows
        Set<Id> conversationIds = new Set<Id>();
        String rowCause = getDirectShareRowCause();

        for (AIConversation__Share shareRow : [SELECT ParentId FROM AIConversation__Share WHERE UserOrGroupId = :userId AND RowCause = :rowCause WITH SYSTEM_MODE ORDER BY LastModifiedDate DESC LIMIT :maxRows]) conversationIds.add(shareRow.ParentId);

        return conversationIds;
    }

    // The sharing reason this feature writes, with the package namespace when there is one.
    private static String getDirectShareRowCause() {

        // [1] Read the reason from the schema
        return Schema.AIConversation__Share.RowCause.DirectShare__c;
    }

    // The users a conversation is shared with.
    private static Set<Id> getSharedUserIds(Id conversationId) {

        // [1] Collect each user of the conversation's direct share rows
        Set<Id> userIds = new Set<Id>();
        String rowCause = getDirectShareRowCause();

        for (AIConversation__Share shareRow : [SELECT UserOrGroupId FROM AIConversation__Share WHERE ParentId = :conversationId AND RowCause = :rowCause WITH SYSTEM_MODE LIMIT 1000]) userIds.add(shareRow.UserOrGroupId);

        return userIds;
    }

    // Turns a user into what the window shows: the name, and under it their title, or else their role.
    private static AIChatDataStructure.ShareRecipient buildRecipient(User sharedUser) {

        // [1] Copy the name and pick the subtitle
        AIChatDataStructure.ShareRecipient recipient = new AIChatDataStructure.ShareRecipient();
        recipient.userId = sharedUser.Id;
        recipient.name = sharedUser.Name;
        recipient.subtitle = String.isNotBlank(sharedUser.Title) ? sharedUser.Title : (sharedUser.UserRole == null || String.isBlank(sharedUser.UserRole.Name) ? '' : sharedUser.UserRole.Name);

        return recipient;
    }
}
