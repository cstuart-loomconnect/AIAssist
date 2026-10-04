/*
Class Name: AIConfigurationValidatorTest

=================================================================
=================================================================

Description: Testing utility for AIConfigurationValidator: a configuration record that names an Apex class, a Named Credential or a permission set that does not exist is refused when it is saved, with an error on the field that says what was not found.

=================================================================
=================================================================
Applicable Classes:

AIConfigurationValidator

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIConfigurationValidatorTest {
  // testScenario1: A data source or Workflow Action naming an Apex class that does not exist, or one that does not implement the interface, is refused; a real one saves, and a non-Apex type is not checked.
  // testScenario2: A model configuration naming a Named Credential that does not exist is refused; one that exists saves, with or without a namespace.
  // testScenario3: An assignment naming a permission set that does not exist is refused; a permission set and a permission set group both save.
  // testScenario4: A name that has not changed is not checked again, so a record whose class was since removed can still be edited.
  // testScenario5: The checks do not run in a test that has not asked for them, and a failure of a check is logged and the record still saves.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  public class RealDataSource implements IAIDataSourceExecutor {
    public AIDataSourceResponse execute(AIDataSourceRequest request) {
      return new AIDataSourceResponse();
    }
  }

  public class RealAction implements IAIWorkflowActionExecutor {
    public AIWorkflowActionResponse execute(AIWorkflowActionRequest request) {
      return new AIWorkflowActionResponse('Done');
    }
  }

  private static String firstError(Database.SaveResult result) {
    return result.isSuccess() ? null : result.getErrors()[0].getMessage();
  }

  @IsTest
  static void testScenario1() {
    AIConfigurationValidator.isCheckedInTest = true;
    List<AIDataSource__c> dataSources = new List<AIDataSource__c>();
    for (
      String className : new List<String>{
        'No_Such_Class_Anywhere',
        'AIConfigurationValidatorTest.RealAction',
        'AIConfigurationValidatorTest.RealDataSource'
      }
    )
      dataSources.addAll(
        AIAssistTestDataFactory.createAIDataSources(
          1,
          AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX,
          className,
          false
        )
      );
    dataSources.addAll(
      AIAssistTestDataFactory.createAIDataSources(
        1,
        AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
        'SELECT Id FROM Account LIMIT 1',
        false
      )
    );
    List<AIWorkflowAction__c> actions = new List<AIWorkflowAction__c>();
    for (
      String className : new List<String>{
        'No_Such_Class_Anywhere',
        'AIConfigurationValidatorTest.RealAction'
      }
    )
      actions.addAll(
        AIAssistTestDataFactory.createAIWorkflowActions(
          1,
          AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
          className,
          false
        )
      );

    Test.startTest();
    List<Database.SaveResult> dataSourceResults = Database.insert(
      dataSources,
      false
    );
    List<Database.SaveResult> actionResults = Database.insert(actions, false);
    Test.stopTest();

    Assert.isTrue(
      firstError(dataSourceResults[0]).contains('No_Such_Class_Anywhere'),
      'The missing class is named: ' + firstError(dataSourceResults[0])
    );
    Assert.isTrue(
      firstError(dataSourceResults[1]).contains('IAIDataSourceExecutor'),
      'A class that is not a data source says which interface is needed: ' +
      firstError(dataSourceResults[1])
    );
    Assert.isTrue(dataSourceResults[2].isSuccess(), 'A real data source.');
    Assert.isTrue(dataSourceResults[3].isSuccess(), 'SOQL is not checked.');
    Assert.isFalse(actionResults[0].isSuccess(), 'A missing action class.');
    Assert.isTrue(actionResults[1].isSuccess(), 'A real action class.');
  }

  @IsTest
  static void testScenario2() {
    AIConfigurationValidator.isCheckedInTest = true;
    AIConfigurationValidator.namedCredentialsForTest = new Set<String>{
      'Provider_Api',
      'acme__Shared_Api'
    };
    List<AIModelConfiguration__c> models = AIAssistTestDataFactory.createAIModelConfigurations(
      3,
      false
    );
    models[0].NamedCredential__c = 'Provider_Api';
    models[1].NamedCredential__c = 'acme__Shared_Api';
    models[2].NamedCredential__c = 'Typo_Api';

    Test.startTest();
    List<Database.SaveResult> results = Database.insert(models, false);
    AIConfigurationValidator.namedCredentialsForTest = null;
    AIModelConfiguration__c againstTheOrg = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      false
    )[0];
    againstTheOrg.NamedCredential__c = 'No_Such_Credential_In_This_Org';
    Database.SaveResult realLookup = Database.insert(againstTheOrg, false);
    Test.stopTest();

    Assert.isTrue(results[0].isSuccess(), 'It exists.');
    Assert.isTrue(results[1].isSuccess(), 'It exists, in a namespace.');
    Assert.isTrue(
      firstError(results[2]).contains('Typo_Api'),
      'The missing credential is named: ' + firstError(results[2])
    );
    Assert.isFalse(realLookup.isSuccess(), 'Looked up in the org itself.');
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIUsagePolicy__c policy = AIAssistTestDataFactory.createAIUsagePolicies(
      1,
      true
    )[0];
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new PermissionSetGroup(
        DeveloperName = 'AIAssistTestGroup',
        MasterLabel = 'AI Assist Test Group'
      );
    }
    List<AIAgentAssignment__c> assignments = new List<AIAgentAssignment__c>();
    for (
      String name : new List<String>{
        AIAssistApplicationConstants.PERMISSION_SET_USER,
        'AIAssistTestGroup',
        'No_Such_Permission_Set'
      }
    )
      assignments.add(
        new AIAgentAssignment__c(
          AIAgent__c = agent.Id,
          AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET,
          PermissionSetName__c = name,
          IsActive__c = true
        )
      );
    AIUsagePolicyAssignment__c policyAssignment = new AIUsagePolicyAssignment__c(
      AIUsagePolicy__c = policy.Id,
      AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET,
      PermissionSetName__c = 'No_Such_Permission_Set',
      IsActive__c = true
    );
    AIConfigurationValidator.isCheckedInTest = true;

    Test.startTest();
    List<Database.SaveResult> results = Database.insert(assignments, false);
    Database.SaveResult policyResult = Database.insert(policyAssignment, false);
    Test.stopTest();

    Assert.isTrue(
      results[0].isSuccess(),
      'A permission set: ' + firstError(results[0])
    );
    Assert.isTrue(
      results[1].isSuccess(),
      'A permission set group: ' + firstError(results[1])
    );
    Assert.isTrue(
      firstError(results[2]).contains('No_Such_Permission_Set'),
      'The missing permission set is named: ' + firstError(results[2])
    );
    Assert.isFalse(
      policyResult.isSuccess(),
      'The same on a policy assignment.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
      'A_Class_Since_Deleted',
      true
    )[0];
    AIConfigurationValidator.isCheckedInTest = true;

    Test.startTest();
    action.Description__c = 'Edited in another way.';
    Database.SaveResult unrelatedEdit = Database.update(action, false);
    action.ApexClassName__c = 'Another_Missing_Class';
    Database.SaveResult renamed = Database.update(action, false);
    Test.stopTest();

    Assert.isTrue(unrelatedEdit.isSuccess(), 'The name did not change.');
    Assert.isFalse(renamed.isSuccess(), 'A changed name is checked.');
  }

  @IsTest
  static void testScenario5() {
    Test.startTest();
    Database.SaveResult unchecked = Database.insert(
      AIAssistTestDataFactory.createAIWorkflowActions(
        1,
        AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
        'No_Such_Class_Anywhere',
        false
      )[0],
      false
    );
    AIConfigurationValidator.isCheckedInTest = true;
    AIConfigurationValidator.isTestFailureThrown = true;
    Database.SaveResult failedCheck = Database.insert(
      AIAssistTestDataFactory.createAIWorkflowActions(
        1,
        AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
        'No_Such_Class_Anywhere',
        false
      )[0],
      false
    );
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      false
    )[0];
    Database.SaveResult failedCredentialCheck = Database.insert(model, false);
    AIConfigurationValidator.checkPermissionSets(
      new List<SObject>{ new AIAgentAssignment__c() },
      AIAgentAssignment__c.PermissionSetName__c
    );
    Test.stopTest();

    Assert.isTrue(unchecked.isSuccess(), 'Not checked unless a test asks.');
    Assert.isTrue(failedCheck.isSuccess(), 'A failed check lets the save go.');
    Assert.isTrue(failedCredentialCheck.isSuccess(), 'And so here.');
    Assert.isTrue(
      [
        SELECT COUNT()
        FROM AIPlatformLog__c
        WHERE ClassName__c = 'AIConfigurationValidator'
      ] >= 3,
      'Each failed check is logged.'
    );
  }
}
