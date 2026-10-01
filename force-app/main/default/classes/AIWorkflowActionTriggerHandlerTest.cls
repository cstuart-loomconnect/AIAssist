/*
Class Name: AIWorkflowActionTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIWorkflowActionTrigger and AIWorkflowActionTriggerHandler: the Developer Name stamped on a new workflow action.

=================================================================
=================================================================
Applicable Classes:

AIWorkflowActionTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIWorkflowActionTriggerHandlerTest {
  // testScenario1: A new workflow action gets a Developer Name derived from its action name, and one supplied is kept.
  // testScenario2: Bulk: 201 workflow actions are all named, distinct, within a few queries.
  // testScenario3: Switched off, nothing is stamped, and the handler ignores empty input.
  // testScenario4: An unexpected failure inside the handler is logged and never stops the save.

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
    List<AIWorkflowAction__c> actions = AIAssistTestDataFactory.createAIWorkflowActions(
      2,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'Some_Flow',
      false
    );
    actions[0].ActionName__c = 'Create Follow-up Task';
    actions[1].DeveloperName__c = 'Fixed_Action';

    Test.startTest();
    insert actions;
    Test.stopTest();

    Map<Id, AIWorkflowAction__c> byId = new Map<Id, AIWorkflowAction__c>(
      [SELECT DeveloperName__c FROM AIWorkflowAction__c WHERE Id IN :actions]
    );
    Assert.areEqual(
      'Create_Follow_up_Task',
      byId.get(actions[0].Id).DeveloperName__c,
      'Derived.'
    );
    Assert.areEqual(
      'Fixed_Action',
      byId.get(actions[1].Id).DeveloperName__c,
      'Kept.'
    );
  }

  @IsTest
  static void testScenario2() {
    List<AIWorkflowAction__c> actions = AIAssistTestDataFactory.createAIWorkflowActions(
      201,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'Some_Flow',
      false
    );
    Integer queries;

    Test.startTest();
    insert actions;
    queries = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(
      201,
      [SELECT COUNT_DISTINCT(DeveloperName__c) FROM AIWorkflowAction__c][0]
        .get('expr0'),
      'All distinct.'
    );
    Assert.isTrue(
      queries <= 5,
      'Queries do not grow with the number of records: ' + queries
    );
  }

  @IsTest
  static void testScenario3() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'Some_Flow',
      false
    )[0];

    Test.startTest();
    insert action;
    AIWorkflowActionTriggerHandler.handleBeforeInsert(null);
    Test.stopTest();

    Assert.isNull(
      [SELECT DeveloperName__c FROM AIWorkflowAction__c WHERE Id = :action.Id]
      .DeveloperName__c,
      'No Developer Name.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIWorkflowActionTriggerHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    try {
      AIWorkflowActionTriggerHandler.handleBeforeInsert(
        new List<AIWorkflowAction__c>{ new AIWorkflowAction__c() }
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
        WHERE ClassName__c = 'AIWorkflowActionTriggerHandler'
      ],
      'Logged once.'
    );
  }
}
