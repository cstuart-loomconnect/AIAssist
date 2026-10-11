/*
Class Name: AIUsageLimitService

=================================================================
=================================================================

Description: Decides whether a message may be accepted right now. A refusal is an exception with a Custom Label.

Step 1: Refuse when the user is sending faster than AIAssistSettings__c.MaxMessagesPerUserPerMinute__c allows
Step 2: Refuse a new conversation when the user already has AIUsagePolicy__c.MaxConcurrentConversations__c active and their behaviour blocks it
Step 3: Refuse a new conversation when the user has started AIUsagePolicy__c.MaxConversationsPer24Hours__c conversations today and their behaviour blocks it
Step 4: Refuse when the user's conversations have spent AIUsagePolicy__c.MaxTokensPer24Hours__c tokens today and their behaviour blocks it
Step 5: Refuse when the org's asynchronous queue is full, so new turns cannot crowd out the org's own queueables, batches and flows
Step 6: Separately, say whether the cap on messages in flight (AIAssistSettings__c.MaxMessagesInFlight__c) is reached, so a message waits as Queued
Step 7: Separately, report which usage limit the user has reached and what it stops, for the chat window to show before they press Send

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

        // [1] Read the user's usage limits and the org's settings
        AIUsagePolicy__c usageLimits = chatContext.usageLimits;
        AIAssistSettings__c settings = AIAssistSettingsService.getSettings();

        // [2] Refuse when the user has sent too many messages in the last minute
        if (settings.MaxMessagesPerUserPerMinute__c != null && settings.MaxMessagesPerUserPerMinute__c >= 1 && countRecentUserMessages(chatContext.userId) >= settings.MaxMessagesPerUserPerMinute__c) throw new AIUsageLimitServiceException(Label.AI_Error_Rate_Limited);

        // [3] Refuse a new conversation when the user has reached their concurrent limit and their behaviour blocks it
        if (isNewConversation && isBlockingBehaviour(usageLimits) && isConcurrentLimitReached(chatContext.userId, usageLimits)) throw new AIUsageLimitServiceException(Label.AI_Error_Concurrent_Limit);

        // [4] Refuse a new conversation when the user has started their daily number of conversations and their behaviour blocks it
        if (isNewConversation && isBlockingBehaviour(usageLimits) && isDailyConversationLimitReached(chatContext.userId, usageLimits)) throw new AIUsageLimitServiceException(Label.AI_Error_Daily_Conversation_Limit);

        // [5] Refuse when the user has used their daily tokens. Block New Messages refuses every message; otherwise only a new conversation is refused
        if (isBlockingBehaviour(usageLimits) && (isNewConversation || usageLimits.UsageLimitReachedBehavior__c == AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES) && isDailyTokenLimitReached(chatContext.userId, usageLimits)) throw new AIUsageLimitServiceException(Label.AI_Error_Daily_Usage_Limit);

        // [6] Refuse when the shared queue is full
        Integer pendingJobLimit = maxPendingJobsForTest == null ? AIAssistApplicationConstants.MAX_PENDING_PROCESSING_JOBS : maxPendingJobsForTest;

        if (countQueuedMessageJobs() >= pendingJobLimit) throw new AIUsageLimitServiceException(Label.AI_Error_Service_Busy);
    }

    // The limit the user has reached and what it stops them doing, for the window to show before they press Send. Null when they have reached none. It makes the same checks as enforceUsageLimits, through the same helpers, so what the window says is what a send is refused for. When more than one limit is reached, the one that blocks most is reported: the token limit under Block New Messages, then tokens, daily conversations and open conversations.
    public static AIChatDataStructure.UsageLimitState getLimitState(Id userId, AIUsagePolicy__c usageLimits) {

        // [1] No limits, no state
        if (userId == null || usageLimits == null) return null;

        // [2] Read what the user has used, for each limit that is set and reached
        AIChatDataStructure.UsageLimitState tokensState = isDailyTokenLimitReached(userId, usageLimits) ? buildLimitState(AIAssistApplicationConstants.USAGE_LIMIT_TYPE_TOKENS, sumUserTokensToday(userId), usageLimits.MaxTokensPer24Hours__c, usageLimits) : null;
        AIChatDataStructure.UsageLimitState conversationsState = isDailyConversationLimitReached(userId, usageLimits) ? buildLimitState(AIAssistApplicationConstants.USAGE_LIMIT_TYPE_CONVERSATIONS, countUserConversationsToday(userId), usageLimits.MaxConversationsPer24Hours__c, usageLimits) : null;
        AIChatDataStructure.UsageLimitState openState = isConcurrentLimitReached(userId, usageLimits) ? buildLimitState(AIAssistApplicationConstants.USAGE_LIMIT_TYPE_OPEN, countActiveConversations(userId), usageLimits.MaxConcurrentConversations__c, usageLimits) : null;

        // [3] Report the one that blocks most
        if (tokensState != null) return tokensState;
        if (conversationsState != null) return conversationsState;

        return openState;
    }

    // What a reached limit stops, from the user's behaviour. A conversation count only ever blocks a new conversation; the token limit blocks every message only under Block New Messages.
    private static AIChatDataStructure.UsageLimitState buildLimitState(String limitType, Decimal used, Decimal max, AIUsagePolicy__c usageLimits) {

        // [1] Say which limit and how far the user is
        AIChatDataStructure.UsageLimitState limitState = new AIChatDataStructure.UsageLimitState();
        limitState.limitType = limitType;
        limitState.used = used;
        limitState.max = max;

        // [2] Say what it stops
        limitState.isNotifyOnly = !isBlockingBehaviour(usageLimits);
        limitState.blocksNewConversations = !limitState.isNotifyOnly;
        limitState.blocksMessages = limitType == AIAssistApplicationConstants.USAGE_LIMIT_TYPE_TOKENS && usageLimits.UsageLimitReachedBehavior__c == AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES;

        return limitState;
    }

    // True unless the user's behaviour is Notify Only, or there are no limits at all.
    private static Boolean isBlockingBehaviour(AIUsagePolicy__c usageLimits) {

        // [1] Anything but Notify Only blocks
        return usageLimits != null && usageLimits.UsageLimitReachedBehavior__c != AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY;
    }

    // True when a concurrent limit is set and the user has that many conversations open.
    private static Boolean isConcurrentLimitReached(Id userId, AIUsagePolicy__c usageLimits) {

        // [1] Count only when a limit is set
        return usageLimits != null && usageLimits.MaxConcurrentConversations__c != null && countActiveConversations(userId) >= usageLimits.MaxConcurrentConversations__c;
    }

    // True when a daily conversations limit is set and the user has started that many today.
    private static Boolean isDailyConversationLimitReached(Id userId, AIUsagePolicy__c usageLimits) {

        // [1] Count only when a limit is set
        return usageLimits != null && usageLimits.MaxConversationsPer24Hours__c != null && countUserConversationsToday(userId) >= usageLimits.MaxConversationsPer24Hours__c;
    }

    // True when a daily tokens limit is set and the user has used that many today.
    private static Boolean isDailyTokenLimitReached(Id userId, AIUsagePolicy__c usageLimits) {

        // [1] Count only when a limit is set
        return usageLimits != null && usageLimits.MaxTokensPer24Hours__c != null && sumUserTokensToday(userId) >= usageLimits.MaxTokensPer24Hours__c;
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

    // Conversations the user has started today, for the daily conversations limit. Read from the user's AIUsage__c record, which starts again each day.
    @TestVisible
    private static Integer countUserConversationsToday(Id userId) {

        // [1] Read today's count from the user's usage
        return AIUsageService.getConversationsStartedToday(userId);
    }

    // Tokens spent today in the user's conversations, for the daily token limit. Read from the user's AIUsage__c record, which starts again each day. It holds the AI's replies and failed turns too, because those tokens were spent too.
    @TestVisible
    private static Decimal sumUserTokensToday(Id userId) {

        // [1] Read today's total from the user's usage
        return AIUsageService.getTokensUsedToday(userId);
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
