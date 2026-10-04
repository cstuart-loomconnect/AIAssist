/*
Class Name: AIAgentObjectTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIAgentObjectTrigger and AIAgentObjectTriggerHandler: the object name is checked against the org, stored as the org spells it, and cannot be added to one agent twice.

=================================================================
=================================================================
Applicable Classes:

AIAgentObjectTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAgentObjectTriggerHandlerTest {
  // testScenario1: An object that exists is saved as the org spells it, with a key made of the agent and the object.
  // testScenario2: An object that does not exist is refused with a message that says what to enter.
  // testScenario3: The same object cannot be added to one agent twice, whatever the capitalisation; another agent can have it.
  // testScenario4: An unexpected failure inside the handler is logged and the save is refused, never allowed unchecked.

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

    Test.startTest();
    AIAgentObject__c agentObject = AIAssistTestDataFactory.createAIAgentObjects(
      agent.Id,
      new List<String>{ 'case' },
      true
    )[0];
    Test.stopTest();

    AIAgentObject__c saved = [
      SELECT ObjectApiName__c, AssignmentKey__c
      FROM AIAgentObject__c
      WHERE Id = :agentObject.Id
    ];
    Assert.areEqual(
      'Case',
      saved.ObjectApiName__c,
      'Stored as the org spells it.'
    );
    Assert.areEqual(
      agent.Id + '|case',
      saved.AssignmentKey__c,
      'The agent, then the object in lower case.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];

    Test.startTest();
    List<Database.SaveResult> results = Database.insert(
      AIAssistTestDataFactory.createAIAgentObjects(
        agent.Id,
        new List<String>{ 'NoSuchObjectAtAll' },
        false
      ),
      false
    );
    Test.stopTest();

    Assert.isFalse(
      results[0].isSuccess(),
      'A typo is caught on save, not in chat.'
    );
    Assert.isTrue(
      results[0].getErrors()[0].getMessage().contains('NoSuchObjectAtAll'),
      'The message names what was entered.'
    );
  }

  @IsTest
  static void testScenario3() {
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, true);
    AIAssistTestDataFactory.createAIAgentObjects(
      agents[0].Id,
      new List<String>{ 'Case' },
      true
    );

    Test.startTest();
    List<Database.SaveResult> duplicate = Database.insert(
      AIAssistTestDataFactory.createAIAgentObjects(
        agents[0].Id,
        new List<String>{ 'CASE' },
        false
      ),
      false
    );
    List<Database.SaveResult> otherAgent = Database.insert(
      AIAssistTestDataFactory.createAIAgentObjects(
        agents[1].Id,
        new List<String>{ 'Case' },
        false
      ),
      false
    );
    Test.stopTest();

    Assert.isFalse(
      duplicate[0].isSuccess(),
      'The same object twice is refused.'
    );
    Assert.isTrue(
      otherAgent[0].isSuccess(),
      'Another agent can have the object.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    AIAgentObjectTriggerHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    List<Database.SaveResult> results = Database.insert(
      AIAssistTestDataFactory.createAIAgentObjects(
        agent.Id,
        new List<String>{ 'Case' },
        false
      ),
      false
    );
    Test.stopTest();

    Assert.isFalse(
      results[0].isSuccess(),
      'The check could not run, so the save is refused rather than allowed unchecked.'
    );
    Assert.areEqual(
      Label.AI_Error_Integrity_Check,
      results[0].getErrors()[0].getMessage(),
      'With the integrity label.'
    );
  }
}
