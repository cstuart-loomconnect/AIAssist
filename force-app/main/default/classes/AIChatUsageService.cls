/*
Class Name: AIChatUsageService

=================================================================
=================================================================

Description: The usage meter the chat window shows, and the three behaviours of UsageLimitReachedBehavior__c.

Figures come from AIUsageDaily__c for the current UTC day through AIMessagingSelector, the same figures
AIUsageLimitService refuses on, so the meter and the refusal always agree. The window is told, not
decided for: it shows the meter and the "limit reached" card, while AIUsageLimitService is what actually
stops a message.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from the old usage service. Reads the daily usage rows for the UTC day instead of summing conversations over a rolling 24 hours.
*/

public with sharing class AIChatUsageService {
  public static AIChatDataStructure.UsageState buildUsageState(
    AIUserSettings__c userSettings
  ) {
    AIChatDataStructure.UsageState usage = new AIChatDataStructure.UsageState();
    Id userId = UserInfo.getUserId();
    AIMessagingSelector.UsageTotals todayUsage = AIMessagingSelector.getUserDailyUsage(
      userId,
      Datetime.now().dateGmt()
    );

    usage.tokensUsed = todayUsage.tokens;

    if (userSettings == null || userSettings.IsActive__c != true)
      return usage;

    usage.tokenLimit = userSettings.MaxTokensPer24Hours__c;
    usage.behavior = userSettings.UsageLimitReachedBehavior__c;

    Boolean isTokenLimitReached =
      usage.tokenLimit != null &&
      usage.tokensUsed >= usage.tokenLimit;
    Boolean isConversationLimitReached =
      userSettings.MaxConversationsPer24Hours__c != null &&
      todayUsage.conversations >= userSettings.MaxConversationsPer24Hours__c;
    Boolean isConcurrentLimitReached =
      userSettings.MaxConcurrentConversations__c != null &&
      AIMessagingSelector.countActiveConversations(userId) >=
      userSettings.MaxConcurrentConversations__c;
    Boolean isAnyLimitReached =
      isTokenLimitReached ||
      isConversationLimitReached ||
      isConcurrentLimitReached;

    if (
      usage.behavior == AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY
    ) {
      usage.notifyOnly = isAnyLimitReached;
    } else if (
      usage.behavior ==
      AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES
    ) {
      usage.blockMessages = isTokenLimitReached;
      usage.blockNewConversations = isAnyLimitReached;
    } else if (
      usage.behavior ==
      AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY
    ) {
      usage.blockNewConversations = isAnyLimitReached;
    }

    usage.limitReached =
      usage.notifyOnly ||
      usage.blockMessages ||
      usage.blockNewConversations;

    // The day is the UTC day, so usage resets at the next UTC midnight.
    if (usage.limitReached) {
      Datetime nextMidnight = Datetime.newInstanceGmt(
        Datetime.now().dateGmt().addDays(1),
        Time.newInstance(0, 0, 0, 0)
      );
      usage.resetsInMinutes = Math.max(
        1,
        ((nextMidnight.getTime() - System.now().getTime()) / 60000).intValue()
      );
    }

    return usage;
  }
}
