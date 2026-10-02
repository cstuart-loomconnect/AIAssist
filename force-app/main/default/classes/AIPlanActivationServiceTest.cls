/*
Class Name: AIPlanActivationServiceTest

=================================================================
=================================================================

Description: Testing utility for AIPlanActivationService, through the triggers that call it: what a plan refuses when an agent, data source, workflow action or model configuration is saved, and what it leaves alone.

Feature Management parameters cannot be changed by a test, so each scenario sets the plan with AIPlanLimitService.setLimitForTest and switches the activation checks on for the test.

=================================================================
=================================================================
Applicable Classes:

AIPlanActivationService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIPlanActivationServiceTest {
  // testScenario1: In a test that has not asked for them, the activation checks do not apply.
  // testScenario2: No more agents can be active than the plan allows; the ones within the limit still save, counting those already active.
  // testScenario3: Activating an agent by update is refused past the limit, but an agent that was already active can still be edited.
  // testScenario4: An agent's retention cannot be longer than the plan's cap, blank counts as longer, and an agent that is not changing its retention is left alone.
  // testScenario5: An active Apex data source needs a plan that includes Apex, and no more data sources can be active than the plan allows.
  // testScenario6: An active action needs a plan that includes Workflow Actions, an Apex one needs Apex too, and no more can be active than the plan allows.
  // testScenario7: On a single-provider plan a second provider cannot be activated, on insert or by update; a plan that allows several accepts it.
  // testScenario8: With no provider in use yet, the first one activated in a save becomes the organisation's provider.
  // testScenario9: No records, or none set, is not an error.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  // Every activation parameter set to "no restriction", so a scenario only states the one it is about.
  private static void checkActivationOnUnrestrictedPlan() {
    for (
      String integerParameter : new List<String>{
        AIAssistApplicationConstants.FEATURE_MAX_ACTIVE_AGENTS,
        AIAssistApplicationConstants.FEATURE_MAX_ACTIVE_DATA_SOURCES,
        AIAssistApplicationConstants.FEATURE_MAX_ACTIVE_WORKFLOW_ACTIONS,
        AIAssistApplicationConstants.FEATURE_MAX_CONVERSATION_RETENTION_DAYS
      }
    )
      AIPlanLimitService.setLimitForTest(integerParameter, null);

    for (
      String booleanParameter : new List<String>{
        AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
        AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
        AIAssistApplicationConstants.FEATURE_MULTIPLE_PROVIDERS_ALLOWED
      }
    )
      AIPlanLimitService.setLimitForTest(booleanParameter, true);

    AIPlanLimitService.isActivationCheckedInTest = true;
  }

  private static Integer countFailures(
    List<Database.SaveResult> saveResults,
    String expectedMessage
  ) {
    Integer failures = 0;
    for (Database.SaveResult saveResult : saveResults) {
      if (saveResult.isSuccess())
        continue;
      failures++;
      Assert.areEqual(
        expectedMessage,
        saveResult.getErrors()[0].getMessage(),
        'The refusal is the plan label.'
      );
    }
    return failures;
  }

  @IsTest
  static void testScenario1() {
    Id modelConfigurationId = AIAssistTestDataFactory.createAIModelConfigurations(
        1,
        true
      )[0]
      .Id;
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_ACTIVE_AGENTS,
      1
    );

    Test.startTest();
    List<Database.SaveResult> saveResults = Database.insert(
      AIAssistTestDataFactory.createAIAgents(4, modelConfigurationId, false),
      false
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      countFailures(saveResults, null),
      'A test that has not switched the checks on is not limited.'
    );
    Assert.isFalse(
      AIPlanLimitService.isActivationChecked(),
      'The checks are off in a test until it asks for them.'
    );
  }

  @IsTest
  static void testScenario2() {
    Id modelConfigurationId = AIAssistTestDataFactory.createAIModelConfigurations(
        1,
        true
      )[0]
      .Id;
    AIAssistTestDataFactory.createAIAgents(1, modelConfigurationId, true);
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      3,
      modelConfigurationId,
      false
    );
    agents.addAll(AIAssistTestDataFactory.createAIAgents(2, false)); // Inactive: never counted.
    checkActivationOnUnrestrictedPlan();
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_ACTIVE_AGENTS,
      3
    );

    Test.startTest();
    List<Database.SaveResult> saveResults = Database.insert(agents, false);
    Test.stopTest();

    Assert.areEqual(
      1,
      countFailures(saveResults, Label.AI_Error_Plan_Limit_Agents),
      'One is already active, so two of the three fit and the third is refused.'
    );
    Assert.areEqual(
      3,
      [SELECT COUNT() FROM AIAgent__c WHERE IsActive__c = TRUE],
      'The limit holds.'
    );
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM AIAgent__c WHERE IsActive__c = FALSE],
      'Inactive agents are not limited.'
    );
  }

  @IsTest
  static void testScenario3() {
    Id modelConfigurationId = AIAssistTestDataFactory.createAIModelConfigurations(
        1,
        true
      )[0]
      .Id;
    List<AIAgent__c> activeAgents = AIAssistTestDataFactory.createAIAgents(
      2,
      modelConfigurationId,
      true
    );
    AIAgent__c inactiveAgent = AIAssistTestDataFactory.createAIAgents(
      1,
      modelConfigurationId,
      false
    )[0];
    inactiveAgent.IsActive__c = false;
    insert inactiveAgent;
    checkActivationOnUnrestrictedPlan();
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_ACTIVE_AGENTS,
      1
    ); // Reduced below what is already active.

    Test.startTest();
    inactiveAgent.IsActive__c = true;
    Database.SaveResult activation = Database.update(inactiveAgent, false);
    activeAgents[0].Description__c = 'Edited while over the limit.';
    Database.SaveResult edit = Database.update(activeAgents[0], false);
    Test.stopTest();

    Assert.isFalse(activation.isSuccess(), 'Nothing more can be activated.');
    Assert.areEqual(
      Label.AI_Error_Plan_Limit_Agents,
      activation.getErrors()[0].getMessage(),
      'The refusal is the plan label.'
    );
    Assert.isTrue(
      edit.isSuccess(),
      'An agent that was already active can still be edited.'
    );
  }

  @IsTest
  static void testScenario4() {
    Id modelConfigurationId = AIAssistTestDataFactory.createAIModelConfigurations(
        1,
        true
      )[0]
      .Id;
    AIAgent__c longKept = AIAssistTestDataFactory.createAIAgents(1, false)[0];
    longKept.ConversationRetentionDays__c = 400;
    insert longKept; // Before the cap applies.
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      3,
      modelConfigurationId,
      false
    );
    agents[0].ConversationRetentionDays__c = 30;
    agents[1].ConversationRetentionDays__c = 365;
    agents[2].ConversationRetentionDays__c = null;
    checkActivationOnUnrestrictedPlan();
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_CONVERSATION_RETENTION_DAYS,
      90
    );

    Test.startTest();
    List<Database.SaveResult> saveResults = Database.insert(agents, false);
    longKept.Description__c = 'Edited without touching the retention.';
    Database.SaveResult unrelatedEdit = Database.update(longKept, false);
    longKept.ConversationRetentionDays__c = 500;
    Database.SaveResult longerRetention = Database.update(longKept, false);
    Test.stopTest();

    Assert.isTrue(saveResults[0].isSuccess(), 'Within the cap.');
    Assert.areEqual(
      2,
      countFailures(saveResults, Label.AI_Error_Plan_Retention_Cap),
      'Longer than the cap, and blank (keep indefinitely), are both refused.'
    );
    Assert.isTrue(
      unrelatedEdit.isSuccess(),
      'An agent that is not changing its retention is left alone.'
    );
    Assert.isFalse(
      longerRetention.isSuccess(),
      'Changing the retention to more than the cap is refused.'
    );
  }

  @IsTest
  static void testScenario5() {
    List<AIDataSource__c> dataSources = AIAssistTestDataFactory.createAIDataSources(
      3,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      false
    );
    AIDataSource__c apexSource = AIAssistTestDataFactory.createAIDataSources(
      1,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX,
      'SomeExecutor',
      false
    )[0];
    checkActivationOnUnrestrictedPlan();
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_ACTIVE_DATA_SOURCES,
      2
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      false
    );

    Test.startTest();
    Database.SaveResult apexResult = Database.insert(apexSource, false);
    List<Database.SaveResult> saveResults = Database.insert(dataSources, false);
    dataSources[2].IsActive__c = false;
    Database.SaveResult inactiveResult = Database.insert(dataSources[2], false);
    dataSources[2].IsActive__c = true;
    Database.SaveResult activation = Database.update(dataSources[2], false);
    dataSources[0].Description__c = 'Edited while at the limit.';
    Database.SaveResult edit = Database.update(dataSources[0], false);
    Test.stopTest();

    Assert.isFalse(apexResult.isSuccess(), 'The plan does not include Apex.');
    Assert.areEqual(
      Label.AI_Error_Plan_Apex_Not_Included,
      apexResult.getErrors()[0].getMessage(),
      'The refusal is the plan label.'
    );
    Assert.areEqual(
      1,
      countFailures(saveResults, Label.AI_Error_Plan_Limit_Data_Sources),
      'Two fit and the third is refused.'
    );
    Assert.isTrue(inactiveResult.isSuccess(), 'It can be saved inactive.');
    Assert.isFalse(activation.isSuccess(), 'But not activated past the limit.');
    Assert.isTrue(edit.isSuccess(), 'An active source can still be edited.');
  }

  @IsTest
  static void testScenario6() {
    List<AIWorkflowAction__c> flowActions = AIAssistTestDataFactory.createAIWorkflowActions(
      2,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'Some_Flow',
      false
    );
    AIWorkflowAction__c apexAction = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
      'SomeExecutor',
      false
    )[0];
    AIWorkflowAction__c refusedAction = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'Some_Flow',
      false
    )[0];
    checkActivationOnUnrestrictedPlan();
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      false
    );

    Test.startTest();
    Database.SaveResult notIncluded = Database.insert(refusedAction, false);

    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      false
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_ACTIVE_WORKFLOW_ACTIONS,
      1
    );
    Database.SaveResult apexResult = Database.insert(apexAction, false);
    List<Database.SaveResult> flowResults = Database.insert(flowActions, false);
    flowActions[0].Description__c = 'Edited while at the limit.';
    Database.SaveResult edit = Database.update(flowActions[0], false);
    Test.stopTest();

    Assert.isFalse(notIncluded.isSuccess(), 'Actions are not in the plan.');
    Assert.areEqual(
      Label.AI_Error_Plan_Actions_Not_Included,
      notIncluded.getErrors()[0].getMessage(),
      'The refusal is the plan label.'
    );
    Assert.isFalse(apexResult.isSuccess(), 'Apex is not in the plan.');
    Assert.areEqual(
      Label.AI_Error_Plan_Apex_Not_Included,
      apexResult.getErrors()[0].getMessage(),
      'The refusal is the plan label.'
    );
    Assert.areEqual(
      1,
      countFailures(flowResults, Label.AI_Error_Plan_Limit_Actions),
      'One fits and the second is refused.'
    );
    Assert.isTrue(edit.isSuccess(), 'An active action can still be edited.');
  }

  @IsTest
  static void testScenario7() {
    AIAssistTestDataFactory.createAIModelConfigurations(1, true); // Anthropic, active.
    List<AIModelConfiguration__c> otherProvider = AIAssistTestDataFactory.createAIModelConfigurations(
      2,
      false
    );
    for (AIModelConfiguration__c configuration : otherProvider)
      configuration.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI;
    otherProvider[1].IsActive__c = false;
    AIModelConfiguration__c sameProvider = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      false
    )[0];
    checkActivationOnUnrestrictedPlan();
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MULTIPLE_PROVIDERS_ALLOWED,
      false
    );

    Test.startTest();
    List<Database.SaveResult> insertResults = Database.insert(
      otherProvider,
      false
    );
    Database.SaveResult sameProviderResult = Database.insert(
      sameProvider,
      false
    );
    otherProvider[1].IsActive__c = true;
    Database.SaveResult activation = Database.update(otherProvider[1], false);

    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MULTIPLE_PROVIDERS_ALLOWED,
      true
    );
    Database.SaveResult allowedActivation = Database.update(
      otherProvider[1],
      false
    );
    Test.stopTest();

    Assert.isFalse(insertResults[0].isSuccess(), 'A second provider, active.');
    Assert.areEqual(
      Label.AI_Error_Plan_Providers_Limit,
      insertResults[0].getErrors()[0].getMessage(),
      'The refusal is the plan label.'
    );
    Assert.isTrue(
      insertResults[1].isSuccess(),
      'A second provider can be saved inactive.'
    );
    Assert.isTrue(
      sameProviderResult.isSuccess(),
      'Another configuration of the provider in use is fine.'
    );
    Assert.isFalse(activation.isSuccess(), 'But not activated.');
    Assert.isTrue(
      allowedActivation.isSuccess(),
      'A plan that allows several providers accepts it.'
    );
  }

  @IsTest
  static void testScenario8() {
    List<AIModelConfiguration__c> configurations = AIAssistTestDataFactory.createAIModelConfigurations(
      2,
      false
    );
    configurations[1]
      .AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI;
    checkActivationOnUnrestrictedPlan();
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MULTIPLE_PROVIDERS_ALLOWED,
      false
    );

    Test.startTest();
    List<Database.SaveResult> saveResults = Database.insert(
      configurations,
      false
    );
    Test.stopTest();

    Assert.isTrue(saveResults[0].isSuccess(), 'The first provider is taken.');
    Assert.isFalse(saveResults[1].isSuccess(), 'The second is refused.');
  }

  @IsTest
  static void testScenario9() {
    checkActivationOnUnrestrictedPlan();

    Test.startTest();
    try {
      AIPlanActivationService.checkAgents(null, null);
      AIPlanActivationService.checkAgents(new List<AIAgent__c>(), null);
      AIPlanActivationService.checkDataSources(null, null);
      AIPlanActivationService.checkWorkflowActions(null, null);
      AIPlanActivationService.checkModelConfigurations(null, null);
      AIPlanActivationService.checkModelConfigurations(
        new List<AIModelConfiguration__c>{ new AIModelConfiguration__c() },
        null
      );
    } catch (Exception ex) {
      Assert.fail('The checks must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.isTrue(
      AIPlanLimitService.isActivationChecked(),
      'The checks were on.'
    );
  }
}
