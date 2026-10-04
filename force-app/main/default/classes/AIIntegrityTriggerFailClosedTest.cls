/*
Class Name: AIIntegrityTriggerFailClosedTest

=================================================================
=================================================================

Description: Testing utility for the before-save integrity handlers: when the check itself cannot run, the save is refused rather than letting a record through with a blank unique key or an unchecked object name.

=================================================================
=================================================================
Applicable Classes:

AIAgentAssignmentTriggerHandler, AIAgentDataSourceTriggerHandler, AIAgentWorkflowActionTriggerHandler,
AIAgentViolationRuleTriggerHandler, AIAgentObjectTriggerHandler, AIUserSettingsTriggerHandler,
AIUsagePolicyAssignmentTriggerHandler, AIAssistGlobalUtility

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIIntegrityTriggerFailClosedTest {
  // testScenario1: refuseSave puts the integrity label on every record, and does nothing for no records.
  // testScenario2: When the check fails inside each of the seven handlers, on insert and on update, every record is refused with the integrity label and nothing is thrown.
  // testScenario3: When the checks run normally, nothing is refused.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  private static void assertRefused(SObject record, String handlerName) {
    Assert.isTrue(record.hasErrors(), handlerName + ' must refuse the save.');
    Assert.areEqual(
      Label.AI_Error_Integrity_Check,
      record.getErrors()[0].getMessage(),
      handlerName + ' refuses with the integrity label.'
    );
  }

  @IsTest
  static void testScenario1() {
    List<Account> accounts = new List<Account>{
      new Account(Name = 'One'),
      new Account(Name = 'Two')
    };

    Test.startTest();
    AIAssistGlobalUtility.refuseSave(accounts);
    AIAssistGlobalUtility.refuseSave(null);
    AIAssistGlobalUtility.refuseSave(new List<SObject>());
    Test.stopTest();

    assertRefused(accounts[0], 'refuseSave');
    assertRefused(accounts[1], 'refuseSave');
  }

  @IsTest
  static void testScenario2() {
    AIAgentAssignmentTriggerHandler.isTestCustomExceptionThrown = true;
    AIAgentDataSourceTriggerHandler.isTestCustomExceptionThrown = true;
    AIAgentWorkflowActionTriggerHandler.isTestCustomExceptionThrown = true;
    AIAgentViolationRuleTriggerHandler.isTestCustomExceptionThrown = true;
    AIAgentObjectTriggerHandler.isTestCustomExceptionThrown = true;
    AIUserSettingsTriggerHandler.isTestCustomExceptionThrown = true;
    AIUsagePolicyAssignmentTriggerHandler.isTestCustomExceptionThrown = true;

    List<AIAgentAssignment__c> assignments = new List<AIAgentAssignment__c>{
      new AIAgentAssignment__c(),
      new AIAgentAssignment__c()
    };
    List<AIAgentDataSource__c> dataSources = new List<AIAgentDataSource__c>{
      new AIAgentDataSource__c(),
      new AIAgentDataSource__c()
    };
    List<AIAgentWorkflowAction__c> actions = new List<AIAgentWorkflowAction__c>{
      new AIAgentWorkflowAction__c(),
      new AIAgentWorkflowAction__c()
    };
    List<AIAgentViolationRule__c> ruleLinks = new List<AIAgentViolationRule__c>{
      new AIAgentViolationRule__c(),
      new AIAgentViolationRule__c()
    };
    List<AIAgentObject__c> agentObjects = new List<AIAgentObject__c>{
      new AIAgentObject__c(),
      new AIAgentObject__c()
    };
    List<AIUserSettings__c> settingsRows = new List<AIUserSettings__c>{
      new AIUserSettings__c(),
      new AIUserSettings__c()
    };
    List<AIUsagePolicyAssignment__c> policyAssignments = new List<AIUsagePolicyAssignment__c>{
      new AIUsagePolicyAssignment__c(),
      new AIUsagePolicyAssignment__c()
    };

    Test.startTest();
    try {
      AIAgentAssignmentTriggerHandler.handleBeforeInsert(assignments);
      AIAgentAssignmentTriggerHandler.handleBeforeUpdate(
        new List<AIAgentAssignment__c>{ assignments[1] }
      );
      AIAgentDataSourceTriggerHandler.handleBeforeInsert(dataSources);
      AIAgentDataSourceTriggerHandler.handleBeforeUpdate(dataSources);
      AIAgentWorkflowActionTriggerHandler.handleBeforeInsert(actions);
      AIAgentWorkflowActionTriggerHandler.handleBeforeUpdate(actions);
      AIAgentViolationRuleTriggerHandler.handleBeforeInsert(ruleLinks);
      AIAgentViolationRuleTriggerHandler.handleBeforeUpdate(ruleLinks);
      AIAgentObjectTriggerHandler.handleBeforeInsert(agentObjects);
      AIAgentObjectTriggerHandler.handleBeforeUpdate(agentObjects);
      AIUserSettingsTriggerHandler.handleBeforeInsert(settingsRows);
      AIUserSettingsTriggerHandler.handleBeforeUpdate(settingsRows);
      AIUsagePolicyAssignmentTriggerHandler.handleBeforeInsert(
        policyAssignments
      );
      AIUsagePolicyAssignmentTriggerHandler.handleBeforeUpdate(
        policyAssignments
      );
      AIAgentAssignmentTriggerHandler.handleBeforeUpdate(null);
    } catch (Exception ex) {
      Assert.fail(
        'A handler must refuse the save, not throw: ' + ex.getMessage()
      );
    }
    Test.stopTest();

    for (SObject record : (List<SObject>) assignments)
      assertRefused(record, 'AIAgentAssignmentTriggerHandler');
    for (SObject record : (List<SObject>) dataSources)
      assertRefused(record, 'AIAgentDataSourceTriggerHandler');
    for (SObject record : (List<SObject>) actions)
      assertRefused(record, 'AIAgentWorkflowActionTriggerHandler');
    for (SObject record : (List<SObject>) ruleLinks)
      assertRefused(record, 'AIAgentViolationRuleTriggerHandler');
    for (SObject record : (List<SObject>) agentObjects)
      assertRefused(record, 'AIAgentObjectTriggerHandler');
    for (SObject record : (List<SObject>) settingsRows)
      assertRefused(record, 'AIUserSettingsTriggerHandler');
    for (SObject record : (List<SObject>) policyAssignments)
      assertRefused(record, 'AIUsagePolicyAssignmentTriggerHandler');
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    User assignee = AIAssistTestDataFactory.createUsers(1, true)[0];

    Test.startTest();
    List<AIAgentAssignment__c> assignments = AIAssistTestDataFactory.createAIAgentAssignments(
      agent.Id,
      new List<User>{ assignee },
      true
    );
    Test.stopTest();

    Assert.isNotNull(assignments[0].Id, 'Saved.');
    Assert.isNotNull(
      [
        SELECT AssignmentKey__c
        FROM AIAgentAssignment__c
        WHERE Id = :assignments[0].Id
      ]
      .AssignmentKey__c,
      'With its key.'
    );
  }
}
