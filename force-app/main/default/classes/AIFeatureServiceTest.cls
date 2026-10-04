/*
Class Name: AIFeatureServiceTest

=================================================================
=================================================================

Description: Testing utility for AIFeatureService: one check for whether a feature may be used, by plan, then org, then user, and the day the limits are counted in.

=================================================================
=================================================================
Applicable Classes:

AIFeatureService, AIAssistGlobalUtility

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIFeatureServiceTest {
  // testScenario1: The plan layer: a feature the plan does not include is refused as Plan, whatever the user holds; the spare features are off until the licence switches them on; an unknown feature is never enabled.
  // testScenario2: The org layer: with the application off, or activated in another org, a feature a user uses is refused as Org, while configuring a feature is not.
  // testScenario3: The user layer: the custom permission grants it, so does the user's settings, and with neither it is refused as User. Running actions needs the settings to be active; debug does not.
  // testScenario4: A feature with no user layer is enabled for everyone once the plan includes it, and the user state the chat window gets comes from the same check.
  // testScenario5: Day boundaries follow the org's time zone, not UTC: in Auckland a turn late on the 31st UTC is counted on the 1st, in the new month, and the usage row and the running totals agree.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  private static void setPlan(String parameterName, Object value) {
    AIPlanLimitService.setLimitForTest(parameterName, value);
  }

  @IsTest
  static void testScenario1() {
    AIUserSettings__c granted = new AIUserSettings__c(
      IsActive__c = true,
      WorkflowActionsEnabled__c = true
    );
    AIFeatureService.permissionForTest.put(
      AIAssistApplicationConstants.PERMISSION_RUN_ACTIONS,
      true
    );

    Test.startTest();
    setPlan(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      false
    );
    String withoutPlan = AIFeatureService.getBlockingLayer(
      AIAssistApplicationConstants.APP_FEATURE_RUN_ACTIONS,
      granted
    );
    setPlan(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );
    String withPlan = AIFeatureService.getBlockingLayer(
      AIAssistApplicationConstants.APP_FEATURE_RUN_ACTIONS,
      granted
    );
    setPlan(AIAssistApplicationConstants.FEATURE_BETA_FEATURES_ENABLED, null);
    Boolean betaUnset = AIFeatureService.isFeatureEnabled(
      AIAssistApplicationConstants.APP_FEATURE_BETA
    );
    setPlan(AIAssistApplicationConstants.FEATURE_BETA_FEATURES_ENABLED, true);
    Boolean betaSet = AIFeatureService.isFeatureEnabled(
      AIAssistApplicationConstants.APP_FEATURE_BETA
    );
    setPlan(
      AIAssistApplicationConstants.FEATURE_CONTINUATION_CHAT_ENABLED,
      null
    );
    Boolean continuationUnset = AIFeatureService.isFeatureEnabled(
      AIAssistApplicationConstants.APP_FEATURE_CONTINUATION_CHAT
    );
    Boolean unknown = AIFeatureService.isFeatureEnabled('Teleportation');
    Test.stopTest();

    Assert.areEqual(
      AIFeatureService.LAYER_PLAN,
      withoutPlan,
      'The plan decides first.'
    );
    Assert.isNull(withPlan, 'In the plan, on, and granted.');
    Assert.isFalse(betaUnset, 'A spare feature is off until switched on.');
    Assert.isTrue(betaSet, 'Switched on by the licence.');
    Assert.isFalse(continuationUnset, 'And so is the other spare one.');
    Assert.isFalse(unknown, 'An unknown feature is never enabled.');
  }

  @IsTest
  static void testScenario2() {
    setPlan(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );
    AIFeatureService.permissionForTest.put(
      AIAssistApplicationConstants.PERMISSION_DEBUG_MODE,
      true
    );
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();

    Test.startTest();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.clearCache();
    String debugWhileOff = AIFeatureService.getBlockingLayer(
      AIAssistApplicationConstants.APP_FEATURE_DEBUG_MODE,
      null
    );
    Boolean configuringWhileOff = AIFeatureService.isFeatureEnabled(
      AIAssistApplicationConstants.APP_FEATURE_WORKFLOW_ACTIONS
    );
    settings.IsEnabled__c = true;
    settings.ActivatedOrgId__c = '00D000000000001AAA';
    update settings;
    AIAssistSettingsService.clearCache();
    String debugInACopiedSandbox = AIFeatureService.getBlockingLayer(
      AIAssistApplicationConstants.APP_FEATURE_DEBUG_MODE,
      null
    );
    settings.ActivatedOrgId__c = null;
    update settings;
    AIAssistSettingsService.clearCache();
    Boolean debugWhileOn = AIFeatureService.isFeatureEnabled(
      AIAssistApplicationConstants.APP_FEATURE_DEBUG_MODE
    );
    Test.stopTest();

    Assert.areEqual(AIFeatureService.LAYER_ORG, debugWhileOff, 'Switched off.');
    Assert.isTrue(configuringWhileOff, 'Configuring does not need it on.');
    Assert.areEqual(
      AIFeatureService.LAYER_ORG,
      debugInACopiedSandbox,
      'Activated in another org.'
    );
    Assert.isTrue(debugWhileOn, 'On, and the permission is held.');
  }

  @IsTest
  static void testScenario3() {
    setPlan(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );
    String runActions = AIAssistApplicationConstants.APP_FEATURE_RUN_ACTIONS;
    String debugMode = AIAssistApplicationConstants.APP_FEATURE_DEBUG_MODE;
    AIFeatureService.permissionForTest.put(
      AIAssistApplicationConstants.PERMISSION_RUN_ACTIONS,
      false
    );
    AIFeatureService.permissionForTest.put(
      AIAssistApplicationConstants.PERMISSION_DEBUG_MODE,
      false
    );

    Test.startTest();
    String withNeither = AIFeatureService.getBlockingLayer(
      runActions,
      new AIUserSettings__c(IsActive__c = true)
    );
    // No settings passed and none in the org for this user: they are looked up.
    String withNoSettingsRow = AIFeatureService.getBlockingLayer(
      runActions,
      null
    );
    Boolean bySettings = AIFeatureService.isFeatureEnabled(
      runActions,
      new AIUserSettings__c(
        IsActive__c = true,
        WorkflowActionsEnabled__c = true
      )
    );
    Boolean byInactiveSettings = AIFeatureService.isFeatureEnabled(
      runActions,
      new AIUserSettings__c(
        IsActive__c = false,
        WorkflowActionsEnabled__c = true
      )
    );
    Boolean debugByInactiveSettings = AIFeatureService.isFeatureEnabled(
      debugMode,
      new AIUserSettings__c(IsActive__c = false, DebugModeEnabled__c = true)
    );
    AIFeatureService.permissionForTest.put(
      AIAssistApplicationConstants.PERMISSION_RUN_ACTIONS,
      true
    );
    Boolean byPermission = AIFeatureService.isFeatureEnabled(
      runActions,
      new AIUserSettings__c()
    );
    AIFeatureService.permissionForTest.clear();
    Boolean realPermissionCheck = AIFeatureService.isFeatureEnabled(
      runActions,
      new AIUserSettings__c(
        IsActive__c = true,
        WorkflowActionsEnabled__c = true
      )
    );
    Test.stopTest();

    Assert.areEqual(AIFeatureService.LAYER_USER, withNeither, 'Not granted.');
    Assert.areEqual(AIFeatureService.LAYER_USER, withNoSettingsRow, 'No row.');
    Assert.isTrue(bySettings, 'The user\'s settings grant it.');
    Assert.isFalse(byInactiveSettings, 'Actions need active settings.');
    Assert.isTrue(debugByInactiveSettings, 'Debug does not.');
    Assert.isTrue(byPermission, 'The custom permission grants it alone.');
    Assert.isTrue(realPermissionCheck, 'With the real permission check too.');
  }

  @IsTest
  static void testScenario4() {
    AIFeatureService.permissionForTest.put(
      AIAssistApplicationConstants.PERMISSION_DEBUG_MODE,
      true
    );
    AIFeatureService.permissionForTest.put(
      AIAssistApplicationConstants.PERMISSION_RUN_ACTIONS,
      false
    );
    setPlan(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );

    Test.startTest();
    setPlan(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      true
    );
    Boolean apexInPlan = AIFeatureService.isFeatureEnabled(
      AIAssistApplicationConstants.APP_FEATURE_APEX
    );
    setPlan(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      false
    );
    Boolean apexNotInPlan = AIFeatureService.isFeatureEnabled(
      AIAssistApplicationConstants.APP_FEATURE_APEX
    );
    setPlan(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
    Boolean rules = AIFeatureService.isFeatureEnabled(
      AIAssistApplicationConstants.APP_FEATURE_AI_RULES
    );
    setPlan(
      AIAssistApplicationConstants.FEATURE_MULTIPLE_PROVIDERS_ALLOWED,
      false
    );
    Boolean providers = AIFeatureService.isFeatureEnabled(
      AIAssistApplicationConstants.APP_FEATURE_MULTIPLE_PROVIDERS
    );
    AIChatDataStructure.UserState noSettings = AIChatStateService.buildUserState(
      null
    );
    AIChatDataStructure.UserState withSettings = AIChatStateService.buildUserState(
      new AIUserSettings__c(
        IsActive__c = true,
        WorkflowActionsEnabled__c = true,
        ConversationExportEnabled__c = true
      )
    );
    Test.stopTest();

    Assert.isTrue(apexInPlan, 'No user layer: the plan is enough.');
    Assert.isFalse(apexNotInPlan, 'Not in the plan.');
    Assert.isTrue(rules, 'In the plan.');
    Assert.isFalse(providers, 'Not in the plan.');
    Assert.isTrue(noSettings.debugMode, 'The permission, with no settings.');
    Assert.isFalse(noSettings.workflowActionsEnabled, 'Not granted.');
    Assert.isFalse(noSettings.exportEnabled, 'Export has no permission.');
    Assert.isTrue(withSettings.workflowActionsEnabled, 'By the settings.');
    Assert.isTrue(withSettings.exportEnabled, 'By the settings.');
  }

  @IsTest
  static void testScenario5() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIMessagingDataService.UsageDelta usageDelta = new AIMessagingDataService.UsageDelta();
    usageDelta.userId = chatUser.Id;
    usageDelta.agentId = agent.Id;
    usageDelta.messages = 1;
    usageDelta.inputTokens = 10;
    // Half past noon UTC on 31 March is half past one in the morning of 1 April in Auckland (UTC+13 in summer time).
    Datetime lateOnThe31stUtc = Datetime.newInstanceGmt(2026, 3, 31, 12, 30, 0);
    Datetime earlyOnThe31stUtc = Datetime.newInstanceGmt(2026, 3, 31, 9, 0, 0);

    Test.startTest();
    AIAssistGlobalUtility.orgTimeZoneSidKey = 'Pacific/Auckland';
    Date beforeMidnight = AIAssistGlobalUtility.getOrgDate(earlyOnThe31stUtc);
    Date afterMidnight = AIAssistGlobalUtility.getOrgDate(lateOnThe31stUtc);
    AIAssistGlobalUtility.nowForTest = earlyOnThe31stUtc;
    Datetime nextMidnight = AIAssistGlobalUtility.getNextOrgMidnight();
    AIMessagingDataService.addToDailyUsage(usageDelta);
    AIMessagingSelector.OrgUsage march = AIOrgUsageService.getUsage();
    AIAssistGlobalUtility.nowForTest = lateOnThe31stUtc;
    AIMessagingSelector.OrgUsage aprilBefore = AIOrgUsageService.getUsage();
    AIMessagingDataService.addToDailyUsage(usageDelta);
    AIMessagingSelector.OrgUsage aprilAfter = AIOrgUsageService.getUsage();
    AIAssistGlobalUtility.orgTimeZoneSidKey = 'America/Los_Angeles';
    Date inLosAngeles = AIAssistGlobalUtility.getOrgDate(lateOnThe31stUtc);
    Test.stopTest();

    Assert.areEqual(
      Date.newInstance(2026, 3, 31),
      beforeMidnight,
      'Still the 31st in Auckland at 22:00 there.'
    );
    Assert.areEqual(
      Date.newInstance(2026, 4, 1),
      afterMidnight,
      'Already the 1st in Auckland.'
    );
    Assert.areEqual(
      Date.newInstance(2026, 3, 31),
      inLosAngeles,
      'And still the 31st in Los Angeles.'
    );
    Assert.areEqual(
      Datetime.newInstanceGmt(2026, 3, 31, 11, 0, 0),
      nextMidnight,
      'Auckland\'s midnight is 11:00 UTC: that is when the day\'s limits reset.'
    );
    Assert.areEqual(1, march.month.messages, 'Counted in March.');
    Assert.areEqual(
      0,
      aprilBefore.month.messages,
      'A new month starts at zero at the org\'s midnight, not at UTC\'s.'
    );
    Assert.areEqual(0, aprilBefore.today.messages, 'And a new day.');
    Assert.areEqual(1, aprilAfter.month.messages, 'Counted in April.');
    Assert.areEqual(
      new Set<Date>{
        Date.newInstance(2026, 3, 31),
        Date.newInstance(2026, 4, 1)
      },
      new Set<Date>{
        [SELECT UsageDate__c FROM AIUsageDaily__c ORDER BY UsageDate__c][0]
        .UsageDate__c,
        [SELECT UsageDate__c FROM AIUsageDaily__c ORDER BY UsageDate__c][1]
        .UsageDate__c
      },
      'One usage row for each of the org\'s two days.'
    );
  }
}
