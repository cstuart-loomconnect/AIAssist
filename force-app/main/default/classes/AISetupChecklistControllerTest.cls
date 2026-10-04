/*
Class Name: AISetupChecklistControllerTest

=================================================================
=================================================================

Description: Testing utility for AISetupChecklistController: the Getting Started steps and scheduling maintenance.

=================================================================
=================================================================
Applicable Classes:

AISetupChecklistController

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AISetupChecklistControllerTest {
  // testScenario1: With nothing configured, the agent, assignment and credential steps are not complete and neither is the checklist.
  // testScenario2: A tested credential, an active agent and an assignment complete their steps; an agent limited to assigned users with none does not complete the assignment step.
  // testScenario3: scheduleMaintenance schedules the job once and the step is then complete.
  // testScenario4: Without the AIAssistManageConfiguration permission neither the checklist nor the action is available.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  private static void allow(Boolean canManage) {
    AIConfigurationAccess.canManageForTest = canManage;
  }

  private static Map<String, Boolean> completeByStep() {
    Map<String, Boolean> isComplete = new Map<String, Boolean>();
    for (
      AISetupChecklistController.Step step : AISetupChecklistController.getChecklist()
        .steps
    )
      isComplete.put(step.name, step.isComplete);
    return isComplete;
  }

  @IsTest
  static void testScenario1() {
    allow(true);

    Test.startTest();
    AISetupChecklistController.Checklist checklist = AISetupChecklistController.getChecklist();
    Test.stopTest();

    Map<String, Boolean> isComplete = new Map<String, Boolean>();
    for (AISetupChecklistController.Step step : checklist.steps)
      isComplete.put(step.name, step.isComplete);
    Assert.areEqual(5, checklist.steps.size(), 'Five steps, in order.');
    Assert.areEqual(
      AISetupChecklistController.STEP_PERMISSION_SETS,
      checklist.steps[0].name,
      'Permission sets first.'
    );
    Assert.isFalse(
      isComplete.get(AISetupChecklistController.STEP_CREDENTIAL_TESTED),
      'No credential tested.'
    );
    Assert.isFalse(
      isComplete.get(AISetupChecklistController.STEP_FIRST_AGENT),
      'No agent.'
    );
    Assert.isFalse(
      isComplete.get(AISetupChecklistController.STEP_ASSIGNMENT),
      'No assignment.'
    );
    Assert.isFalse(checklist.isComplete, 'Not finished.');
  }

  @IsTest
  static void testScenario2() {
    allow(true);
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      AIAssistApplicationConstants.PERMISSION_SET_USER
    );
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      false
    )[0];
    agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
    insert agent;

    Test.startTest();
    Map<String, Boolean> beforeAssignment = completeByStep();
    model.ConnectionTestedDate__c = System.now();
    update model;
    AIAssistTestDataFactory.createAIAgentAssignments(
      agent.Id,
      new List<User>{ chatUser },
      true
    );
    Map<String, Boolean> afterAssignment = completeByStep();
    Test.stopTest();

    Assert.isTrue(
      beforeAssignment.get(AISetupChecklistController.STEP_PERMISSION_SETS),
      'Somebody holds a permission set.'
    );
    Assert.isTrue(
      beforeAssignment.get(AISetupChecklistController.STEP_FIRST_AGENT),
      'An active agent.'
    );
    Assert.isFalse(
      beforeAssignment.get(AISetupChecklistController.STEP_ASSIGNMENT),
      'Limited to assigned users, and nobody is.'
    );
    Assert.isFalse(
      beforeAssignment.get(AISetupChecklistController.STEP_CREDENTIAL_TESTED),
      'Not tested yet.'
    );
    Assert.isTrue(
      afterAssignment.get(AISetupChecklistController.STEP_ASSIGNMENT),
      'Assigned.'
    );
    Assert.isTrue(
      afterAssignment.get(AISetupChecklistController.STEP_CREDENTIAL_TESTED),
      'Tested.'
    );
  }

  @IsTest
  static void testScenario3() {
    allow(true);
    // The org the tests run in may already have the job: start from none.
    for (CronTrigger existing : [
      SELECT Id
      FROM CronTrigger
      WHERE CronJobDetail.Name = :AIMaintenanceScheduler.JOB_NAME
    ])
      System.abortJob(existing.Id);

    Test.startTest();
    Boolean wasComplete = completeByStep()
      .get(AISetupChecklistController.STEP_MAINTENANCE);
    Boolean scheduledNow = AISetupChecklistController.scheduleMaintenance();
    Boolean scheduledAgain = AISetupChecklistController.scheduleMaintenance();
    Boolean isComplete = completeByStep()
      .get(AISetupChecklistController.STEP_MAINTENANCE);
    Test.stopTest();

    Assert.isFalse(wasComplete, 'Not scheduled to begin with.');
    Assert.isTrue(scheduledNow, 'Scheduled.');
    Assert.isFalse(scheduledAgain, 'Already scheduled: not a second job.');
    Assert.isTrue(isComplete, 'The step is complete.');
  }

  @IsTest
  static void testScenario4() {
    allow(false);
    List<String> refusals = new List<String>();

    Test.startTest();
    try {
      AISetupChecklistController.getChecklist();
    } catch (AuraHandledException refused) {
      refusals.add(refused.getMessage());
    }
    try {
      AISetupChecklistController.scheduleMaintenance();
    } catch (AuraHandledException refused) {
      refusals.add(refused.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      new List<String>{
        Label.AI_Error_Not_Authorised,
        Label.AI_Error_Not_Authorised
      },
      refusals,
      'Both refused.'
    );
  }
}
