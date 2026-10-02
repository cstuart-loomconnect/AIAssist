/*
Class Name: AIViolationTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIViolationTrigger and AIViolationTriggerHandler: the reviewer stamp, and the rule statistics that grow with each violation without losing counts.

=================================================================
=================================================================
Applicable Classes:

AIViolationTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIViolationTriggerHandlerTest {
  // testScenario1: Marking a violation Reviewed stamps who and when, once.
  // testScenario2: Dismissing stamps the same, and an update that leaves the status New stamps nothing.
  // testScenario3: New violations add to their rule's trigger count and set its last triggered time.
  // testScenario4: Bulk: 201 violations across two rules count once each, with one rule update.
  // testScenario5: A violation with no rule saves and counts nothing.
  // testScenario6: Switched off, nothing is stamped or counted.
  // testScenario7: The handler ignores empty input.
  // testScenario8: An unexpected failure inside the handler is logged and never stops the save.

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
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      true
    )[0];
    AIViolation__c violation = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      null,
      null,
      1,
      true
    )[0];

    Test.startTest();
    violation.ReviewStatus__c = AIAssistApplicationConstants.REVIEW_STATUS_REVIEWED;
    update violation;
    Test.stopTest();

    AIViolation__c reviewed = [
      SELECT ReviewedBy__c, ReviewedDate__c
      FROM AIViolation__c
      WHERE Id = :violation.Id
    ];
    Assert.areEqual(
      UserInfo.getUserId(),
      reviewed.ReviewedBy__c,
      'Who reviewed it.'
    );
    Assert.isNotNull(reviewed.ReviewedDate__c, 'And when.');
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
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
      2,
      true
    );

    Test.startTest();
    violations[0]
      .ReviewStatus__c = AIAssistApplicationConstants.REVIEW_STATUS_DISMISSED;
    update violations[0];
    update violations[1];
    Test.stopTest();

    Map<Id, AIViolation__c> byId = new Map<Id, AIViolation__c>(
      [SELECT ReviewedBy__c FROM AIViolation__c WHERE Id IN :violations]
    );
    Assert.isNotNull(
      byId.get(violations[0].Id).ReviewedBy__c,
      'Dismissed is stamped.'
    );
    Assert.isNull(
      byId.get(violations[1].Id).ReviewedBy__c,
      'Untouched is not.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      true
    )[0];

    Test.startTest();
    AIAssistTestDataFactory.createAIViolations(rule.Id, null, null, 3, true);
    AIAssistTestDataFactory.createAIViolations(rule.Id, null, null, 2, true);
    Test.stopTest();

    AIViolationRule__c updated = [
      SELECT TriggerCount__c, LastTriggeredDate__c
      FROM AIViolationRule__c
      WHERE Id = :rule.Id
    ];
    Assert.areEqual(
      5,
      updated.TriggerCount__c,
      'Each insert added to the stored count.'
    );
    Assert.isNotNull(updated.LastTriggeredDate__c, 'With the time.');
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    List<AIViolationRule__c> rules = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      2,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      true
    );
    List<AIViolation__c> violations = AIAssistTestDataFactory.createAIViolations(
      rules[0].Id,
      null,
      null,
      150,
      false
    );
    violations.addAll(
      AIAssistTestDataFactory.createAIViolations(
        rules[1].Id,
        null,
        null,
        51,
        false
      )
    );
    Integer queries;

    Test.startTest();
    Database.insert(violations, true, AccessLevel.SYSTEM_MODE);
    queries = Limits.getQueries();
    Test.stopTest();

    Map<Id, AIViolationRule__c> byId = new Map<Id, AIViolationRule__c>(
      [SELECT TriggerCount__c FROM AIViolationRule__c WHERE Id IN :rules]
    );
    Assert.areEqual(150, byId.get(rules[0].Id).TriggerCount__c, 'First rule.');
    Assert.areEqual(51, byId.get(rules[1].Id).TriggerCount__c, 'Second rule.');
    Assert.isTrue(queries <= 3, 'One query for the rules: ' + queries);
  }

  @IsTest
  static void testScenario5() {
    AIViolation__c violation = AIAssistTestDataFactory.createAIViolations(
      null,
      null,
      null,
      1,
      false
    )[0];

    Test.startTest();
    Database.insert(violation, true, AccessLevel.SYSTEM_MODE);
    Test.stopTest();

    Assert.isNotNull(violation.Id, 'Saved.');
  }

  @IsTest
  static void testScenario6() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      true
    )[0];

    Test.startTest();
    AIViolation__c violation = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      null,
      null,
      1,
      true
    )[0];
    violation.ReviewStatus__c = AIAssistApplicationConstants.REVIEW_STATUS_REVIEWED;
    update violation;
    Test.stopTest();

    Assert.isTrue(
      [SELECT TriggerCount__c FROM AIViolationRule__c WHERE Id = :rule.Id]
        .TriggerCount__c == null ||
        [SELECT TriggerCount__c FROM AIViolationRule__c WHERE Id = :rule.Id]
        .TriggerCount__c == 0,
      'Not counted.'
    );
    Assert.isNull(
      [SELECT ReviewedBy__c FROM AIViolation__c WHERE Id = :violation.Id]
      .ReviewedBy__c,
      'Not stamped.'
    );
  }

  @IsTest
  static void testScenario7() {
    Test.startTest();
    try {
      AIViolationTriggerHandler.handleBeforeUpdate(null, null);
      AIViolationTriggerHandler.handleAfterInsert(null);
      AIViolationTriggerHandler.handleAfterInsert(new List<AIViolation__c>());
    } catch (Exception ex) {
      Assert.fail('The handler must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIPlatformLog__c],
      'Nothing to do is not a fault.'
    );
  }

  @IsTest
  static void testScenario8() {
    AIViolationTriggerHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    try {
      AIViolationTriggerHandler.handleAfterInsert(
        new List<AIViolation__c>{ new AIViolation__c() }
      );
    } catch (Exception ex) {
      Assert.fail('The handler must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AIPlatformLog__c
        WHERE ClassName__c = 'AIViolationTriggerHandler'
      ],
      'Logged once.'
    );
  }
}
