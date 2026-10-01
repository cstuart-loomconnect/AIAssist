/*
Class Name: AIPlatformLogEventHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIPlatformLogEventHandler: saving published log events as AIPlatformLog__c records.

=================================================================
=================================================================
Applicable Classes:

AIPlatformLogEventHandler
AIPlatformLogEventTrigger

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIPlatformLogEventHandlerTest {
  // testScenario1: afterInsert saves every field of an event on the AIPlatformLog__c record it creates.
  // testScenario2: A bulk of more than two hundred published events reaches the trigger in chunks and every one is saved.
  // testScenario3: While the application is switched off, or platform logging is, the trigger saves nothing.
  // testScenario4: A null or empty list of events is ignored.
  // testScenario5: An unexpected failure inside the handler is logged and never stops the save.

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
    Id relatedRecordId = AIAssistTestDataFactory.createAIAgents(1, true)[0].Id;
    Datetime occurredAt = Datetime.now().addMinutes(-5);

    AIPlatformLogEvent__e event = new AIPlatformLogEvent__e(
      ClassName__c = 'SomeClass',
      MethodName__c = 'someMethod',
      OccurredAt__c = occurredAt,
      UserId__c = UserInfo.getUserId(),
      ExceptionType__c = 'System.DmlException',
      ExceptionMessage__c = 'Short message',
      StackTrace__c = 'Stack trace',
      ExceptionLogDetail__c = 'Long detail',
      RelatedRecordId__c = relatedRecordId,
      Severity__c = AIAssistApplicationConstants.LOG_SEVERITY_WARNING
    );

    Test.startTest();
    AIPlatformLogEventHandler.handleAfterInsert(
      new List<AIPlatformLogEvent__e>{ event }
    );
    Test.stopTest();

    AIPlatformLog__c log = [
      SELECT
        ClassName__c,
        MethodName__c,
        OccurredAt__c,
        User__c,
        ExceptionType__c,
        ExceptionMessage__c,
        StackTrace__c,
        ExceptionLogDetail__c,
        RelatedRecordId__c,
        Severity__c
      FROM AIPlatformLog__c
    ];

    Assert.areEqual('SomeClass', log.ClassName__c, 'Class name.');
    Assert.areEqual('someMethod', log.MethodName__c, 'Method name.');
    Assert.areEqual(occurredAt, log.OccurredAt__c, 'When it happened.');
    Assert.areEqual(UserInfo.getUserId(), log.User__c, 'The user.');
    Assert.areEqual(
      'System.DmlException',
      log.ExceptionType__c,
      'Exception type.'
    );
    Assert.areEqual('Short message', log.ExceptionMessage__c, 'Message.');
    Assert.areEqual('Stack trace', log.StackTrace__c, 'Stack trace.');
    Assert.areEqual('Long detail', log.ExceptionLogDetail__c, 'Detail.');
    Assert.areEqual(
      String.valueOf(relatedRecordId),
      log.RelatedRecordId__c,
      'Related record.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.LOG_SEVERITY_WARNING,
      log.Severity__c,
      'Severity is copied across.'
    );
  }

  @IsTest
  static void testScenario2() {
    List<AIPlatformLogEvent__e> events = new List<AIPlatformLogEvent__e>();
    for (Integer i = 0; i < 201; i++)
      events.add(
        new AIPlatformLogEvent__e(
          ClassName__c = 'BulkClass',
          MethodName__c = 'bulk' + i,
          ExceptionType__c = 'Test',
          ExceptionMessage__c = 'Bulk ' + i,
          Severity__c = AIAssistApplicationConstants.LOG_SEVERITY_INFO
        )
      );

    Test.startTest();
    EventBus.publish(events);
    Test.stopTest();

    Assert.areEqual(
      201,
      [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'BulkClass'],
      'No event may be dropped because it fell in a later chunk.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;

    Test.startTest();
    EventBus.publish(
      new AIPlatformLogEvent__e(
        ClassName__c = 'OffClass',
        MethodName__c = 'off',
        ExceptionType__c = 'Test',
        Severity__c = AIAssistApplicationConstants.LOG_SEVERITY_INFO
      )
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'OffClass'],
      'A switched-off application saves no log records.'
    );
  }

  @IsTest
  static void testScenario4() {
    Test.startTest();
    AIPlatformLogEventHandler.handleAfterInsert(null);
    AIPlatformLogEventHandler.handleAfterInsert(
      new List<AIPlatformLogEvent__e>()
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIPlatformLog__c],
      'There was nothing to save.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIPlatformLogEventHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    try {
      AIPlatformLogEventHandler.handleAfterInsert(
        new List<AIPlatformLogEvent__e>{ new AIPlatformLogEvent__e() }
      );
    } catch (Exception ex) {
      Assert.fail('The handler must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIPlatformLog__c],
      'A failure saving log events is not itself logged, which would loop.'
    );
  }
}
