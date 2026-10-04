/*
Class Name: AIChatStateServiceTest

=================================================================
=================================================================

Description: Testing utility for AIChatStateService: the UI settings, what a user may do, channel and terms state.

=================================================================
=================================================================
Applicable Classes:

AIChatStateService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIChatStateServiceTest {
  // testScenario1: UI settings default sensibly and follow the org settings.
  // testScenario2: With no settings row a user has no debug, export or Workflow Actions, and with a row each follows its flag.
  // testScenario3: A channel is allowed with no row, no list or no channel, and otherwise only when it is on the list.
  // testScenario4: Terms are required until the current version is signed, and not when none is configured.
  // testScenario5: Each blocked state is named with its message: inactive, sandbox not activated, paused, no licence, not assigned, terms, usage limit and plan cap; a ready user is not blocked.
  // testScenario6: Busy when the queue is full, and the plan-cap warning from 80 percent of a monthly allowance until the cap itself.

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
    AIAssistUISettings__c ui = new AIAssistUISettings__c(
      ShowTimestampOnMessages__c = true,
      IsFeedbackEnabled__c = false,
      IsUserInitiatedChatEnabled__c = false,
      SuggestedActionsDisplay__c = AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS,
      MaxVisibleMessageHistory__c = 7
    );

    Test.startTest();
    AIChatDataStructure.UiSettings configured = AIChatStateService.buildUiSettings(
      ui
    );
    AIChatDataStructure.UiSettings defaults = AIChatStateService.buildUiSettings(
      new AIAssistUISettings__c()
    );
    Test.stopTest();

    Assert.isTrue(
      configured.showTimestamps &&
        !configured.feedbackEnabled &&
        configured.newChatsDisabled,
      'Configured.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS,
      configured.suggestedActionsDisplay,
      'Inline buttons.'
    );
    Assert.areEqual(7, configured.messagePageSize, 'Page size.');
    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_DEFAULT_MESSAGE_PAGE_SIZE,
      defaults.messagePageSize,
      'Default page size.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIUserSettings__c row = new AIUserSettings__c(
      IsActive__c = true,
      DebugModeEnabled__c = true,
      ConversationExportEnabled__c = true,
      WorkflowActionsEnabled__c = true
    );
    AIUserSettings__c inactive = new AIUserSettings__c(
      IsActive__c = false,
      WorkflowActionsEnabled__c = true
    );

    // Running an action also needs the plan to include Workflow Actions.
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );
    // The user running the tests may hold the custom permissions; this scenario is about a user who does not.
    AIFeatureService.permissionForTest.put(
      AIAssistApplicationConstants.PERMISSION_DEBUG_MODE,
      false
    );
    AIFeatureService.permissionForTest.put(
      AIAssistApplicationConstants.PERMISSION_RUN_ACTIONS,
      false
    );

    Test.startTest();
    AIChatDataStructure.UserState none = AIChatStateService.buildUserState(
      null
    );
    AIChatDataStructure.UserState full = AIChatStateService.buildUserState(row);
    AIChatDataStructure.UserState off = AIChatStateService.buildUserState(
      inactive
    );
    Test.stopTest();

    Assert.isFalse(
      none.debugMode || none.exportEnabled || none.workflowActionsEnabled,
      'Nothing without a row.'
    );
    Assert.isTrue(
      full.debugMode && full.exportEnabled && full.workflowActionsEnabled,
      'All on.'
    );
    Assert.isFalse(
      off.workflowActionsEnabled,
      'An inactive row grants nothing.'
    );
    Assert.areEqual(UserInfo.getUserId(), none.userId, 'The user.');
  }

  @IsTest
  static void testScenario3() {
    AIUserSettings__c row = new AIUserSettings__c(
      AllowedChannels__c = AIAssistApplicationConstants.CHANNEL_MOBILE
    );

    Test.startTest();
    Boolean noRow = AIChatStateService.isChannelAllowed(
      null,
      AIAssistApplicationConstants.CHANNEL_UTILITY_BAR
    );
    Boolean noChannel = AIChatStateService.isChannelAllowed(row, null);
    Boolean listed = AIChatStateService.isChannelAllowed(
      row,
      AIAssistApplicationConstants.CHANNEL_MOBILE
    );
    Boolean unlisted = AIChatStateService.isChannelAllowed(
      row,
      AIAssistApplicationConstants.CHANNEL_UTILITY_BAR
    );
    Test.stopTest();

    Assert.isTrue(noRow && noChannel && listed, 'Allowed.');
    Assert.isFalse(unlisted, 'Not on the list.');
  }

  @IsTest
  static void testScenario4() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.CurrentTermsVersion__c = 'v3';
    settings.AIUsagePolicyUrl__c = 'https://example.com/policy';
    AIChatDataStructure.TermsState unsigned;
    AIChatDataStructure.TermsState none;
    AIChatDataStructure.TermsState signed;

    Test.startTest();
    unsigned = AIChatStateService.buildTermsState(settings);
    insert AIAssistTestDataFactory.createAITermsAcknowledgments(
      UserInfo.getUserId(),
      'v3',
      1,
      false
    );
    signed = AIChatStateService.buildTermsState(settings);
    settings.CurrentTermsVersion__c = null;
    none = AIChatStateService.buildTermsState(settings);
    Test.stopTest();

    Assert.isTrue(unsigned.required, 'Required.');
    Assert.areEqual(
      'https://example.com/policy',
      unsigned.policyUrl,
      'The policy link.'
    );
    Assert.isFalse(signed.required, 'Signed.');
    Assert.isFalse(none.required, 'Nothing configured.');
  }

  private static AIChatDataStructure.ChatContext blocked(String state) {
    AIChatDataStructure.ChatContext context = new AIChatDataStructure.ChatContext();
    context.state = state;
    context.usage = new AIChatDataStructure.UsageState();
    AIChatStateService.setBlockedState(context);
    return context;
  }

  @IsTest
  static void testScenario5() {
    AIChatStateService.isLicensedForTest = true;
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_MESSAGES,
      null
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_USAGE,
      null
    );
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    String ready = AIAssistApplicationConstants.CHAT_STATE_READY;

    Test.startTest();
    AIChatDataStructure.ChatContext notBlocked = blocked(ready);

    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.clearCache();
    AIChatDataStructure.ChatContext inactive = blocked(
      AIAssistApplicationConstants.CHAT_STATE_INACTIVE
    );

    settings.IsEnabled__c = true;
    settings.ActivatedOrgId__c = '00D000000000001AAA';
    update settings;
    AIAssistSettingsService.clearCache();
    AIChatDataStructure.ChatContext sandbox = blocked(
      AIAssistApplicationConstants.CHAT_STATE_INACTIVE
    );

    settings.ActivatedOrgId__c = null;
    update settings;
    AIAssistSettingsService.clearCache();
    AIOrgLimitMonitor.State pausedState = new AIOrgLimitMonitor.State();
    pausedState.checkedAt = System.currentTimeMillis();
    AIOrgLimitMonitor.FeatureState chatPaused = new AIOrgLimitMonitor.FeatureState();
    chatPaused.mode = AIAssistApplicationConstants.LIMIT_MODE_PAUSED;
    pausedState.byFeature.put(
      AIAssistApplicationConstants.LIMIT_FEATURE_CHAT,
      chatPaused
    );
    AIOrgLimitMonitor.transactionState = pausedState;
    AIChatDataStructure.ChatContext paused = blocked(ready);
    AIOrgLimitMonitor.transactionState = new AIOrgLimitMonitor.State();
    AIOrgLimitMonitor.transactionState.checkedAt = System.currentTimeMillis();

    AIChatStateService.isLicensedForTest = false;
    AIChatDataStructure.ChatContext noLicence = blocked(ready);
    AIChatStateService.isLicensedForTest = null;
    AIChatDataStructure.ChatContext realLicenceCheck = blocked(ready);
    AIChatStateService.isLicensedForTest = true;

    AIChatDataStructure.ChatContext notAssigned = blocked(
      AIAssistApplicationConstants.CHAT_STATE_NO_AGENT
    );

    AIChatDataStructure.ChatContext termsContext = new AIChatDataStructure.ChatContext();
    termsContext.state = AIAssistApplicationConstants.CHAT_STATE_TERMS;
    termsContext.terms = new AIChatDataStructure.TermsState();
    termsContext.terms.required = true;
    AIChatStateService.setBlockedState(termsContext);

    AIChatDataStructure.ChatContext usageContext = new AIChatDataStructure.ChatContext();
    usageContext.state = ready;
    usageContext.usage = new AIChatDataStructure.UsageState();
    usageContext.usage.blockMessages = true;
    AIChatStateService.setBlockedState(usageContext);

    settings.OrgUsageStateJson__c =
      '{"day":"' +
      String.valueOf(AIAssistGlobalUtility.getOrgToday()) +
      '","dayMessages":0,"dayTokens":0,"monthMessages":100,"monthTokens":500}';
    update settings;
    AIAssistSettingsService.clearCache();
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_MESSAGES,
      100
    );
    AIChatDataStructure.ChatContext messageCap = blocked(ready);
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_MESSAGES,
      null
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_USAGE,
      500
    );
    AIChatDataStructure.ChatContext tokenCap = blocked(ready);
    Test.stopTest();

    Assert.isNull(notBlocked.blockedState, 'A ready user is not blocked.');
    Assert.isNull(notBlocked.planCapWarning, 'And is not warned.');
    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_BLOCKED_INACTIVE,
      inactive.blockedState,
      'Switched off.'
    );
    Assert.areEqual(
      Label.AI_Error_Application_Inactive,
      inactive.blockedMessage,
      'With its message.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_BLOCKED_SANDBOX_NOT_ACTIVATED,
      sandbox.blockedState,
      'Activated in another org.'
    );
    Assert.areEqual(
      Label.AI_Chat_Blocked_Sandbox,
      sandbox.blockedMessage,
      'With its message.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_BLOCKED_PAUSED,
      paused.blockedState,
      'Paused for the org\'s limits.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_BLOCKED_NO_LICENCE,
      noLicence.blockedState,
      'No licence.'
    );
    Assert.isNull(
      realLicenceCheck.blockedState,
      'Outside a managed package there is no licence to lack.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_BLOCKED_NOT_ASSIGNED,
      notAssigned.blockedState,
      'No agent for this user.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_BLOCKED_TERMS,
      termsContext.blockedState,
      'Terms to accept.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_BLOCKED_USAGE_LIMIT,
      usageContext.blockedState,
      'The user\'s own limit.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_BLOCKED_PLAN_CAP,
      messageCap.blockedState,
      'The plan\'s messages.'
    );
    Assert.isTrue(
      messageCap.blockedMessage.contains('100'),
      'Says how much the plan allows: ' + messageCap.blockedMessage
    );
    Assert.isNull(
      messageCap.planCapWarning,
      'At the cap it is a block, not a warning.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_BLOCKED_PLAN_CAP,
      tokenCap.blockedState,
      'The plan\'s tokens.'
    );
  }

  @IsTest
  static void testScenario6() {
    AIChatStateService.isLicensedForTest = true;
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_USAGE,
      null
    );
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.OrgUsageStateJson__c =
      '{"day":"' +
      String.valueOf(AIAssistGlobalUtility.getOrgToday()) +
      '","dayMessages":0,"dayTokens":0,"monthMessages":850,"monthTokens":0}';
    update settings;
    AIAssistSettingsService.clearCache();
    String ready = AIAssistApplicationConstants.CHAT_STATE_READY;

    Test.startTest();
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_MESSAGES,
      1000
    );
    AIChatDataStructure.ChatContext warned = blocked(ready);
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_MESSAGES,
      2000
    );
    AIChatDataStructure.ChatContext notYet = blocked(ready);
    AIChatDataStructure.ChatContext busy = new AIChatDataStructure.ChatContext();
    busy.state = ready;
    Integer queued = AIMessagingSelector.countQueuedMessageJobs();
    AIChatStateService.setBlockedState(busy);
    Test.stopTest();

    Assert.isNull(warned.blockedState, 'Not blocked at 85 percent.');
    Assert.areEqual(
      String.format(Label.AI_Chat_Plan_Cap_Warning, new List<String>{ '85' }),
      warned.planCapWarning,
      'Warned, with the percentage.'
    );
    Assert.isNull(notYet.planCapWarning, 'No warning under 80 percent.');
    Assert.areEqual(0, queued, 'Nothing is queued in this test.');
    Assert.isNull(
      busy.blockedState,
      'So it is not busy; busy needs the queue to be full.'
    );
  }
}
