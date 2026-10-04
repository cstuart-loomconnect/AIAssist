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
}
