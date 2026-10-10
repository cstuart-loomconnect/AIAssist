/*
Class Name: AIConversationRetentionBatch

=================================================================
=================================================================

Description: Deletes conversations once they have passed RetentionExpiryDate__c, skipping any conversation on
legal hold (IsOnLegalHold__c). The conversation's messages, steps, masking records and PII mappings go
with it because they are its children. Feedback only looks up to the conversation, so it is deleted here
first.

Runs in system mode because no user holds Delete on conversations (the security model keeps deletion
inside the package). It runs whether or not the application is switched on: switching AI Assist off must
not stop the conversations it already holds from expiring.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from the old retention batch. Skips legal holds, runs in explicit system mode, deletes through the package gateway and logs once per batch.
3.0          Chandler Stuart          Runs while the application is off. Deletes the conversation's feedback.
*/

public inherited sharing class AIConversationRetentionBatch implements Database.Batchable<SObject> {
  public Database.QueryLocator start(Database.BatchableContext context) {
    Date today = Datetime.now().dateGmt();

    return Database.getQueryLocator(
      [
        SELECT Id
        FROM AIConversation__c
        WHERE
          RetentionExpiryDate__c != NULL
          AND RetentionExpiryDate__c <= :today
          AND IsOnLegalHold__c = FALSE
        WITH SYSTEM_MODE
      ]
    );
  }

  public void execute(
    Database.BatchableContext context,
    List<AIConversation__c> scope
  ) {
    // Feedback only looks up to its conversation, so it would be left behind with a blank conversation: it goes first.
    AIMessagingDataService.deleteAndLogFailures(
      [
        SELECT Id
        FROM AIFeedback__c
        WHERE AIConversation__c IN :scope
        WITH SYSTEM_MODE
      ],
      'AIConversationRetentionBatch',
      'execute'
    );
    AIMessagingDataService.deleteAndLogFailures(
      scope,
      'AIConversationRetentionBatch',
      'execute'
    );
  }

  public void finish(Database.BatchableContext context) {
  }
}
