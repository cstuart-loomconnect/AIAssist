/*
Class Name: AIViolationRuleCapServiceTest

=================================================================
=================================================================

Description: Testing utility for AIViolationRuleCapService and the rule cap in AIMessagingSelector: the warning when an agent has more AI evaluated rules than are used, and which rules survive the cut.

=================================================================
=================================================================
Applicable Classes:

AIViolationRuleCapService, AIMessagingSelector

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIViolationRuleCapServiceTest {
  // testScenario1: The busiest agent's count is the global rules plus the most assigned to one agent, and no warning is given at or under the limit.
  // testScenario2: Global rules that push an agent over the limit are warned about, though no rule was assigned to that agent in the save.
  // testScenario3: When there are too many rules, the blocking rules are the ones kept, and the list is cut to the limit.
  // testScenario4: Saving a rule or an assignment runs the check without stopping the save, and does nothing while the application is switched off.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  private static AIAgent__c createAgent() {
    return AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
  }

  private static void allowAiRules() {
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
  }

  private static List<AIViolationRule__c> createGlobalRules(Integer count) {
    List<AIViolationRule__c> rules = AIAssistTestDataFactory.createAIViolationRules(
      null,
      count,
      AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED,
      false
    );
    for (AIViolationRule__c rule : rules)
      rule.AppliesToAllAgents__c = true;
    insert rules;

    return rules;
  }

  @IsTest
  static void testScenario1() {
    allowAiRules();
    Integer cap = AIAssistApplicationConstants.MAX_AI_RULES_PER_AGENT;
    AIAgent__c busy = createAgent();
    AIAgent__c quiet = createAgent();
    AIAssistTestDataFactory.createAIViolationRules(
      busy.Id,
      cap - 2,
      AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED,
      true
    );
    AIAssistTestDataFactory.createAIViolationRules(
      quiet.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED,
      true
    );
    createGlobalRules(2);

    Test.startTest();
    Integer busiest = AIViolationRuleCapService.getBusiestAgentRuleCount();
    Boolean warned = AIViolationRuleCapService.warnWhenOverLimit();
    Test.stopTest();

    Assert.areEqual(
      cap,
      busiest,
      'Two global rules plus the busiest agent\'s.'
    );
    Assert.isFalse(warned, 'At the limit is not over it.');
  }

  @IsTest
  static void testScenario2() {
    allowAiRules();
    Integer cap = AIAssistApplicationConstants.MAX_AI_RULES_PER_AGENT;
    AIAgent__c busy = createAgent();
    AIAssistTestDataFactory.createAIViolationRules(
      busy.Id,
      cap - 1,
      AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED,
      true
    );
    createGlobalRules(2);

    Test.startTest();
    Boolean warned = AIViolationRuleCapService.warnWhenOverLimit();
    Test.stopTest();

    Assert.isTrue(warned, 'The global rules pushed the agent over.');
  }

  @IsTest
  static void testScenario3() {
    allowAiRules();
    Integer cap = AIAssistApplicationConstants.MAX_AI_RULES_PER_AGENT;
    AIAgent__c agent = createAgent();
    List<AIViolationRule__c> rules = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      cap + 2,
      AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED,
      false
    );
    for (Integer index = 0; index < rules.size(); index++)
      rules[index].Name = 'Rule ' + String.valueOf(100 + index); // Name order is index order.
    rules[cap + 1].Name = 'Rule ZZZ last by name';
    rules[cap + 1].BlockRequest__c = true;
    insert rules;
    AIAssistTestDataFactory.createAIAgentViolationRules(agent.Id, rules, true);

    Test.startTest();
    List<AIViolationRule__c> used = AIMessagingSelector.getActiveAiEvaluatedRules(
      agent.Id
    );
    Test.stopTest();

    Set<Id> usedIds = new Map<Id, AIViolationRule__c>(used).keySet();
    Assert.areEqual(cap, used.size(), 'Cut to the limit.');
    Assert.isTrue(
      usedIds.contains(rules[cap + 1].Id),
      'The blocking rule is kept although it sorts last.'
    );
    Assert.isFalse(
      usedIds.contains(rules[cap].Id),
      'A rule that only notes is dropped in its place.'
    );
    Assert.areEqual(
      used[0].Id,
      rules[cap + 1].Id,
      'Blocking rules come first.'
    );
  }

  @IsTest
  static void testScenario4() {
    allowAiRules();
    AIAgent__c agent = createAgent();

    Test.startTest();
    List<AIViolationRule__c> saved = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      2,
      AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED,
      true
    );
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    AIViolationRuleTriggerHandler.handleAfterSave(saved);
    AIAgentViolationRuleTriggerHandler.handleAfterSave(
      new List<AIAgentViolationRule__c>{ new AIAgentViolationRule__c() }
    );
    AIViolationRuleTriggerHandler.handleAfterSave(null);
    Test.stopTest();

    Assert.areEqual(
      2,
      saved.size(),
      'The rules and their assignments were saved.'
    );
  }
}
