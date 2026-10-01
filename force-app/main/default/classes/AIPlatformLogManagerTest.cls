/*
Class Name: AIPlatformLogManagerTest

=================================================================
=================================================================

Description: Testing utility for AIPlatformLogManager: what is published as an event, what is saved as a log, and that logging never throws.

=================================================================
=================================================================
Applicable Classes:

AIPlatformLogManager
AIPlatformLogEventHandler
AIPlatformLogEventTrigger

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIPlatformLogManagerTest {
  // testScenario1: logException publishes one error event that is saved as one AIPlatformLog__c with the class, method, exception type, message, user and the record the DML failed on.
  // testScenario2: A message longer than the event field is cut to 255 characters so the publish succeeds, and the full text stays in the detail.
  // testScenario3: logExceptions logs a batch of save results as one entry that counts the failures and names each failed record and its error.
  // testScenario4: A batch where every record saved logs nothing.
  // testScenario5: logCustomMessage records a warning with the related record, and does nothing when both the message and the detail are blank.
  // testScenario6: Missing input is ignored without throwing: no exception, no class name, no method name and no save results.
  // testScenario7: With exception logging switched off nothing is published, so nothing is saved.
  // testScenario8: With platform logging switched off events are published but dropped rather than saved as records.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  @IsTest
  static void testScenario1() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    agent.ConversationRetentionDays__c = -1;
    DmlException dmlException;

    try {
      update agent;
    } catch (DmlException ex) {
      dmlException = ex;
    }

    Test.startTest();
    AIPlatformLogManager.logException(
      dmlException,
      'AIPlatformLogManagerTest',
      'testScenario1'
    );
    Test.stopTest();

    List<AIPlatformLog__c> logs = [
      SELECT
        ClassName__c,
        MethodName__c,
        ExceptionType__c,
        ExceptionMessage__c,
        Severity__c,
        User__c,
        OccurredAt__c,
        ExceptionLogDetail__c,
        RelatedRecordId__c
      FROM AIPlatformLog__c
    ];

    Assert.areEqual(1, logs.size(), 'One exception is one log.');
    Assert.areEqual(
      'AIPlatformLogManagerTest',
      logs[0].ClassName__c,
      'The class that logged it.'
    );
    Assert.areEqual(
      'testScenario1',
      logs[0].MethodName__c,
      'The method that logged it.'
    );
    Assert.areEqual(
      'System.DmlException',
      logs[0].ExceptionType__c,
      'The exception type.'
    );
    Assert.isTrue(
      logs[0].ExceptionMessage__c.contains('1 or more'),
      'The exception message is the validation rule\'s.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.LOG_SEVERITY_ERROR,
      logs[0].Severity__c,
      'An exception is an error.'
    );
    Assert.areEqual(
      UserInfo.getUserId(),
      logs[0].User__c,
      'The user it happened to.'
    );
    Assert.isNotNull(logs[0].OccurredAt__c, 'When it happened.');
    Assert.areEqual(
      String.valueOf(agent.Id),
      logs[0].RelatedRecordId__c,
      'The record the DML failed on.'
    );
    Assert.isTrue(
      logs[0].ExceptionLogDetail__c.contains('testScenario1'),
      'The detail names the method.'
    );
  }

  @IsTest
  static void testScenario2() {
    String longMessage = 'x'.repeat(1000);

    Test.startTest();
    AIPlatformLogManager.logException(
      new NullPointerException(),
      'AIPlatformLogManagerTest',
      'testScenario2'
    );
    AIPlatformLogManager.logCustomMessage(
      longMessage,
      longMessage,
      'AIPlatformLogManagerTest',
      'testScenario2',
      null
    );
    Test.stopTest();

    AIPlatformLog__c customLog = [
      SELECT ExceptionMessage__c, ExceptionLogDetail__c
      FROM AIPlatformLog__c
      WHERE
        ExceptionType__c = :AIAssistApplicationConstants.LOG_TYPE_CUSTOM_MESSAGE
    ];

    Assert.areEqual(
      255,
      customLog.ExceptionMessage__c.length(),
      'The message is cut to the field size, or the whole publish would be refused.'
    );
    Assert.areEqual(
      1000,
      customLog.ExceptionLogDetail__c.length(),
      'The detail keeps the full text.'
    );
  }

  @IsTest
  static void testScenario3() {
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, false);
    agents[1].ConversationRetentionDays__c = -1; // Refused by the object model's validation rule.
    List<Database.SaveResult> saveResults = Database.insert(agents, false);

    Test.startTest();
    AIPlatformLogManager.logExceptions(
      saveResults,
      'AIPlatformLogManagerTest',
      'testScenario3'
    );
    Test.stopTest();

    List<AIPlatformLog__c> logs = [
      SELECT
        ExceptionType__c,
        ExceptionMessage__c,
        ExceptionLogDetail__c,
        Severity__c
      FROM AIPlatformLog__c
    ];

    Assert.areEqual(
      1,
      logs.size(),
      'A batch with failures is one entry, not one per record.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.LOG_TYPE_DML_FAILURE,
      logs[0].ExceptionType__c,
      'It is a save failure.'
    );
    Assert.areEqual(
      '1 of 2 record(s) failed to save',
      logs[0].ExceptionMessage__c,
      'It counts the failures.'
    );
    Assert.isTrue(
      logs[0].ExceptionLogDetail__c.contains('record 2 of 2'),
      'The detail names the failed record.'
    );
    Assert.isTrue(
      logs[0]
        .ExceptionLogDetail__c.contains('FIELD_CUSTOM_VALIDATION_EXCEPTION'),
      'And the status code of the refusal.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.LOG_SEVERITY_ERROR,
      logs[0].Severity__c,
      'A save failure is an error.'
    );
  }

  @IsTest
  static void testScenario4() {
    List<Database.SaveResult> saveResults = Database.insert(
      AIAssistTestDataFactory.createAIAgents(2, false),
      false
    );

    Test.startTest();
    AIPlatformLogManager.logExceptions(
      saveResults,
      'AIPlatformLogManagerTest',
      'testScenario4'
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIPlatformLog__c],
      'Nothing failed, so nothing is logged.'
    );
  }

  @IsTest
  static void testScenario5() {
    Id relatedRecordId = AIAssistTestDataFactory.createAIAgents(1, true)[0].Id;

    Test.startTest();
    AIPlatformLogManager.logCustomMessage(
      'Worth knowing',
      'Some detail',
      'AIPlatformLogManagerTest',
      'testScenario5',
      relatedRecordId
    );
    AIPlatformLogManager.logCustomMessage(
      null,
      '',
      'AIPlatformLogManagerTest',
      'testScenario5',
      null
    );
    Test.stopTest();

    List<AIPlatformLog__c> logs = [
      SELECT
        ExceptionType__c,
        Severity__c,
        RelatedRecordId__c,
        ExceptionLogDetail__c
      FROM AIPlatformLog__c
    ];

    Assert.areEqual(1, logs.size(), 'The blank message is not logged.');
    Assert.areEqual(
      AIAssistApplicationConstants.LOG_TYPE_CUSTOM_MESSAGE,
      logs[0].ExceptionType__c,
      'A custom message.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.LOG_SEVERITY_WARNING,
      logs[0].Severity__c,
      'A custom message is a warning.'
    );
    Assert.areEqual(
      String.valueOf(relatedRecordId),
      logs[0].RelatedRecordId__c,
      'The record it is about.'
    );
    Assert.areEqual(
      'Some detail',
      logs[0].ExceptionLogDetail__c,
      'The detail.'
    );
  }

  @IsTest
  static void testScenario6() {
    Test.startTest();
    AIPlatformLogManager.logException(
      null,
      'AIPlatformLogManagerTest',
      'testScenario6'
    );
    AIPlatformLogManager.logException(
      new NullPointerException(),
      '',
      'testScenario6'
    );
    AIPlatformLogManager.logException(
      new NullPointerException(),
      'AIPlatformLogManagerTest',
      null
    );
    AIPlatformLogManager.logExceptions(
      null,
      'AIPlatformLogManagerTest',
      'testScenario6'
    );
    AIPlatformLogManager.logExceptions(
      new List<Database.SaveResult>(),
      'AIPlatformLogManagerTest',
      'testScenario6'
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIPlatformLog__c],
      'Invalid input must log nothing, and must not throw.'
    );
  }

  @IsTest
  static void testScenario7() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsExceptionLoggingEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;

    Test.startTest();
    AIPlatformLogManager.logException(
      new NullPointerException(),
      'AIPlatformLogManagerTest',
      'testScenario7'
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIPlatformLog__c],
      'Nothing was published, so nothing was saved.'
    );
  }

  @IsTest
  static void testScenario8() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsPlatformLoggingEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;

    Test.startTest();
    AIPlatformLogManager.logException(
      new NullPointerException(),
      'AIPlatformLogManagerTest',
      'testScenario8'
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIPlatformLog__c],
      'With platform logging off the event is dropped rather than saved.'
    );
  }
}
