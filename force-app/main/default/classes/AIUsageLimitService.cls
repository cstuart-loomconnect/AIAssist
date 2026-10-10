/*
Class Name: AIUsageLimitService

=================================================================
=================================================================

Description: Decides whether a message may be accepted right now. A refusal is an exception with a Custom Label.

Step 1: Refuse when the user is sending faster than AIAssistSettings__c.MaxMessagesPerUserPerMinute__c allows
Step 2: Refuse a new conversation when the user already has AIUserSettings__c.MaxConcurrentConversations__c active and their behaviour blocks it
Step 3: Refuse a new conversation when the user has started AIUserSettings__c.MaxConversationsPer24Hours__c conversations in the last 24 hours and their behaviour blocks it
Step 4: Refuse when the user's conversations have spent AIUserSettings__c.MaxTokensPer24Hours__c tokens in the last 24 hours and their behaviour blocks it
Step 5: Refuse when the org's asynchronous queue is full, so new turns cannot crowd out the org's own queueables, batches and flows
Step 6: Separately, say whether the cap on messages in flight (AIAssistSettings__c.MaxMessagesInFlight__c) is reached, so a message waits as Queued

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIUsageLimitService {

    public class AIUsageLimitServiceException extends Exception {}

    // A test cannot queue hundreds of jobs, so it lowers the ceiling instead.
    @TestVisible
    private static Integer maxPendingJobsForTest;
    // A test cannot keep jobs running, so it says how many are in flight.
    @TestVisible
    private static Integer inFlightForTest;

    // Throws an exception carrying a Custom Label when the message may not be accepted right now.
    public static void enforceUsageLimits(AIMessageValidator.ChatContext chatContext, Boolean isNewConversation) {

        // [1] Read the user's settings and the org's settings
        AIUserSettings__c userSettings = chatContext.userSettings;
        AIAssistSettings__c settings = AIAssistSettingsService.getSettings();

        // [2] Refuse when the user has sent too many messages in the last minute
        if (settings.MaxMessagesPerUserPerMinute__c != null && settings.MaxMessagesPerUserPerMinute__c >= 1 && countRecentUserMessages(chatContext.userId) >= settings.MaxMessagesPerUserPerMinute__c) throw new AIUsageLimitServiceException(Label.AI_Error_Rate_Limited);

        // [3] Refuse a new conversation when the user has reached their concurrent limit and their behaviour blocks it
        if (isNewConversation && userSettings != null && userSettings.IsActive__c == true && userSettings.MaxConcurrentConversations__c != null && userSettings.UsageLimitReachedBehavior__c != AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY && countActiveConversations(chatContext.userId) >= userSettings.MaxConcurrentConversations__c) throw new AIUsageLimitServiceException(Label.AI_Error_Concurrent_Limit);

        // [4] Refuse a new conversation when the user has started their daily number of conversations and their behaviour blocks it
        if (isNewConversation && userSettings != null && userSettings.IsActive__c == true && userSettings.MaxConversationsPer24Hours__c != null && userSettings.UsageLimitReachedBehavior__c != AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY && countUserConversationsLast24Hours(chatContext.userId) >= userSettings.MaxConversationsPer24Hours__c) throw new AIUsageLimitServiceException(Label.AI_Error_Daily_Conversation_Limit);

        // [5] Refuse when the user has used their daily tokens. Block New Messages refuses every message; otherwise only a new conversation is refused
        if (userSettings != null && userSettings.IsActive__c == true && userSettings.MaxTokensPer24Hours__c != null && userSettings.UsageLimitReachedBehavior__c != AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY && (isNewConversation || userSettings.UsageLimitReachedBehavior__c == AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES) && sumUserTokensLast24Hours(chatContext.userId) >= userSettings.MaxTokensPer24Hours__c) throw new AIUsageLimitServiceException(Label.AI_Error_Daily_Usage_Limit);

        // [6] Refuse when the shared queue is full
        Integer pendingJobLimit = maxPendingJobsForTest == null ? AIAssistApplicationConstants.MAX_PENDING_PROCESSING_JOBS : maxPendingJobsForTest;

        if (countQueuedMessageJobs() >= pendingJobLimit) throw new AIUsageLimitServiceException(Label.AI_Error_Service_Busy);
    }

    // True when the org-wide cap on messages in flight is reached: a new message is kept Queued and started when a place is free. False when no cap is set.
    public static Boolean isInFlightCapReached() {

        // [1] Read the cap and how many messages are in flight
        Decimal inFlightCap = AIAssistSettingsService.getSettings().MaxMessagesInFlight__c;
        Integer messagesInFlight = inFlightForTest == null ? countQueuedMessageJobs() : inFlightForTest;

        // [2] The cap is reached when one is set and the messages in flight have used it up
        return inFlightCap != null && inFlightCap >= 1 && messagesInFlight >= inFlightCap;
    }

    // The user's conversations that count towards the concurrent limit: Active, and with activity inside their agent's idle timeout. One past its timeout is only waiting for the maintenance job to close it, so it does not hold a place. An agent with no timeout counts every Active conversation. It must see every user's records, so the class runs without sharing.
    @TestVisible
    private static Integer countActiveConversations(Id userId) {

        // [1] Start the count and note the time
        Datetime currentTime = System.now();
        Integer activeConversations = 0;

        // [2] Go through the user's Active conversations
        for (AIConversation__c conversation : [SELECT CreatedDate, LastMessageTimestamp__c, AIAgent__r.IdleTimeoutMinutes__c FROM AIConversation__c WHERE OwnerId = :userId AND Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE WITH SYSTEM_MODE ORDER BY LastModifiedDate DESC LIMIT :AIAssistApplicationConstants.MAX_ACTIVE_CONVERSATIONS_COUNTED]) {

            // [3] Use the last message time, or the created date when there has been no message
            Datetime lastActivity = conversation.LastMessageTimestamp__c == null ? conversation.CreatedDate : conversation.LastMessageTimestamp__c;

            // [4] Count it when its agent has no timeout or it is still inside the timeout
            if (conversation.AIAgent__r?.IdleTimeoutMinutes__c == null || lastActivity.addMinutes(Integer.valueOf(conversation.AIAgent__r.IdleTimeoutMinutes__c)) > currentTime) activeConversations++;
        }

        // [5] Return the count
        return activeConversations;
    }

    // Conversations the user started in the last 24 hours, for the daily conversations limit. It must see every conversation the user owns, so the class runs without sharing.
    @TestVisible
    private static Integer countUserConversationsLast24Hours(Id userId) {

        // [1] Look back 24 hours
        Datetime oneDayAgo = System.now().addHours(-24);

        // [2] Count the conversations the user owns that were created in that time
        return [SELECT COUNT() FROM AIConversation__c WHERE OwnerId = :userId AND CreatedDate >= :oneDayAgo WITH SYSTEM_MODE];
    }

    // Tokens spent in the last 24 hours in the user's conversations, for the daily token limit. It adds up every message with a count, the AI's replies and failed turns included, because those tokens were spent too. An aggregate counts each row it adds up against the query row limit, so this stays within it only for a user with fewer than tens of thousands of messages a day.
    @TestVisible
    private static Decimal sumUserTokensLast24Hours(Id userId) {

        // [1] Look back 24 hours
        Datetime oneDayAgo = System.now().addHours(-24);

        // [2] Add up the token counts of the messages in the user's conversations
        List<AggregateResult> totals = [SELECT SUM(TokenCount__c) tokensUsed FROM AIConversationMessage__c WHERE AIConversation__r.OwnerId = :userId AND CreatedDate >= :oneDayAgo AND TokenCount__c != NULL WITH SYSTEM_MODE];

        // [3] Return the total, or zero when there are no messages
        Decimal tokensUsed = (Decimal) totals[0].get('tokensUsed');

        return tokensUsed == null ? 0 : tokensUsed;
    }

    // Turns queued or running in this org right now. The asynchronous queue is shared with the subscriber, so the messaging layer refuses new work before it can crowd theirs out. Bounded to the last day because a job older than that is not pending.
    @TestVisible
    private static Integer countQueuedMessageJobs() {

        // [1] Look back one day only
        Datetime oneDayAgo = Datetime.now().addDays(-1);

        // [2] Match this package's class only, because a subscriber may have a class of the same name
        String packageNamespace = getPackageNamespace();

        // [3] Count the jobs still waiting or running
        return [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'AIMessageProcessingQueueable' AND ApexClass.NamespacePrefix = :packageNamespace AND JobType = 'Queueable' AND Status IN ('Queued', 'Preparing', 'Processing') AND CreatedDate >= :oneDayAgo WITH SYSTEM_MODE];
    }

    // Messages the user sent in the last 60 seconds, for the rate limit.
    @TestVisible
    private static Integer countRecentUserMessages(Id userId) {

        // [1] Look back 60 seconds only
        Datetime oneMinuteAgo = System.now().addSeconds(-60);

        // [2] Count the messages the user sent in that time
        return [SELECT COUNT() FROM AIConversationMessage__c WHERE CreatedById = :userId AND Sender__c = :AIAssistApplicationConstants.SENDER_USER AND CreatedDate >= :oneMinuteAgo WITH SYSTEM_MODE];
    }

    // The namespace this code runs in, as ApexClass.NamespacePrefix holds it. Null when the code is not in a namespace.
    private static String getPackageNamespace() {

        // [1] Take the part of the class name before the dot, if there is one
        return AIUsageLimitService.class.getName().contains('.') ? AIUsageLimitService.class.getName().substringBefore('.') : null;
    }
}
