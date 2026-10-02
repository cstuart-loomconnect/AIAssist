/*
Class Name: AIConversationIdleBatch

=================================================================
=================================================================

Description: Closes active conversations that have sat idle longer than their agent's IdleTimeoutMinutes__c.
Idle time runs from the conversation's last message (LastMessageTimestamp__c, kept by the message
trigger) or, with no messages yet, from its creation, so no second query on the messages is needed.

Safe in the subscriber's org: it reads and writes only the package's own conversations, in system
mode because conversations are private to their owner and the job must see them all. It does nothing
while the application is switched off, skips a conversation whose reply is still being produced (the
processing lock), and closes in the package's own gateway so one bad record does not stop the rest.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from AIConversationIdleTimeoutBatch. Uses the stored last message time instead of an aggregate query, skips conversations being processed, stamps the close time itself and respects the application switch.
*/

public inherited sharing class AIConversationIdleBatch implements Database.Batchable<SObject> {
  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [
        SELECT
          Id,
          CreatedDate,
          LastMessageTimestamp__c,
          ProcessingLockedUntil__c,
          AIAgent__r.IdleTimeoutMinutes__c
        FROM AIConversation__c
        WHERE
          Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE
          AND AIAgent__r.IdleTimeoutMinutes__c != NULL
        WITH SYSTEM_MODE
      ]
    );
  }

  public void execute(
    Database.BatchableContext context,
    List<AIConversation__c> scope
  ) {
    if (!AIAssistSettingsService.isEnabled())
      return;

    Datetime currentTime = System.now();
    List<AIConversation__c> conversationsToClose = new List<AIConversation__c>();

    for (AIConversation__c conversation : scope) {
      if (
        conversation.ProcessingLockedUntil__c != null &&
        conversation.ProcessingLockedUntil__c > currentTime
      )
        continue; // A reply is being produced.

      Datetime lastActivity = conversation.LastMessageTimestamp__c == null
        ? conversation.CreatedDate
        : conversation.LastMessageTimestamp__c;
      if (
        lastActivity.addMinutes(
          Integer.valueOf(conversation.AIAgent__r.IdleTimeoutMinutes__c)
        ) > currentTime
      )
        continue;

      conversationsToClose.add(
        new AIConversation__c(
          Id = conversation.Id,
          Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED,
          ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_IDLE_TIMEOUT,
          ConversationClosedTimestamp__c = currentTime
        )
      );
    }

    AIMessagingDataService.updateAndLogFailures(
      conversationsToClose,
      'AIConversationIdleBatch',
      'execute'
    );
  }

  public void finish(Database.BatchableContext context) {
  }
}
