/*
Class Name: AIRecordRetentionBatchTest

=================================================================
=================================================================

Description: Testing utility for AIRecordRetentionBatch: old platform logs and reviewed violations are deleted by the lifetimes in the settings, and unreviewed ones are kept.

=================================================================
=================================================================
Applicable Classes:

AIRecordRetentionBatch

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIRecordRetentionBatchTest {
  // testScenario1: Logs older than the platform log lifetime are deleted and newer ones kept.
  // testScenario2: A blank or zero lifetime keeps every log.
  // testScenario3: Violations older than the violation lifetime are deleted once reviewed or dismissed, and an unreviewed one is kept whatever its age.
  // testScenario4: The boundary: a log one day inside the lifetime is kept.
  // testScenario5: Retention still runs while the application is switched off.
  // testScenario6: Steps older than the step lifetime are deleted and newer ones kept, and messages older than the message lifetime are deleted with their steps while the conversation stays.
  // testScenario7: Steps and messages of a conversation on legal hold are kept however old they are.
  // testScenario8: The defaults are 7 days for steps and 30 for messages and logs, a blank lifetime keeps everything, and a chained run starts the next kind.

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
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.PlatformLogRetentionDays__c = 30;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    List<AIPlatformLog__c> logs = new List<AIPlatformLog__c>{
      new AIPlatformLog__c(ClassName__c = 'Old'),
      new AIPlatformLog__c(ClassName__c = 'Recent')
    };
    insert logs;
    Test.setCreatedDate(logs[0].Id, System.now().addDays(-31));

    Test.startTest();
    Database.executeBatch(
      new AIRecordRetentionBatch(AIRecordRetentionBatch.LOGS),
      200
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'Old'],
      'The old log is deleted.'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'Recent'],
      'The recent one is kept.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.PlatformLogRetentionDays__c = null;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    AIPlatformLog__c log = new AIPlatformLog__c(ClassName__c = 'Old');
    insert log;
    Test.setCreatedDate(log.Id, System.now().addDays(-4000));

    Test.startTest();
    Database.executeBatch(
      new AIRecordRetentionBatch(AIRecordRetentionBatch.LOGS),
      200
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'Old'],
      'Kept indefinitely.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.ViolationRetentionDays__c = 365;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      true
    )[0];
    List<AIViolation__c> violations = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      null,
      null,
      3,
      false
    );
    violations[0]
      .ReviewStatus__c = AIAssistApplicationConstants.REVIEW_STATUS_REVIEWED;
    violations[1]
      .ReviewStatus__c = AIAssistApplicationConstants.REVIEW_STATUS_DISMISSED;
    insert violations;
    for (AIViolation__c violation : violations)
      Test.setCreatedDate(violation.Id, System.now().addDays(-400));

    Test.startTest();
    Database.executeBatch(
      new AIRecordRetentionBatch(AIRecordRetentionBatch.VIOLATIONS),
      200
    );
    Test.stopTest();

    Map<Id, AIViolation__c> remaining = new Map<Id, AIViolation__c>(
      [SELECT Id FROM AIViolation__c]
    );
    Assert.isFalse(
      remaining.containsKey(violations[0].Id),
      'Reviewed and old: deleted.'
    );
    Assert.isFalse(
      remaining.containsKey(violations[1].Id),
      'Dismissed and old: deleted.'
    );
    Assert.isTrue(
      remaining.containsKey(violations[2].Id),
      'Unreviewed: kept, so evidence nobody has seen is not lost.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.PlatformLogRetentionDays__c = 30;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    AIPlatformLog__c log = new AIPlatformLog__c(ClassName__c = 'Edge');
    insert log;
    Test.setCreatedDate(log.Id, System.now().addDays(-29));

    Test.startTest();
    Database.executeBatch(
      new AIRecordRetentionBatch(AIRecordRetentionBatch.LOGS),
      200
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'Edge'],
      'Kept.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    AIAssistSettings__c lifetime = AIAssistSettings__c.getOrgDefaults();
    lifetime.PlatformLogRetentionDays__c = 1;
    update lifetime;
    AIAssistSettingsService.cachedSettings = null;
    AIPlatformLog__c log = new AIPlatformLog__c(ClassName__c = 'Old');
    insert log;
    Test.setCreatedDate(log.Id, System.now().addDays(-10));

    Test.startTest();
    Database.executeBatch(
      new AIRecordRetentionBatch(AIRecordRetentionBatch.LOGS),
      200
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'Old'],
      'Deleted although the application is off.'
    );
  }

  // A conversation with two user messages. The first is 40 days old, with a step as old. The second is new, with one step 10 days old and one 40 days old.
  private class Aged {
    AIConversation__c conversation;
    List<AIConversationMessage__c> messages;
    List<AIExecutionStep__c> steps;
  }

  private static Aged createAged(Boolean isOnLegalHold) {
    Aged aged = new Aged();
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    aged.conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      false
    )[0];
    aged.conversation.IsOnLegalHold__c = isOnLegalHold;
    insert aged.conversation;
    aged.messages = AIAssistTestDataFactory.createAIConversationMessages(
      aged.conversation.Id,
      5,
      2,
      true
    );
    aged.steps = AIAssistTestDataFactory.createAIExecutionSteps(
      aged.messages[0].Id,
      1,
      false
    );
    aged.steps.addAll(
      AIAssistTestDataFactory.createAIExecutionSteps(
        aged.messages[1].Id,
        2,
        false
      )
    );
    insert aged.steps;
    Test.setCreatedDate(aged.messages[0].Id, System.now().addDays(-40));
    Test.setCreatedDate(aged.steps[0].Id, System.now().addDays(-40));
    Test.setCreatedDate(aged.steps[1].Id, System.now().addDays(-10));
    Test.setCreatedDate(aged.steps[2].Id, System.now().addDays(-40));

    return aged;
  }

  private static void setLifetimes(Decimal stepDays, Decimal messageDays) {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.StepRetentionDays__c = stepDays;
    settings.MessageRetentionDays__c = messageDays;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
  }

  private static void purgeStepsAndMessages() {
    Database.executeBatch(
      new AIRecordRetentionBatch(AIRecordRetentionBatch.STEPS),
      200
    );
    Database.executeBatch(
      new AIRecordRetentionBatch(AIRecordRetentionBatch.MESSAGES),
      200
    );
  }

  @IsTest
  static void testScenario6() {
    Aged aged = createAged(false);
    setLifetimes(20, 30);

    Test.startTest();
    purgeStepsAndMessages();
    Test.stopTest();

    Assert.areEqual(
      new Set<Id>{ aged.steps[1].Id },
      new Map<Id, AIExecutionStep__c>([SELECT Id FROM AIExecutionStep__c])
        .keySet(),
      'The 40 day old steps are purged, also on a message that stays, and the 10 day old one kept.'
    );
    Assert.areEqual(
      new Set<Id>{ aged.messages[1].Id },
      new Map<Id, AIConversationMessage__c>(
          [SELECT Id FROM AIConversationMessage__c]
        )
        .keySet(),
      'The 40 day old message is purged and the new one kept.'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AIConversation__c WHERE Id = :aged.conversation.Id],
      'The conversation itself stays: its own retention decides that.'
    );
  }

  @IsTest
  static void testScenario7() {
    Aged aged = createAged(true);
    setLifetimes(1, 1);

    Test.startTest();
    purgeStepsAndMessages();
    Test.stopTest();

    Assert.areEqual(
      3,
      [SELECT COUNT() FROM AIExecutionStep__c],
      'Every step of a held conversation is kept.'
    );
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM AIConversationMessage__c],
      'And every message.'
    );
    Assert.isNotNull(aged.conversation.Id);
  }

  @IsTest
  static void testScenario8() {
    Aged aged = createAged(false);
    AIAssistSettings__c defaults = (AIAssistSettings__c) AIAssistSettings__c.SObjectType.newSObject(
      null,
      true
    );
    setLifetimes(null, 0);

    Test.startTest();
    purgeStepsAndMessages();
    Database.executeBatch(new AIRecordRetentionBatch(), 200);
    new AIRecordRetentionBatch(AIRecordRetentionBatch.LOGS).finish(null);
    Test.stopTest();

    Assert.areEqual(7, defaults.StepRetentionDays__c, 'Steps: 7 days.');
    Assert.areEqual(30, defaults.MessageRetentionDays__c, 'Messages: 30.');
    Assert.areEqual(30, defaults.PlatformLogRetentionDays__c, 'Logs: 30.');
    Assert.areEqual(
      3,
      [SELECT COUNT() FROM AIExecutionStep__c],
      'A blank lifetime keeps every step.'
    );
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM AIConversationMessage__c],
      'A zero lifetime keeps every message.'
    );
    Assert.isTrue(
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'AIRecordRetentionBatch'
      ] >= 3,
      'The chained run was started beside the two single ones.'
    );
    Assert.isNotNull(aged.conversation.Id);
  }
}
