/*
Class Name: AIChatStateServiceTest

=================================================================
=================================================================

Description: Testing utility for AIChatStateService: the UI settings, what a user may do, channel and terms state.

=================================================================
=================================================================
Applicable Classes:

AIChatStateService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIChatStateServiceTest {
  // testScenario1: Build UI settings from a configured record and an empty one -> the configured values are used and the empty one gets the defaults.
  // testScenario2: Build the user state with no row, then with the UI settings on, then off -> no row grants nothing, the UI settings drive debug and Workflow Actions, the row drives export.
  // testScenario3: Check a channel with no row, no channel, a listed channel and an unlisted channel -> allowed unless the channel is not on the list.
  // testScenario4: Build the terms state unsigned, signed and with no version configured -> required only while the configured version is unsigned.
  // testScenario5: Set the blocked state for a ready user, inactive app, no agent and terms to accept -> each is named with its message and a ready user is not blocked.

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
    // [1] Build a configured UI settings record
    AIAssistUISettings__c ui = new AIAssistUISettings__c(
      ShowTimestampOnMessages__c = true,
      IsFeedbackEnabled__c = false,
      IsUserInitiatedChatEnabled__c = false,
      SuggestedActionsDisplay__c = AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS,
      MaxVisibleMessageHistory__c = 7
    );

    AIChatDataStructure.UiSettings configured;
    AIChatDataStructure.UiSettings defaults;

    // [2] Build the UI settings from the configured record and from an empty one
    Test.startTest();
    configured = AIChatStateService.buildUiSettings(ui);
    defaults = AIChatStateService.buildUiSettings(new AIAssistUISettings__c());
    Test.stopTest();

    // [3] Check the configured values are used and the empty record gets the defaults
    Assert.isTrue(
      configured.showTimestamps,
      'Timestamps should follow the setting.'
    );
    Assert.isFalse(
      configured.feedbackEnabled,
      'Feedback should be off when the setting is false.'
    );
    Assert.isTrue(
      configured.newChatsDisabled,
      'New chats should be disabled when user-initiated chat is off.'
    );

    Assert.areEqual(
      AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS,
      configured.suggestedActionsDisplay,
      'Inline buttons should be used when asked for.'
    );

    Assert.areEqual(
      7,
      configured.messagePageSize,
      'The configured page size should be used.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_DEFAULT_MESSAGE_PAGE_SIZE,
      defaults.messagePageSize,
      'The default page size should be used when none is set.'
    );
  }

  @IsTest
  static void testScenario2() {
    // [1] Build a user settings row with export enabled
    AIUserSettings__c row = new AIUserSettings__c(
      IsActive__c = true,
      ConversationExportEnabled__c = true
    );

    AIChatDataStructure.UserState none;
    AIChatDataStructure.UserState full;
    AIChatDataStructure.UserState off;

    // [2] Build the user state with no row, then with the UI settings on, then off
    Test.startTest();
    none = AIChatStateService.buildUserState(null);

    AIAssistTestDataFactory.upsertUiSettings(true, true);
    full = AIChatStateService.buildUserState(row);

    AIAssistTestDataFactory.upsertUiSettings(false, false);
    off = AIChatStateService.buildUserState(row);
    Test.stopTest();

    // [3] Check what each state grants
    Assert.isFalse(
      none.debugMode || none.exportEnabled || none.workflowActionsEnabled,
      'A user with no row and no UI settings should have nothing.'
    );
    Assert.isTrue(
      full.debugMode && full.exportEnabled && full.workflowActionsEnabled,
      'The UI settings and a row with export should grant everything.'
    );

    Assert.isFalse(
      off.debugMode || off.workflowActionsEnabled,
      'Debug mode and Workflow Actions should follow the UI settings.'
    );
    Assert.isTrue(off.exportEnabled, 'Export should follow the user\'s row.');

    Assert.areEqual(
      UserInfo.getUserId(),
      none.userId,
      'The state should be for the signed-in user.'
    );
  }

  @IsTest
  static void testScenario3() {
    // [1] Build a user settings row that allows only the mobile channel
    AIUserSettings__c row = new AIUserSettings__c(
      AllowedChannels__c = AIAssistApplicationConstants.CHANNEL_MOBILE
    );

    Boolean noRow;
    Boolean noChannel;
    Boolean listed;
    Boolean unlisted;

    // [2] Check a channel with no row, no channel, a listed channel and an unlisted channel
    Test.startTest();
    noRow = AIChatStateService.isChannelAllowed(
      null,
      AIAssistApplicationConstants.CHANNEL_UTILITY_BAR
    );
    noChannel = AIChatStateService.isChannelAllowed(row, null);
    listed = AIChatStateService.isChannelAllowed(
      row,
      AIAssistApplicationConstants.CHANNEL_MOBILE
    );
    unlisted = AIChatStateService.isChannelAllowed(
      row,
      AIAssistApplicationConstants.CHANNEL_UTILITY_BAR
    );
    Test.stopTest();

    // [3] Check a channel is allowed unless it is not on the list
    Assert.isTrue(
      noRow,
      'A channel should be allowed when the user has no row.'
    );
    Assert.isTrue(noChannel, 'A missing channel should be allowed.');

    Assert.isTrue(listed, 'A channel on the list should be allowed.');
    Assert.isFalse(
      unlisted,
      'A channel not on the list should not be allowed.'
    );
  }

  @IsTest
  static void testScenario4() {
    // [1] Configure a current terms version and policy link
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.CurrentTermsVersion__c = 'v3';
    settings.AIUsagePolicyUrl__c = 'https://example.com/policy';

    AIChatDataStructure.TermsState unsigned;
    AIChatDataStructure.TermsState signed;
    AIChatDataStructure.TermsState none;

    // [2] Build the terms state unsigned, then signed, then with no version configured
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

    // [3] Check the terms are required only while the configured version is unsigned
    Assert.isTrue(
      unsigned.required,
      'The terms should be required until the version is signed.'
    );
    Assert.areEqual(
      'https://example.com/policy',
      unsigned.policyUrl,
      'The policy link should be passed on.'
    );

    Assert.isFalse(
      signed.required,
      'The terms should not be required once signed.'
    );

    Assert.isFalse(
      none.required,
      'The terms should not be required when none are configured.'
    );
  }

  @IsTest
  static void testScenario5() {
    // [1] Load the settings and build the contexts for each state
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();

    AIChatDataStructure.ChatContext notBlocked = new AIChatDataStructure.ChatContext();
    notBlocked.state = AIAssistApplicationConstants.CHAT_STATE_READY;

    AIChatDataStructure.ChatContext inactive = new AIChatDataStructure.ChatContext();
    inactive.state = AIAssistApplicationConstants.CHAT_STATE_INACTIVE;

    AIChatDataStructure.ChatContext notAssigned = new AIChatDataStructure.ChatContext();
    notAssigned.state = AIAssistApplicationConstants.CHAT_STATE_NO_AGENT;

    AIChatDataStructure.ChatContext termsContext = new AIChatDataStructure.ChatContext();
    termsContext.state = AIAssistApplicationConstants.CHAT_STATE_TERMS;
    termsContext.terms = new AIChatDataStructure.TermsState();
    termsContext.terms.required = true;

    // [2] Set the blocked state for a ready user, an inactive app, no agent and terms to accept
    Test.startTest();
    AIChatStateService.setBlockedState(notBlocked);

    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    AIChatStateService.setBlockedState(inactive);

    settings.IsEnabled__c = true;
    update settings;
    AIAssistSettingsService.cachedSettings = null;

    AIChatStateService.setBlockedState(notAssigned);
    AIChatStateService.setBlockedState(termsContext);
    Test.stopTest();

    // [3] Check each blocked state and message
    Assert.isNull(
      notBlocked.blockedState,
      'A ready user should not be blocked.'
    );

    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_BLOCKED_INACTIVE,
      inactive.blockedState,
      'A switched-off application should block the user.'
    );
    Assert.areEqual(
      Label.AI_Error_Application_Inactive,
      inactive.blockedMessage,
      'The inactive state should carry its message.'
    );

    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_BLOCKED_NOT_ASSIGNED,
      notAssigned.blockedState,
      'A user with no agent should be blocked as not assigned.'
    );

    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_BLOCKED_TERMS,
      termsContext.blockedState,
      'A user with terms to accept should be blocked.'
    );
  }
}
