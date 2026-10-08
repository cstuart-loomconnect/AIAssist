/*
Class Name: AIUsageLimitService

=================================================================
=================================================================

Description: Decides whether a message may be accepted right now. A refusal is an exception with
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
  public class AIUsageLimitServiceException extends Exception {
  }

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
      countRecentUserMessages(chatContext.userId) >=
      settings.MaxMessagesPerUserPerMinute__c
    )
      throw new AIUsageLimitServiceException(Label.AI_Error_Rate_Limited);

    // [2]
    if (
      isNewConversation &&
      userSettings != null &&
      userSettings.IsActive__c == true &&
      userSettings.MaxConcurrentConversations__c != null &&
      userSettings.UsageLimitReachedBehavior__c !=
      AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY &&
      countActiveConversations(chatContext.userId) >=
      userSettings.MaxConcurrentConversations__c
    )
      throw new AIUsageLimitServiceException(Label.AI_Error_Concurrent_Limit);

    // [3]
    Integer pendingJobLimit = maxPendingJobsForTest == null
      ? AIAssistApplicationConstants.MAX_PENDING_PROCESSING_JOBS
      : maxPendingJobsForTest;
    if (countQueuedMessageJobs() >= pendingJobLimit)
      throw new AIUsageLimitServiceException(Label.AI_Error_Service_Busy);
  }

  // True when the org-wide cap on messages in flight is reached: a new message is kept Queued and started when a place is free. False when no cap is set.
  public static Boolean isInFlightCapReached() {
    Decimal inFlightCap = AIAssistSettingsService.getSettings()
      .MaxMessagesInFlight__c;
    Integer messagesInFlight = inFlightForTest == null
      ? countQueuedMessageJobs()
      : inFlightForTest;

    return inFlightCap != null &&
      inFlightCap >= 1 &&
      messagesInFlight >= inFlightCap;
  }

  // These queries must see every user's records, not just the running user's, so they run in a class declared without sharing.
  private static SystemReader systemReader = new SystemReader();

  @TestVisible
  private static Integer countActiveConversations(Id userId) {
    return systemReader.countActiveConversations(userId);
  }

  @TestVisible
  private static Integer countQueuedMessageJobs() {
    return systemReader.countQueuedMessageJobs();
  }

  @TestVisible
  private static Integer countRecentUserMessages(Id userId) {
    return systemReader.countRecentUserMessages(userId);
  }

  private without sharing class SystemReader {
    // The user's conversations that count towards the concurrent limit: Active, and with activity inside their agent's idle timeout. One past its timeout is only waiting for the maintenance job to close it, so it does not hold a place. An agent with no timeout counts every Active conversation.
    public Integer countActiveConversations(Id userId) {
      Datetime currentTime = System.now();
      Integer activeConversations = 0;

      for (AIConversation__c conversation : [
        SELECT
          CreatedDate,
          LastMessageTimestamp__c,
          AIAgent__r.IdleTimeoutMinutes__c
        FROM AIConversation__c
        WHERE
          OwnerId = :userId
          AND Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE
        WITH SYSTEM_MODE
        ORDER BY LastModifiedDate DESC
        LIMIT :AIAssistApplicationConstants.MAX_ACTIVE_CONVERSATIONS_COUNTED
      ]) {
        Datetime lastActivity = conversation.LastMessageTimestamp__c == null
          ? conversation.CreatedDate
          : conversation.LastMessageTimestamp__c;
        if (
          conversation.AIAgent__r?.IdleTimeoutMinutes__c == null ||
          lastActivity.addMinutes(
            Integer.valueOf(conversation.AIAgent__r.IdleTimeoutMinutes__c)
          ) > currentTime
        )
          activeConversations++;
      }

      return activeConversations;
    }

    // Turns queued or running in this org right now. The asynchronous queue is shared with the subscriber, so the messaging layer refuses new work before it can crowd theirs out. Bounded to the last day because a job older than that is not pending.
    public Integer countQueuedMessageJobs() {
      Datetime oneDayAgo = Datetime.now().addDays(-1);
      String packageNamespace = getPackageNamespace(); // This package's class only: a subscriber may have a class of the same name.

      return [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE
          ApexClass.Name = 'AIMessageProcessingQueueable'
          AND ApexClass.NamespacePrefix = :packageNamespace
          AND JobType = 'Queueable'
          AND Status IN ('Queued', 'Preparing', 'Processing')
          AND CreatedDate >= :oneDayAgo
        WITH SYSTEM_MODE
      ];
    }

    // Messages the user sent in the last 60 seconds, for the rate limit.
    public Integer countRecentUserMessages(Id userId) {
      Datetime oneMinuteAgo = System.now().addSeconds(-60);

      return [
        SELECT COUNT()
        FROM AIConversationMessage__c
        WHERE
          CreatedById = :userId
          AND Sender__c = :AIAssistApplicationConstants.SENDER_USER
          AND CreatedDate >= :oneMinuteAgo
        WITH SYSTEM_MODE
      ];
    }

    // The namespace this code runs in, as ApexClass.NamespacePrefix holds it. Null when the code is not in a namespace.
    public String getPackageNamespace() {
      return AIUsageLimitService.class.getName().contains('.')
        ? AIUsageLimitService.class.getName().substringBefore('.')
        : null;
    }
  }
}
