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
  // testScenario5: A Flow that runs in system context without sharing, or that cannot be found, is refused on insert, on a change of Flow and on activation; a Flow in the default mode is saved.
  // testScenario6: If the run mode check itself fails, the save is refused rather than allowed.

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

  @IsTest
  static void testScenario5() {
    AIFlowRunModeService.setRunModeForTest('SafeFlow', null);
    AIFlowRunModeService.setRunModeForTest(
      'SharingFlow',
      'SystemModeWithSharing'
    );
    AIFlowRunModeService.setRunModeForTest(
      'SystemFlow',
      AIFlowRunModeService.RUN_MODE_SYSTEM_WITHOUT_SHARING
    );
    List<AIWorkflowAction__c> actions = AIAssistTestDataFactory.createAIWorkflowActions(
      4,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'SafeFlow',
      false
    );
    actions[1].FlowAPIName__c = 'SharingFlow';
    actions[2].FlowAPIName__c = 'SystemFlow';
    actions[3].FlowAPIName__c = 'MissingFlow';

    Test.startTest();
    List<Database.SaveResult> results = Database.insert(actions, false);
    AIWorkflowAction__c safe = actions[0];
    safe.FlowAPIName__c = 'SystemFlow';
    Database.SaveResult changed = Database.update(safe, false);
    safe.FlowAPIName__c = 'SafeFlow';
    update safe;
    safe.IsActive__c = false;
    update safe;
    AIFlowRunModeService.setRunModeForTest(
      'SafeFlow',
      AIFlowRunModeService.RUN_MODE_SYSTEM_WITHOUT_SHARING
    );
    safe.IsActive__c = true;
    Database.SaveResult activated = Database.update(safe, false);
    Test.stopTest();

    Assert.isTrue(results[0].isSuccess(), 'Default mode is saved.');
    Assert.isTrue(
      results[1].isSuccess(),
      'System context with sharing is saved.'
    );
    Assert.isFalse(
      results[2].isSuccess(),
      'System context without sharing is refused.'
    );
    Assert.areEqual(
      Label.AI_Error_Flow_Run_Mode,
      results[2].getErrors()[0].getMessage(),
      'With its own label.'
    );
    Assert.isFalse(
      results[3].isSuccess(),
      'A Flow that cannot be found is refused.'
    );
    Assert.isFalse(
      changed.isSuccess(),
      'Changing to an unsafe Flow is refused.'
    );
    Assert.isFalse(
      activated.isSuccess(),
      'Switching on an action whose Flow has become unsafe is refused.'
    );
  }

  @IsTest
  static void testScenario6() {
    AIWorkflowActionTriggerHandler.isTestFlowCheckExceptionThrown = true;
    AIFlowRunModeService.setRunModeForTest('SafeFlow', null);
    AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'SafeFlow',
      false
    )[0];

    Test.startTest();
    Database.SaveResult result = Database.insert(action, false);
    Test.stopTest();

    Assert.isFalse(result.isSuccess(), 'Fails closed.');
  }
}
