/*
Class Name: AIViolationRuleTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIViolationRuleTrigger and AIViolationRuleTriggerHandler: the plan check on AI evaluated rules, and that a signal tag can belong to one rule only.

=================================================================
=================================================================
Applicable Classes:

AIViolationRuleTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIViolationRuleTriggerHandlerTest {
  // testScenario1: A rule of either kind saves on a plan that includes AI evaluated rules.
  // testScenario2: An active AI evaluated rule is refused on a plan that does not include them, and a deterministic one is not.
  // testScenario3: An inactive AI evaluated rule saves on a plan without them, and activating it is refused.
  // testScenario4: A signal tag already used by another rule is refused by the field itself.
  // testScenario5: Bulk: 201 rules save with no queries from the handler.
  // testScenario6: Switched off, the plan is not checked, and the handler ignores empty input.
  // testScenario7: An unexpected failure inside the handler is logged and never stops the save.

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
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
    List<AIViolationRule__c> rules = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED,
      false
    );
    rules.addAll(
      AIAssistTestDataFactory.createAIViolationRules(
        agent.Id,
        1,
        AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
        false
      )
    );

    Test.startTest();
    insert rules;
    Test.stopTest();

    Assert.areEqual(2, [SELECT COUNT() FROM AIViolationRule__c], 'Both saved.');
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      false
    );
    List<AIViolationRule__c> rules = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED,
      false
    );
    rules.addAll(
      AIAssistTestDataFactory.createAIViolationRules(
        agent.Id,
        1,
        AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
        false
      )
    );
    List<Database.SaveResult> results;

    Test.startTest();
    results = Database.insert(rules, false);
    Test.stopTest();

    Assert.isFalse(results[0].isSuccess(), 'The AI rule is refused.');
    Assert.areEqual(
      Label.AI_Error_Plan_AI_Rules_Not_Included,
      results[0].getErrors()[0].getMessage(),
      'The text is the Custom Label.'
    );
    Assert.isTrue(results[1].isSuccess(), 'The deterministic rule saves.');
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED,
      false
    )[0];
    rule.IsActive__c = false;
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      false
    );
    Database.SaveResult activation;

    Test.startTest();
    insert rule;
    activation = Database.update(
      new AIViolationRule__c(Id = rule.Id, IsActive__c = true),
      false
    );
    Test.stopTest();

    Assert.isNotNull(rule.Id, 'The inactive rule saved.');
    Assert.isFalse(activation.isSuccess(), 'Activating it is refused.');
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
    AIViolationRule__c existing = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      true
    )[0];
    AIViolationRule__c duplicate = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      false
    )[0];
    duplicate.SignalTag__c = existing.SignalTag__c;
    Database.SaveResult result;

    Test.startTest();
    result = Database.insert(duplicate, false);
    Test.stopTest();

    Assert.isFalse(result.isSuccess(), 'Refused.');
    Assert.areEqual(
      StatusCode.DUPLICATE_VALUE,
      result.getErrors()[0].getStatusCode(),
      'By the unique field, so no code can bypass it.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
    List<AIViolationRule__c> rules = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      201,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      false
    );
    Integer queries;

    Test.startTest();
    insert rules;
    queries = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(
      201,
      [SELECT COUNT() FROM AIViolationRule__c],
      'All saved.'
    );
    Assert.isTrue(queries <= 2, 'The handler does not query: ' + queries);
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
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      false
    );
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED,
      false
    )[0];

    Test.startTest();
    insert rule;
    AIViolationRuleTriggerHandler.handleBeforeInsert(null);
    Test.stopTest();

    Assert.isNotNull(rule.Id, 'Saved, because the trigger is off.');
  }

  @IsTest
  static void testScenario7() {
    AIViolationRuleTriggerHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    try {
      AIViolationRuleTriggerHandler.handleBeforeInsert(
        new List<AIViolationRule__c>{ new AIViolationRule__c() }
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
        WHERE ClassName__c = 'AIViolationRuleTriggerHandler'
      ],
      'Logged once.'
    );
  }
}
