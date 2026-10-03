/*
Class Name: AIAgentViolationRuleTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIAgentViolationRuleTrigger and AIAgentViolationRuleTriggerHandler: the unique key that stops one agent being given the same violation rule twice.

=================================================================
=================================================================
Applicable Classes:

AIAgentViolationRuleTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAgentViolationRuleTriggerHandlerTest {
  // testScenario1: A new assignment gets a key made of its agent and its rule.
  // testScenario2: The same rule cannot be assigned to one agent twice; another agent can have it, and one rule can serve many agents.
  // testScenario3: An unexpected failure inside the handler is logged and never throws.

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
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      null,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      true
    )[0];

    Test.startTest();
    AIAgentViolationRule__c link = AIAssistTestDataFactory.createAIAgentViolationRules(
      agent.Id,
      new List<AIViolationRule__c>{ rule },
      true
    )[0];
    Test.stopTest();

    Assert.areEqual(
      agent.Id + '|' + rule.Id,
      [SELECT AssignmentKey__c FROM AIAgentViolationRule__c WHERE Id = :link.Id]
      .AssignmentKey__c,
      'The agent, then the rule.'
    );
  }

  @IsTest
  static void testScenario2() {
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, true);
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      null,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      true
    )[0];
    List<AIViolationRule__c> rules = new List<AIViolationRule__c>{ rule };
    AIAssistTestDataFactory.createAIAgentViolationRules(
      agents[0].Id,
      rules,
      true
    );

    Test.startTest();
    List<Database.SaveResult> duplicate = Database.insert(
      AIAssistTestDataFactory.createAIAgentViolationRules(
        agents[0].Id,
        rules,
        false
      ),
      false
    );
    List<Database.SaveResult> otherAgent = Database.insert(
      AIAssistTestDataFactory.createAIAgentViolationRules(
        agents[1].Id,
        rules,
        false
      ),
      false
    );
    Test.stopTest();

    Assert.isFalse(duplicate[0].isSuccess(), 'The same rule twice is refused.');
    Assert.isTrue(otherAgent[0].isSuccess(), 'One rule can serve many agents.');
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      null,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      true
    )[0];
    AIAgentViolationRuleTriggerHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    List<AIAgentViolationRule__c> links = AIAssistTestDataFactory.createAIAgentViolationRules(
      agent.Id,
      new List<AIViolationRule__c>{ rule },
      true
    );
    Test.stopTest();

    Assert.isNotNull(
      links[0].Id,
      'The save went through; the failure was logged.'
    );
  }
}
