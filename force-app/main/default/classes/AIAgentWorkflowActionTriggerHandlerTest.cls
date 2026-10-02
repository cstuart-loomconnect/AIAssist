/*
Class Name: AIAgentWorkflowActionTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIAgentWorkflowActionTrigger and AIAgentWorkflowActionTriggerHandler: the unique key that stops one agent being given the same workflow action twice.

=================================================================
=================================================================
Applicable Classes:

AIAgentWorkflowActionTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAgentWorkflowActionTriggerHandlerTest {
  // testScenario1: A new link gets a key made of its agent and its workflow action.
  // testScenario2: The same workflow action cannot be linked to one agent twice, active or not; another agent can have it.
  // testScenario3: The key is set on insert and is still right after an update. Nobody is granted edit access to it, so it cannot be typed in.
  // testScenario4: An unexpected failure inside the handler is logged and never throws.

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
    List<AIWorkflowAction__c> children = AIAssistTestDataFactory.createAIWorkflowActions(
      2,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'Some_Flow',
      true
    );

    Test.startTest();
    List<AIAgentWorkflowAction__c> links = AIAssistTestDataFactory.createAIAgentWorkflowActions(
      agent.Id,
      children,
      true
    );
    Test.stopTest();

    Map<Id, AIAgentWorkflowAction__c> savedById = new Map<Id, AIAgentWorkflowAction__c>(
      [
        SELECT Id, AIWorkflowAction__c, AssignmentKey__c
        FROM AIAgentWorkflowAction__c
        WHERE Id IN :links
      ]
    );
    Assert.areEqual(2, savedById.size(), 'Both saved.');
    for (AIAgentWorkflowAction__c saved : savedById.values())
      Assert.areEqual(
        agent.Id + '|' + saved.AIWorkflowAction__c,
        saved.AssignmentKey__c,
        'The agent, then the workflow action.'
      );
  }

  @IsTest
  static void testScenario2() {
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, true);
    List<AIWorkflowAction__c> children = AIAssistTestDataFactory.createAIWorkflowActions(
      2,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'Some_Flow',
      true
    );
    AIAssistTestDataFactory.createAIAgentWorkflowActions(
      agents[0].Id,
      children,
      true
    );
    List<AIAgentWorkflowAction__c> duplicates = AIAssistTestDataFactory.createAIAgentWorkflowActions(
      agents[0].Id,
      children,
      false
    );
    duplicates[1].IsActive__c = false;

    Test.startTest();
    List<Database.SaveResult> duplicateResults = Database.insert(
      duplicates,
      false
    );
    List<Database.SaveResult> otherAgentResults = Database.insert(
      AIAssistTestDataFactory.createAIAgentWorkflowActions(
        agents[1].Id,
        children,
        false
      ),
      false
    );
    Test.stopTest();

    for (Database.SaveResult duplicateResult : duplicateResults) {
      Assert.isFalse(duplicateResult.isSuccess(), 'Refused as a duplicate.');
      Assert.areEqual(
        StatusCode.DUPLICATE_VALUE,
        duplicateResult.getErrors()[0].getStatusCode(),
        'By the unique key.'
      );
    }
    for (Database.SaveResult otherAgentResult : otherAgentResults)
      Assert.isTrue(otherAgentResult.isSuccess(), 'Another agent may have it.');
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    List<AIWorkflowAction__c> children = AIAssistTestDataFactory.createAIWorkflowActions(
      2,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'Some_Flow',
      true
    );
    AIAgentWorkflowAction__c link = AIAssistTestDataFactory.createAIAgentWorkflowActions(
      agent.Id,
      new List<AIWorkflowAction__c>{ children[0] },
      false
    )[0];

    Test.startTest();
    insert link;
    String keyAfterInsert = [
      SELECT AssignmentKey__c
      FROM AIAgentWorkflowAction__c
      WHERE Id = :link.Id
    ]
    .AssignmentKey__c;
    update new AIAgentWorkflowAction__c(Id = link.Id, IsActive__c = false); // Only what changes: the master-detail to the agent cannot be written again.
    Test.stopTest();

    Assert.areEqual(
      agent.Id + '|' + children[0].Id,
      keyAfterInsert,
      'Set on insert.'
    );
    Assert.areEqual(
      keyAfterInsert,
      [
        SELECT AssignmentKey__c
        FROM AIAgentWorkflowAction__c
        WHERE Id = :link.Id
      ]
      .AssignmentKey__c,
      'And unchanged by an update.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIAgentWorkflowActionTriggerHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    try {
      AIAgentWorkflowActionTriggerHandler.handleBeforeInsert(
        new List<AIAgentWorkflowAction__c>{ new AIAgentWorkflowAction__c() }
      );
      AIAgentWorkflowActionTriggerHandler.handleBeforeUpdate(null);
    } catch (Exception ex) {
      Assert.fail('The handler must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM AIPlatformLog__c
        WHERE ClassName__c = 'AIAgentWorkflowActionTriggerHandler'
      ],
      'Logged once for each call.'
    );
  }
}
