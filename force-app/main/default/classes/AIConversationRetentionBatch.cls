/*
Class Name: AIConversationRetentionBatch

=================================================================
=================================================================

Description: Deletes conversations once they have passed RetentionExpiryDate__c, skipping any conversation on
legal hold (IsOnLegalHold__c). The conversation's messages, steps, masking records, feedback and PII
mappings go with it because they are its children.

Runs in system mode because no user holds Delete on conversations (the security model keeps deletion
inside the package). It does nothing while the application is switched off.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from the old retention batch. Skips legal holds, runs in explicit system mode, deletes through the package gateway and logs once per batch.
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
    if (!AIAssistSettingsService.isEnabled())
      return;

    AIMessagingDataService.deleteAndLogFailures(
      scope,
      'AIConversationRetentionBatch',
      'execute'
    );
  }

  public void finish(Database.BatchableContext context) {
  }
}
