/*
Class Name: AIChatStateService

=================================================================
=================================================================

Description: What state the chat window is in for the signed-in user: the UI settings, what this user may do
(debug, export, Workflow Actions), whether the channel is allowed, and whether the terms have to be
accepted. The settings behind ChatContext.state.

The user's own AIUserSettings__c row is read in system mode through AIMessagingSelector, because the
User permission set cannot read it; only the signed-in user's row is ever asked for. With no row the
user has no debug, no export and no Workflow Actions, matching AIWorkflowActionDispatcher.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from the old state service. The user type and the terms copy on user settings are gone; Workflow Actions are off without a settings row.
*/

public with sharing class AIChatStateService {
  public static AIUserSettings__c getUserSettings() {
    return AIMessagingSelector.getUserSettings(UserInfo.getUserId());
  }

  public static AIChatDataStructure.UiSettings buildUiSettings(
    AIAssistUISettings__c uiSettings
  ) {
    AIChatDataStructure.UiSettings uiState = new AIChatDataStructure.UiSettings();
    uiState.showTimestamps = uiSettings.ShowTimestampOnMessages__c == true;
    uiState.feedbackEnabled = uiSettings.IsFeedbackEnabled__c != false;
    uiState.typingIndicatorEnabled =
      uiSettings.TypingIndicatorEnabled__c != false;
    uiState.showExecutionTrace = uiSettings.ShowExecutionTraceToUser__c == true;
    uiState.inlineActionsEnabled =
      uiSettings.AllowInlineWorkflowActions__c != false;
    uiState.newChatsDisabled =
      uiSettings.IsUserInitiatedChatEnabled__c == false;
    uiState.suggestedActionsDisplay = uiSettings.SuggestedActionsDisplay__c !=
      null &&
      uiSettings.SuggestedActionsDisplay__c.trim()
        .equalsIgnoreCase(
          AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS
        )
      ? AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS
      : AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_CARDS;
    uiState.messagePageSize = uiSettings.MaxVisibleMessageHistory__c != null &&
      uiSettings.MaxVisibleMessageHistory__c >= 1
      ? uiSettings.MaxVisibleMessageHistory__c.intValue()
      : AIAssistApplicationConstants.CHAT_DEFAULT_MESSAGE_PAGE_SIZE;

    return uiState;
  }

  public static AIChatDataStructure.UserState buildUserState(
    AIUserSettings__c userSettings
  ) {
    AIChatDataStructure.UserState userState = new AIChatDataStructure.UserState();
    userState.userId = UserInfo.getUserId();
    userState.firstName = UserInfo.getFirstName();

    if (userSettings == null)
      return userState;

    userState.debugMode = userSettings.DebugModeEnabled__c == true;
    userState.exportEnabled = userSettings.ConversationExportEnabled__c == true;
    userState.workflowActionsEnabled =
      userSettings.IsActive__c == true &&
      userSettings.WorkflowActionsEnabled__c == true;

    return userState;
  }

  // The same rule the validator applies: no row, no allow-list or no channel means allowed.
  public static Boolean isChannelAllowed(
    AIUserSettings__c userSettings,
    String channel
  ) {
    if (
      userSettings == null ||
      String.isBlank(userSettings.AllowedChannels__c) ||
      String.isBlank(channel)
    )
      return true;

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
    AIChatDataStructure.TermsState termsState = new AIChatDataStructure.TermsState();
    termsState.version = String.isBlank(appSettings.CurrentTermsVersion__c)
      ? null
      : appSettings.CurrentTermsVersion__c.trim();
    termsState.policyUrl = appSettings.AIUsagePolicyUrl__c;
    termsState.required =
      AIMessagingSelector.getTermsAcceptanceStatus(
        UserInfo.getUserId(),
        termsState.version
      ) != AIMessagingSelector.TERMS_ACCEPTED;

    return termsState;
  }
}
