/*
Class Name: AIChatStateService

=================================================================
=================================================================

Description: Works out what state the chat window is in for the signed-in user (the settings behind ChatContext.state).

Step 1: Build the UI settings from the org's UI settings record
Step 2: Build what this user may do (debug, export, Workflow Actions) from the UI settings and their own settings row
Step 3: Check the channel is allowed and whether the terms have to be accepted
Step 4: Name the one reason the user cannot send a message right now, if there is one

The user's own AIUserSettings__c row is read in system mode (AIUsagePolicyService.getUserSettings), because the
User permission set cannot read it; only the signed-in user's row is ever asked for.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIChatStateService {
  // Builds the UI settings the chat window uses, with a sensible default for anything left blank.
  public static AIChatDataStructure.UiSettings buildUiSettings(
    AIAssistUISettings__c uiSettings
  ) {
    // [1] Create the result
    AIChatDataStructure.UiSettings uiState = new AIChatDataStructure.UiSettings();

    // [2] Copy each flag across, keeping the default when the setting is blank
    uiState.showTimestamps = uiSettings.ShowTimestampOnMessages__c == true;
    uiState.feedbackEnabled = uiSettings.IsFeedbackEnabled__c != false;
    uiState.typingIndicatorEnabled =
      uiSettings.TypingIndicatorEnabled__c != false;
    uiState.showExecutionTrace = uiSettings.ShowExecutionTraceToUser__c == true;
    uiState.inlineActionsEnabled =
      uiSettings.AllowInlineWorkflowActions__c != false;
    uiState.newChatsDisabled =
      uiSettings.IsUserInitiatedChatEnabled__c == false;

    // [3] Show suggested actions as cards unless inline buttons were asked for
    uiState.suggestedActionsDisplay = uiSettings.SuggestedActionsDisplay__c !=
      null &&
      uiSettings.SuggestedActionsDisplay__c.trim()
        .equalsIgnoreCase(
          AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS
        )
      ? AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS
      : AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_CARDS;

    // [4] Use the configured page size when it is at least 1, otherwise the default
    uiState.messagePageSize = uiSettings.MaxVisibleMessageHistory__c != null &&
      uiSettings.MaxVisibleMessageHistory__c >= 1
      ? uiSettings.MaxVisibleMessageHistory__c.intValue()
      : AIAssistApplicationConstants.CHAT_DEFAULT_MESSAGE_PAGE_SIZE;

    return uiState;
  }

  // Builds what the signed-in user may do. Debug mode and Workflow Actions follow the UI settings; export follows the user's settings row, so with no row there is no export.
  public static AIChatDataStructure.UserState buildUserState(
    AIUserSettings__c userSettings
  ) {
    // [1] Create the result for the signed-in user
    AIChatDataStructure.UserState userState = new AIChatDataStructure.UserState();
    userState.userId = UserInfo.getUserId();

    // [2] Use an empty row when the user has none
    AIUserSettings__c settings = userSettings == null
      ? new AIUserSettings__c()
      : userSettings;

    // [3] Debug mode and Workflow Actions come from the UI settings, and export from the user's row; all need the application on
    Boolean isApplicationOn = AIAssistSettingsService.isEnabled();
    AIAssistUISettings__c uiSettings = AIAssistSettingsService.getUiSettings();
    userState.debugMode =
      isApplicationOn && uiSettings.IsDebugModeEnabled__c == true;
    userState.exportEnabled =
      isApplicationOn && settings.ConversationExportEnabled__c == true;
    userState.workflowActionsEnabled =
      isApplicationOn && uiSettings.AreWorkflowActionsEnabled__c == true;

    return userState;
  }

  // The same rule the validator applies: no row, no allow-list or no channel means allowed.
  public static Boolean isChannelAllowed(
    AIUserSettings__c userSettings,
    String channel
  ) {
    // [1] Allow the channel when there is nothing to check it against
    if (
      userSettings == null ||
      String.isBlank(userSettings.AllowedChannels__c) ||
      String.isBlank(channel)
    )
      return true;

    // [2] Allow it only when it is on the user's list
    return new Set<String>(
        userSettings.AllowedChannels__c.split(
          AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR
        )
      )
      .contains(channel);
  }

  // Required when terms are configured and the user has not signed the current version. With none configured there is nothing to accept.
  public static AIChatDataStructure.TermsState buildTermsState(
    AIAssistSettings__c appSettings
  ) {
    // [1] Create the result
    AIChatDataStructure.TermsState termsState = new AIChatDataStructure.TermsState();

    // [2] Take the configured version and policy link
    termsState.version = String.isBlank(appSettings.CurrentTermsVersion__c)
      ? null
      : appSettings.CurrentTermsVersion__c.trim();
    termsState.policyUrl = appSettings.AIUsagePolicyUrl__c;

    // [3] The terms are required unless the user has already accepted this version
    termsState.required =
      AIMessageValidator.getTermsAcceptanceStatus(
        UserInfo.getUserId(),
        termsState.version
      ) != AIMessageValidator.TERMS_ACCEPTED;

    return termsState;
  }

  // Fills in why the user cannot send a message right now. One reason is given, the first that applies, most fundamental first: the application, the terms, then the agent assignment. Every state the window can be blocked in is named here, so it does not have to work one out from the other fields.
  public static void setBlockedState(AIChatDataStructure.ChatContext context) {
    // [1] Read the application settings
    AIAssistSettings__c appSettings = AIAssistSettingsService.getSettings();

    // [2] Name the first reason that applies
    if (appSettings.IsEnabled__c == false) {
      context.blockedState = AIAssistApplicationConstants.CHAT_BLOCKED_INACTIVE;
      context.blockedMessage = Label.AI_Error_Application_Inactive;
    } else if (context.terms != null && context.terms.required) {
      context.blockedState = AIAssistApplicationConstants.CHAT_BLOCKED_TERMS;
    } else if (
      context.state == AIAssistApplicationConstants.CHAT_STATE_NO_AGENT
    ) {
      context.blockedState = AIAssistApplicationConstants.CHAT_BLOCKED_NOT_ASSIGNED;
      context.blockedMessage = Label.AI_Chat_Blocked_Not_Assigned;
    }
  }

  // Gets the signed-in user's own settings row, or null when they have none.
  public static AIUserSettings__c getUserSettings() {
    return AIUsagePolicyService.getUserSettings(UserInfo.getUserId());
  }
}
