/*
Class Name: AIConversationRetentionRecalcBatch

=================================================================
=================================================================

Description: Recalculates RetentionExpiryDate__c on every conversation of the agents whose
retention settings changed (ConversationRetentionDays__c or RetentionTrigger__c), started by
AIAgentTriggerHandler. Without it a change applies only to conversations created afterwards, so
shortening an agent's retention would leave its older conversations to live out the old period.

The same rules the triggers apply as a conversation is created, messaged and closed:
- Retention Days blank or under 1: no expiry date (kept indefinitely). A date already set is cleared.
- Conversation Created Date: created date plus the days.
- Last Message Date: the last message (or creation, with no message yet) plus the days.
- Conversation Closed Date: the close time plus the days; no date while the conversation is open.
Dates are in GMT, as in the triggers. A conversation on legal hold has its date recalculated too: the
hold, not the date, is what stops the retention batch deleting it.

Runs whether or not the application is switched on, in system mode: retention applies to every user's
conversations. Only conversations whose date actually changes are written.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public inherited sharing class AIConversationRetentionRecalcBatch implements Database.Batchable<SObject> {
  private Set<Id> agentIds;

  public AIConversationRetentionRecalcBatch(Set<Id> agentIds) {
    this.agentIds = agentIds == null ? new Set<Id>() : agentIds;
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [
        SELECT
          Id,
          CreatedDate,
          LastMessageTimestamp__c,
          ConversationClosedTimestamp__c,
          Status__c,
          RetentionExpiryDate__c,
          AIAgent__r.ConversationRetentionDays__c,
          AIAgent__r.RetentionTrigger__c
        FROM AIConversation__c
        WHERE AIAgent__c IN :agentIds
        WITH SYSTEM_MODE
      ]
    );
  }

  public void execute(
    Database.BatchableContext context,
    List<AIConversation__c> scope
  ) {
    List<AIConversation__c> changed = new List<AIConversation__c>();

    for (AIConversation__c conversation : scope) {
      Decimal retentionDays = conversation.AIAgent__r.ConversationRetentionDays__c;
      String retentionTrigger = conversation.AIAgent__r.RetentionTrigger__c;
      Datetime countedFrom = null;

      if (retentionDays != null && retentionDays >= 1) {
        if (
          retentionTrigger ==
          AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE
        )
          countedFrom = conversation.CreatedDate;
        else if (
          retentionTrigger ==
          AIAssistApplicationConstants.RETENTION_TRIGGER_LAST_MESSAGE_DATE
        )
          countedFrom = conversation.LastMessageTimestamp__c == null
            ? conversation.CreatedDate
            : conversation.LastMessageTimestamp__c;
        else if (
          retentionTrigger ==
          AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE &&
          conversation.Status__c ==
          AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED
        )
          countedFrom = conversation.ConversationClosedTimestamp__c;
      }

      Date expiryDate = countedFrom == null
        ? null
        : countedFrom.dateGmt().addDays(Integer.valueOf(retentionDays));
      if (expiryDate != conversation.RetentionExpiryDate__c)
        changed.add(
          new AIConversation__c(
            Id = conversation.Id,
            RetentionExpiryDate__c = expiryDate
          )
        );
    }

    AIMessagingDataService.updateAndLogFailures(
      changed,
      'AIConversationRetentionRecalcBatch',
      'execute'
    );
  }

  public void finish(Database.BatchableContext context) {
  }
}
