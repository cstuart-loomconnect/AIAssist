/*
Class Name: AIConversationRetentionBatch

=================================================================
=================================================================

Description: Deletes conversations that have passed their retention expiry date, skipping any on legal hold.

Step 1: Find conversations past RetentionExpiryDate__c that are not on legal hold
Step 2: Delete their feedback first, because feedback only looks up to the conversation
Step 3: Delete the conversations, which removes their messages, steps, masking records and PII mappings

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIConversationRetentionBatch implements Database.Batchable<SObject> {
  // Finds the expired conversations that are not on legal hold. It runs in system mode because no user holds Delete on conversations.
  public Database.QueryLocator start(Database.BatchableContext context) {
    // [1] Work out today's date in GMT
    Date today = Datetime.now().dateGmt();

    // [2] Return every conversation that has expired and is not on legal hold
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

  // Deletes each batch of conversations and their feedback. It runs whether or not the application is switched on, so switching AI Assist off never stops conversations expiring.
  public void execute(
    Database.BatchableContext context,
    List<AIConversation__c> scope
  ) {
    // [1] Delete the feedback first, because it only looks up to its conversation and would be left behind with a blank conversation
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

    // [2] Delete the conversations, which removes their child records with them
    AIMessagingDataService.deleteAndLogFailures(
      scope,
      'AIConversationRetentionBatch',
      'execute'
    );
  }

  // Nothing to do when the batch finishes.
  public void finish(Database.BatchableContext context) {
  }
}
