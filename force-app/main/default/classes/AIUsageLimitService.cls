/*
Class Name: AIUsageLimitService

=================================================================
=================================================================

Description: Decides whether a message that has passed AIMessageValidator would take the user, or
the organisation, past a limit. Refusals are AIMessagingException with a Custom Label and a stable
code, checked in this order:
[1] The user's own limits (AIUserSettings__c) against their usage today (AIUsageDaily__c), by
    the behaviour in UsageLimitReachedBehavior__c:
    - Notify Only never blocks.
    - Block New Messages blocks every message once a limit is reached.
    - Block New Conversations Only applies the limits only to a message that would start a
      conversation, so an open one can carry on.
    Limits: conversations open at once, conversations started today, tokens used today.
[2] The organisation's limits: the plan's monthly messages and tokens (Feature Management) and
    AIAssistSettings__c.GlobalTokenBudgetPerDay__c, against the running totals AIOrgUsageService
    keeps. No usage row is read, however many there are.
[3] The organisation's asynchronous queue has room. It is shared with the subscriber's own
    queueables, batches and flows, so new turns are refused before ours can crowd theirs out.

"Today" and "this month" are the UTC calendar day and month: limits are read from AIUsageDaily__c,
one row per user per day, instead of summing every message. The fields are named "24 hours" in the
object model; they behave as per UTC day.

The token estimate of the message being sent counts towards the user's daily limit, so a message
that would break it is refused before its request is made. Nothing here writes.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, as the second half of AIMessageGuard.
2.0          Chandler Stuart          The monthly message and token cap messages say how much the plan allows and when it renews.
3.0          Chandler Stuart          Organisation totals read from AIOrgUsageService. A full queue says AI Assist is busy, not that the provider is unavailable.
*/

public inherited sharing class AIUsageLimitService {
  // A test cannot queue hundreds of jobs, so it lowers the ceiling instead.
  @TestVisible
  private static Integer maxPendingJobsForTest;

  public static void enforceUsageLimits(
    AIMessageValidator.ChatContext chatContext,
    Boolean isNewConversation,
    Decimal estimatedTokens
  ) {
    Date today = Datetime.now().dateGmt();
    AIUserSettings__c userSettings = chatContext.userSettings;

    // [1] The user's own limits.
    if (
      userSettings != null &&
      userSettings.IsActive__c == true &&
      userSettings.UsageLimitReachedBehavior__c !=
      AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY
    ) {
      Boolean blocksEverything =
        userSettings.UsageLimitReachedBehavior__c ==
        AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES;
      Boolean blocksNewConversations =
        userSettings.UsageLimitReachedBehavior__c ==
        AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY &&
        isNewConversation;

      if (blocksEverything || blocksNewConversations) {
        // Only a new conversation adds to either conversation count.
        if (
          isNewConversation &&
          userSettings.MaxConcurrentConversations__c != null &&
          AIMessagingSelector.countActiveConversations(chatContext.userId) >=
          userSettings.MaxConcurrentConversations__c
        ) {
          throw limitReached(
            chatContext,
            AIAssistApplicationConstants.ERROR_CONCURRENT_LIMIT,
            Label.AI_Error_Concurrent_Limit
          );
        }

        if (
          (isNewConversation &&
          userSettings.MaxConversationsPer24Hours__c != null) ||
          userSettings.MaxTokensPer24Hours__c != null
        ) {
          AIMessagingSelector.UsageTotals userUsage = AIMessagingSelector.getUserDailyUsage(
            chatContext.userId,
            today
          );

          if (
            isNewConversation &&
            userSettings.MaxConversationsPer24Hours__c != null &&
            userUsage.conversations >=
            userSettings.MaxConversationsPer24Hours__c
          ) {
            throw limitReached(
              chatContext,
              AIAssistApplicationConstants.ERROR_CONVERSATION_LIMIT_DAILY,
              Label.AI_Error_Conversation_Limit_Daily
            );
          }

          if (
            userSettings.MaxTokensPer24Hours__c != null &&
            userUsage.tokens + estimatedTokens >=
            userSettings.MaxTokensPer24Hours__c
          ) {
            throw limitReached(
              chatContext,
              AIAssistApplicationConstants.ERROR_DAILY_USAGE_LIMIT,
              Label.AI_Error_Daily_Usage_Limit
            );
          }
        }
      }
    }

    // [2] The organisation's limits.
    Integer messageLimit = AIPlanLimitService.getMessageLimit();
    Integer usageLimit = AIPlanLimitService.getUsageLimit();
    Decimal dailyBudget = AIAssistSettingsService.getSettings()
      .GlobalTokenBudgetPerDay__c;

    if (messageLimit != null || usageLimit != null || dailyBudget != null) {
      // The running totals AI Assist keeps (AIOrgUsageService), not a sum of the month's usage rows on every send.
      AIMessagingSelector.OrgUsage orgUsage = AIOrgUsageService.getUsage();

      if (messageLimit != null && orgUsage.month.messages >= messageLimit)
        throw limitReached(
          chatContext,
          AIAssistApplicationConstants.ERROR_PLAN_LIMIT_MESSAGES,
          planLimitMessage(
            Label.AI_Error_Plan_Limit_Messages,
            messageLimit,
            today
          )
        );
      if (usageLimit != null && orgUsage.month.tokens >= usageLimit)
        throw limitReached(
          chatContext,
          AIAssistApplicationConstants.ERROR_PLAN_LIMIT_USAGE,
          planLimitMessage(Label.AI_Error_Plan_Limit_Tokens, usageLimit, today)
        );
      if (dailyBudget != null && orgUsage.today.tokens >= dailyBudget)
        throw limitReached(
          chatContext,
          AIAssistApplicationConstants.ERROR_DAILY_USAGE_LIMIT,
          Label.AI_Error_Daily_Usage_Limit
        );
    }

    // [3] Room in the shared queue.
    if (
      AIMessagingSelector.countQueuedMessageJobs() >=
      (maxPendingJobsForTest == null
        ? AIAssistApplicationConstants.MAX_PENDING_PROCESSING_JOBS
        : maxPendingJobsForTest)
    ) {
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_SERVICE_BUSY,
        Label.AI_Error_Service_Busy
      );
    }
  }

  // A limit reached is the violation the object model calls Usage Limit Exceeded, when the agent has a rule for it.
  private static AIMessagingException limitReached(
    AIMessageValidator.ChatContext chatContext,
    String errorCode,
    String userMessageLabel
  ) {
    AIViolationService.recordDeterministicViolation(
      AIAssistApplicationConstants.VIOLATION_TYPE_USAGE_LIMIT_EXCEEDED,
      chatContext.agent == null ? null : chatContext.agent.Id,
      chatContext.userId,
      null,
      null
    );
    return AIMessagingException.newRefusal(errorCode, userMessageLabel);
  }

  // The plan's cap, in words: how much the plan allows and when it renews (the first of next month, the month the usage rows are counted in). Without it a cap looks like a fault.
  @TestVisible
  private static String planLimitMessage(
    String template,
    Integer allowance,
    Date today
  ) {
    return String.format(
      template,
      new List<String>{
        String.valueOf(allowance),
        today.toStartOfMonth().addMonths(1).format()
      }
    );
  }
}
