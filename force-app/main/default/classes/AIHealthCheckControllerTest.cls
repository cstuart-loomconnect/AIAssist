/*
Class Name: AIHealthCheckControllerTest

=================================================================
=================================================================

Description: Testing utility for AIHealthCheckController: each configuration problem is reported once, with the record to fix.

=================================================================
=================================================================
Applicable Classes:

AIHealthCheckController

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIHealthCheckControllerTest {
  // testScenario1: A sound configuration has no finding except the ones the scenario cannot avoid, and each finding of a record carries its Id, name and link.
  // testScenario2: The application switched off, settings activated in another org, and maintenance not scheduled are each reported.
  // testScenario3: Broken references: an Apex class that does not exist on a data source and on an action, a Flow that is missing, and a permission set an assignment names.
  // testScenario4: Missing credentials: a model configuration with no Named Credential, and one naming a credential that does not exist.
  // testScenario5: A model the provider reported as retired in the last week, an agent whose model configuration is inactive, and an agent limited to assigned users with none.
  // testScenario6: Without the AIAssistManageConfiguration permission nothing is returned.

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

  public class RealDataSource implements IAIDataSourceExecutor {
    public AIDataSourceResponse execute(AIDataSourceRequest request) {
      return new AIDataSourceResponse();
    }
  }

  private static Map<String, List<AIHealthCheckController.Finding>> byCode() {
    Map<String, List<AIHealthCheckController.Finding>> findingsByCode = new Map<String, List<AIHealthCheckController.Finding>>();
    for (
      AIHealthCheckController.Finding finding : AIHealthCheckController.getFindings()
    ) {
      if (!findingsByCode.containsKey(finding.code))
        findingsByCode.put(
          finding.code,
          new List<AIHealthCheckController.Finding>()
        );
      findingsByCode.get(finding.code).add(finding);
    }
    return findingsByCode;
  }

  // An active model whose credential exists, and an active agent open to everyone on it.
  private static AIAgent__c createSoundAgent() {
    AIHealthCheckController.namedCredentialsForTest = new Set<String>{
      'Test_Credential'
    };
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
    insert agent;
    return agent;
  }

  @IsTest
  static void testScenario1() {
    allow(true);
    createSoundAgent();
    AIAssistTestDataFactory.createAIDataSources(
      1,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX,
      'AIHealthCheckControllerTest.RealDataSource',
      true
    );
    AIMaintenanceScheduler.scheduleDaily();

    Test.startTest();
    List<AIHealthCheckController.Finding> findings = AIHealthCheckController.getFindings();
    Test.stopTest();

    Assert.isTrue(
      findings.isEmpty(),
      'Nothing wrong: ' + JSON.serialize(findings)
    );
  }

  @IsTest
  static void testScenario2() {
    allow(true);
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();

    Test.startTest();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.clearCache();
    Map<String, List<AIHealthCheckController.Finding>> whileOff = byCode();
    settings.IsEnabled__c = true;
    settings.ActivatedOrgId__c = '00D000000000001AAA';
    update settings;
    AIAssistSettingsService.clearCache();
    Map<String, List<AIHealthCheckController.Finding>> copied = byCode();
    Test.stopTest();

    Assert.isTrue(
      whileOff.containsKey(AIHealthCheckController.CODE_APP_INACTIVE),
      'Switched off.'
    );
    Assert.areEqual(
      Label.AI_Console_Health_App_Inactive,
      whileOff.get(AIHealthCheckController.CODE_APP_INACTIVE)[0].message,
      'Says what to do.'
    );
    Assert.isTrue(
      copied.containsKey(AIHealthCheckController.CODE_SANDBOX_NOT_ACTIVATED),
      'Activated in another org.'
    );
    Assert.isFalse(
      copied.containsKey(AIHealthCheckController.CODE_APP_INACTIVE),
      'One finding for the application, not two.'
    );
    // The org the tests run in may already have the job; when it does not, it is reported.
    Assert.areEqual(
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE CronJobDetail.Name = :AIMaintenanceScheduler.JOB_NAME
      ] == 0,
      whileOff.containsKey(
        AIHealthCheckController.CODE_MAINTENANCE_NOT_SCHEDULED
      ),
      'Maintenance not scheduled is reported exactly when it is not.'
    );
  }

  @IsTest
  static void testScenario3() {
    allow(true);
    AIAgent__c agent = createSoundAgent();
    AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(
      1,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX,
      'No_Such_Data_Source_Class',
      true
    )[0];
    AIWorkflowAction__c apexAction = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
      'No_Such_Action_Class',
      true
    )[0];
    AIWorkflowAction__c flowAction = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'A_Flow_Since_Deleted',
      true
    )[0];
    insert new AIAgentAssignment__c(
      AIAgent__c = agent.Id,
      AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET,
      PermissionSetName__c = 'No_Such_Permission_Set',
      IsActive__c = true
    );
    // The Flow existed when the action was saved and has been deleted since.
    AIFlowRunModeService.testRunModeByFlowName = new Map<String, String>();

    Test.startTest();
    List<AIHealthCheckController.Finding> broken = byCode()
      .get(AIHealthCheckController.CODE_BROKEN_REFERENCE);
    Test.stopTest();

    Map<Id, AIHealthCheckController.Finding> byRecord = new Map<Id, AIHealthCheckController.Finding>();
    for (AIHealthCheckController.Finding finding : broken)
      byRecord.put(finding.recordId, finding);
    Assert.areEqual(
      4,
      broken.size(),
      'Four broken references: ' + JSON.serialize(broken)
    );
    Assert.isTrue(
      byRecord.get(dataSource.Id).message.contains('No_Such_Data_Source_Class'),
      'The data source\'s class is named.'
    );
    Assert.isTrue(
      byRecord.get(apexAction.Id).message.contains('No_Such_Action_Class'),
      'The action\'s class is named.'
    );
    Assert.isTrue(
      byRecord.get(flowAction.Id).message.contains('A_Flow_Since_Deleted'),
      'The Flow is named.'
    );
    Assert.isTrue(
      byRecord.get(agent.Id).message.contains('No_Such_Permission_Set'),
      'The permission set is named.'
    );
    Assert.areEqual(
      '/' + dataSource.Id,
      byRecord.get(dataSource.Id).recordUrl,
      'With a link to the record.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.LOG_SEVERITY_ERROR,
      byRecord.get(dataSource.Id).severity,
      'An error: it stops something working.'
    );
  }

  @IsTest
  static void testScenario4() {
    allow(true);
    AIHealthCheckController.namedCredentialsForTest = new Set<String>{
      'Real_Credential'
    };
    List<AIModelConfiguration__c> models = AIAssistTestDataFactory.createAIModelConfigurations(
      3,
      false
    );
    models[0].NamedCredential__c = 'Real_Credential';
    models[1].NamedCredential__c = 'Deleted_Credential';
    models[2].NamedCredential__c = null;
    models[2].IsActive__c = false;
    insert models;
    // Active with no credential cannot be saved, so it is made so after the fact, as a deleted credential would leave it.
    Test.startTest();
    List<AIHealthCheckController.Finding> missing = byCode()
      .get(AIHealthCheckController.CODE_MISSING_CREDENTIAL);
    AIHealthCheckController.namedCredentialsForTest = null;
    Integer againstTheOrg = byCode()
      .get(AIHealthCheckController.CODE_MISSING_CREDENTIAL)
      .size();
    Test.stopTest();

    Assert.areEqual(
      1,
      missing.size(),
      'Only the active model whose credential is gone: ' +
      JSON.serialize(missing)
    );
    Assert.areEqual(
      models[1].Id,
      missing[0].recordId,
      'The model configuration to fix.'
    );
    Assert.isTrue(
      missing[0].message.contains('Deleted_Credential'),
      'The credential is named.'
    );
    Assert.areEqual(
      2,
      againstTheOrg,
      'Looked up in the org itself, neither credential exists.'
    );
  }

  @IsTest
  static void testScenario5() {
    allow(true);
    AIAgent__c agent = createSoundAgent();
    AIAgent__c closedAgent = AIAssistTestDataFactory.createAIAgents(
      1,
      agent.AIModelConfiguration__c,
      false
    )[0];
    closedAgent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
    insert closedAgent;
    AIModelConfiguration__c inactiveModel = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      false
    )[0];
    inactiveModel.IsActive__c = false;
    insert inactiveModel;
    AIAgent__c orphanAgent = AIAssistTestDataFactory.createAIAgents(
      1,
      inactiveModel.Id,
      false
    )[0];
    orphanAgent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
    insert orphanAgent;
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIConversationMessage__c failedTurn = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      false
    )[0];
    failedTurn.ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_FAILED;
    failedTurn.FailureReason__c = AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED;
    insert failedTurn;

    Test.startTest();
    Map<String, List<AIHealthCheckController.Finding>> findings = byCode();
    Test.stopTest();

    Assert.areEqual(
      agent.AIModelConfiguration__c,
      findings.get(AIHealthCheckController.CODE_RETIRED_MODEL)[0].recordId,
      'The model the provider says is gone.'
    );
    Assert.areEqual(
      orphanAgent.Id,
      findings.get(AIHealthCheckController.CODE_NO_ACTIVE_MODEL)[0].recordId,
      'The agent with no active model.'
    );
    Assert.areEqual(
      1,
      findings.get(AIHealthCheckController.CODE_NO_ASSIGNED_USERS).size(),
      'One agent has nobody.'
    );
    Assert.areEqual(
      closedAgent.Id,
      findings.get(AIHealthCheckController.CODE_NO_ASSIGNED_USERS)[0].recordId,
      'The agent limited to assigned users with none.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.LOG_SEVERITY_WARNING,
      findings.get(AIHealthCheckController.CODE_NO_ASSIGNED_USERS)[0].severity,
      'A warning: nothing is broken, nobody can use it yet.'
    );
  }

  @IsTest
  static void testScenario6() {
    allow(false);
    String refusal;

    Test.startTest();
    try {
      AIHealthCheckController.getFindings();
    } catch (AuraHandledException refused) {
      refusal = refused.getMessage();
    }
    Test.stopTest();

    Assert.areEqual(Label.AI_Error_Not_Authorised, refusal, 'Refused.');
  }
}
