/*
Class Name: AIRecordRetentionBatch

=================================================================
=================================================================

Description: Deletes the package's platform logs and violations once they are older than the lifetime set on
AIAssistSettings__c (PlatformLogRetentionDays__c, ViolationRetentionDays__c). A blank or zero lifetime
keeps the records indefinitely. A violation that is still New is kept whatever its age, because
deleting evidence nobody has reviewed would hide it.

One instance handles one object, chosen by the constructor, so each runs in its own transactions.
System mode: no user holds Delete on either object. It does nothing while the application is off.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development. Applies the two retention settings the object model added.
*/

public inherited sharing class AIRecordRetentionBatch implements Database.Batchable<SObject> {
  public static final String LOGS = 'Logs';
  public static final String VIOLATIONS = 'Violations';

  private String recordKind;

  public AIRecordRetentionBatch(String recordKind) {
    this.recordKind = recordKind;
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    AIAssistSettings__c settings = AIAssistSettingsService.getSettings();
    Decimal lifetimeDays = recordKind == VIOLATIONS
      ? settings.ViolationRetentionDays__c
      : settings.PlatformLogRetentionDays__c;
    Boolean isKept = lifetimeDays == null || lifetimeDays < 1;
    Datetime cutoff = isKept
      ? Datetime.newInstance(1900, 1, 1)
      : System.now().addDays(-Integer.valueOf(lifetimeDays));

    if (recordKind == VIOLATIONS) {
      return Database.getQueryLocator(
        [
          SELECT Id
          FROM AIViolation__c
          WHERE
            CreatedDate < :cutoff
            AND ReviewStatus__c != :AIAssistApplicationConstants.REVIEW_STATUS_NEW
          WITH SYSTEM_MODE
        ]
      );
    }

    return Database.getQueryLocator(
      [
        SELECT Id
        FROM AIPlatformLog__c
        WHERE CreatedDate < :cutoff
        WITH SYSTEM_MODE
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    if (!AIAssistSettingsService.isEnabled())
      return;

    AIMessagingDataService.deleteAndLogFailures(
      scope,
      'AIRecordRetentionBatch',
      'execute'
    );
  }

  public void finish(Database.BatchableContext context) {
  }
}
