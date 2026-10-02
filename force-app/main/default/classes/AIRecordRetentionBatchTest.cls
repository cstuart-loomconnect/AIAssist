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
  // testScenario5: Switched off, nothing is deleted.

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
      1,
      [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'Old'],
      'Kept while off.'
    );
  }
}
