/*
Class Name: AIPlanUsageControllerTest

=================================================================
=================================================================

Description: Testing utility for AIPlanUsageController: the plan usage figures and the percentages worked out from them.

=================================================================
=================================================================
Applicable Classes:

AIPlanUsageController

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIPlanUsageControllerTest {
  // testScenario1: The month's messages and tokens come from the stored totals, against the plan's allowances, with the percentage rounded down and capped by nothing.
  // testScenario2: Active agents, data sources and actions are counted against the plan's limits, an unlimited one has no percentage, and the plan's features are listed.
  // testScenario3: Storage now is the footprint's, and the projection adds 30 days at this month's daily message rate, three records of 2 KB a message.
  // testScenario4: Each feature's mode, the org's and AI Assist's share of its limit, and its thresholds are returned.
  // testScenario5: Without the AIAssistManageConfiguration permission nothing is returned.

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

  private static void storeUsage(Decimal monthMessages, Decimal monthTokens) {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.OrgUsageStateJson__c =
      '{"day":"' +
      String.valueOf(AIAssistGlobalUtility.getOrgToday()) +
      '","dayMessages":0,"dayTokens":0,"monthMessages":' +
      monthMessages +
      ',"monthTokens":' +
      monthTokens +
      '}';
    update settings;
    AIAssistSettingsService.clearCache();
  }

  private static Map<String, AIPlanUsageController.Allowance> byName(
    List<AIPlanUsageController.Allowance> allowances
  ) {
    Map<String, AIPlanUsageController.Allowance> allowanceByName = new Map<String, AIPlanUsageController.Allowance>();
    for (AIPlanUsageController.Allowance allowance : allowances)
      allowanceByName.put(allowance.name, allowance);
    return allowanceByName;
  }

  @IsTest
  static void testScenario1() {
    allow(true);
    storeUsage(1250, 999999);
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_MESSAGES,
      5000
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_USAGE,
      1000000
    );

    Test.startTest();
    Integer rowsBefore = Limits.getQueryRows();
    AIPlanUsageController.PlanUsage planUsage = AIPlanUsageController.getPlanUsage();
    Test.stopTest();

    Map<String, AIPlanUsageController.Allowance> monthly = byName(
      planUsage.monthly
    );
    Assert.areEqual(
      1250,
      monthly.get('Messages').used,
      'From the stored total.'
    );
    Assert.areEqual(
      5000,
      monthly.get('Messages').allowed,
      'The plan\'s allowance.'
    );
    Assert.areEqual(25, monthly.get('Messages').percentUsed, '1,250 of 5,000.');
    Assert.areEqual(
      99,
      monthly.get('Tokens').percentUsed,
      'Rounded down: 99.9999 percent is not 100.'
    );
    Assert.areEqual(
      AIAssistGlobalUtility.getOrgToday()
        .toStartOfMonth()
        .addMonths(1)
        .format(),
      planUsage.renewsOn,
      'The first of next month.'
    );
    Assert.isTrue(rowsBefore >= 0);
  }

  @IsTest
  static void testScenario2() {
    allow(true);
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      2,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIAssistTestDataFactory.createAIDataSources(
      3,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account LIMIT 1',
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_ACTIVE_AGENTS,
      4
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_ACTIVE_DATA_SOURCES,
      3
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_ACTIVE_WORKFLOW_ACTIONS,
      null
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_MESSAGES,
      0
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      false
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_BETA_FEATURES_ENABLED,
      null
    );

    Test.startTest();
    AIPlanUsageController.PlanUsage planUsage = AIPlanUsageController.getPlanUsage();
    Test.stopTest();

    Map<String, AIPlanUsageController.Allowance> configuration = byName(
      planUsage.configuration
    );
    Assert.areEqual(
      2,
      configuration.get('Active agents').used,
      'Two active agents.'
    );
    Assert.areEqual(
      50,
      configuration.get('Active agents').percentUsed,
      'Two of four.'
    );
    Assert.areEqual(
      100,
      configuration.get('Active data sources').percentUsed,
      'Three of three.'
    );
    Assert.isNull(
      configuration.get('Active workflow actions').allowed,
      'Unlimited.'
    );
    Assert.isNull(
      configuration.get('Active workflow actions').percentUsed,
      'So no percentage.'
    );
    Assert.areEqual(
      100,
      byName(planUsage.monthly).get('Messages').percentUsed,
      'An allowance of zero is fully used.'
    );
    Assert.isTrue(
      planUsage.features.get(
        AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED
      ),
      'In the plan.'
    );
    Assert.isFalse(
      planUsage.features.get(
        AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED
      ),
      'Not in the plan.'
    );
    Assert.isFalse(
      planUsage.features.get(
        AIAssistApplicationConstants.FEATURE_BETA_FEATURES_ENABLED
      ),
      'A spare feature is off until set.'
    );
    Assert.isNotNull(agent.Id);
  }

  @IsTest
  static void testScenario3() {
    allow(true);
    Integer dayOfMonth = AIAssistGlobalUtility.getOrgToday().day();
    // 1,024 messages a day so far this month.
    storeUsage(1024 * dayOfMonth, 0);
    AIOrgLimitMonitor.Footprint footprint = new AIOrgLimitMonitor.Footprint();
    footprint.storageMegabytes = 40;
    footprint.asyncJobs = 77;
    footprint.events = 88;
    AIOrgLimitMonitor.testFootprint = footprint;

    Test.startTest();
    AIPlanUsageController.PlanUsage planUsage = AIPlanUsageController.getPlanUsage();
    Test.stopTest();

    Assert.areEqual(
      40,
      planUsage.storageMegabytes,
      'What the records take now.'
    );
    // 1,024 messages a day, 30 days, 3 records each, 2 KB a record = 180 MB more.
    Assert.areEqual(
      220,
      planUsage.projectedStorageMegabytes,
      'Now plus thirty days at this month\'s rate.'
    );
    Assert.areEqual(77, planUsage.asyncJobsLastDay, 'Its jobs.');
    Assert.areEqual(88, planUsage.eventsLastDay, 'Its events.');
  }

  @IsTest
  static void testScenario4() {
    allow(true);
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.ChatDegradedPercent__c = 40;
    settings.ChatPausedPercent__c = 60;
    settings.ChatAppSharePercent__c = 25;
    update settings;
    AIAssistSettingsService.clearCache();
    AIOrgLimitMonitor.testLimits = new Map<String, List<Decimal>>{
      'DailyAsyncApexExecutions' => new List<Decimal>{ 45, 100 },
      'DataStorageMB' => new List<Decimal>{ 0, 100 },
      'HourlyPublishedPlatformEvents' => new List<Decimal>{ 0, 100 }
    };
    AIOrgLimitMonitor.Footprint footprint = new AIOrgLimitMonitor.Footprint();
    footprint.asyncJobs = 10;
    AIOrgLimitMonitor.testFootprint = footprint;

    Test.startTest();
    AIPlanUsageController.PlanUsage planUsage = AIPlanUsageController.getPlanUsage();
    Test.stopTest();

    AIPlanUsageController.FeatureLimit chat;
    for (AIPlanUsageController.FeatureLimit featureLimit : planUsage.limits) {
      if (
        featureLimit.feature == AIAssistApplicationConstants.LIMIT_FEATURE_CHAT
      )
        chat = featureLimit;
    }
    Assert.areEqual(3, planUsage.limits.size(), 'Chat, Events and Logging.');
    Assert.areEqual(
      AIAssistApplicationConstants.LIMIT_MODE_DEGRADED,
      chat.mode,
      'Past 40 percent, under 60.'
    );
    Assert.areEqual(45, chat.orgPercent, 'How full the org\'s limit is.');
    Assert.areEqual(10, chat.appPercent, 'AI Assist\'s own share.');
    Assert.areEqual(40, chat.degradedPercent, 'Its thresholds.');
    Assert.areEqual(60, chat.pausedPercent, 'Its thresholds.');
    Assert.areEqual(25, chat.appSharePercent, 'Its share budget.');
  }

  @IsTest
  static void testScenario5() {
    allow(false);
    String refusal;

    Test.startTest();
    try {
      AIPlanUsageController.getPlanUsage();
    } catch (AuraHandledException refused) {
      refusal = refused.getMessage();
    }
    Test.stopTest();

    Assert.areEqual(Label.AI_Error_Not_Authorised, refusal, 'Refused.');
  }
}
