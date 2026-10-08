/*
Class Name: AIUsageLimitService

=================================================================
=================================================================

Description: Decides whether a message may be accepted right now. A refusal is an AIMessagingException with
a Custom Label and a stable code, checked in this order:
[1] How fast one user may send: AIAssistSettings__c.MaxMessagesPerUserPerMinute__c.
[2] The user's concurrent conversations: AIUserSettings__c.MaxConcurrentConversations__c, only for a
    message that would start a conversation and only when the user's behaviour blocks it.
[3] The organisation's asynchronous queue has room. It is shared with the org's own queueables, batches
    and flows, so new turns are refused before ours can crowd theirs out.

Also says whether the cap on messages in flight (AIAssistSettings__c.MaxMessagesInFlight__c) is reached,
so a message waits as Queued until a place is free.

=================================================================
=================================================================

Version      Author                   Description
TBC          TBC                      TBC
*/

public inherited sharing class AIUsageLimitService {
  // A test cannot queue hundreds of jobs, so it lowers the ceiling instead.
  @TestVisible
  private static Integer maxPendingJobsForTest;
  // A test cannot keep jobs running, so it says how many are in flight.
  @TestVisible
  private static Integer inFlightForTest;

  public static void enforceUsageLimits(
    AIMessageValidator.ChatContext chatContext,
    Boolean isNewConversation
  ) {
    AIUserSettings__c userSettings = chatContext.userSettings;
    AIAssistSettings__c settings = AIAssistSettingsService.getSettings();

    // [1]
    if (
      settings.MaxMessagesPerUserPerMinute__c != null &&
      settings.MaxMessagesPerUserPerMinute__c >= 1 &&
      AIMessagingSelector.countRecentUserMessages(chatContext.userId) >=
      settings.MaxMessagesPerUserPerMinute__c
    )
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_RATE_LIMITED,
        Label.AI_Error_Rate_Limited
      );

    // [2]
    if (
      isNewConversation &&
      userSettings != null &&
      userSettings.IsActive__c == true &&
      userSettings.MaxConcurrentConversations__c != null &&
      userSettings.UsageLimitReachedBehavior__c !=
      AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY &&
      AIMessagingSelector.countActiveConversations(chatContext.userId) >=
      userSettings.MaxConcurrentConversations__c
    )
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_CONCURRENT_LIMIT,
        Label.AI_Error_Concurrent_Limit
      );

    // [3]
    Integer pendingJobLimit = maxPendingJobsForTest == null
      ? AIAssistApplicationConstants.MAX_PENDING_PROCESSING_JOBS
      : maxPendingJobsForTest;
    if (AIMessagingSelector.countQueuedMessageJobs() >= pendingJobLimit)
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_SERVICE_BUSY,
        Label.AI_Error_Service_Busy
      );
  }

  // True when the org-wide cap on messages in flight is reached: a new message is kept Queued and started when a place is free. False when no cap is set.
  public static Boolean isInFlightCapReached() {
    Decimal inFlightCap = AIAssistSettingsService.getSettings()
      .MaxMessagesInFlight__c;
    Integer messagesInFlight = inFlightForTest == null
      ? AIMessagingSelector.countQueuedMessageJobs()
      : inFlightForTest;

    return inFlightCap != null &&
      inFlightCap >= 1 &&
      messagesInFlight >= inFlightCap;
  }
}
