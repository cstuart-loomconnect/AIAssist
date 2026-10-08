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
2.0          Chandler Stuart          setBlockedState: every state the chat window can be blocked in, and the plan-cap warning. The user state comes from AIFeatureService.
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

    // Application and user in one place (AIFeatureService). A custom permission can grant debug mode or actions to a user with no settings row; export has no permission, so no row means no export.
    AIUserSettings__c settings = userSettings == null
      ? new AIUserSettings__c()
      : userSettings;
    userState.debugMode = AIFeatureService.isFeatureEnabled(
      AIAssistApplicationConstants.APP_FEATURE_DEBUG_MODE,
      settings
    );
    userState.exportEnabled = AIFeatureService.isFeatureEnabled(
      AIAssistApplicationConstants.APP_FEATURE_EXPORT,
      settings
    );
    userState.workflowActionsEnabled = AIFeatureService.isFeatureEnabled(
      AIAssistApplicationConstants.APP_FEATURE_RUN_ACTIONS,
      settings
    );

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

  // A test cannot change who holds a licence.
  @TestVisible
  private static Boolean isLicensedForTest;

  // Fills in why the user cannot send a message right now, One reason is given, the first that applies, most fundamental first: the application, the org's limits, the user's licence and access, the terms, then usage. Every state the window can be blocked in is named here, so it does not have to work one out from the other fields.
  public static void setBlockedState(AIChatDataStructure.ChatContext context) {
    AIAssistSettings__c appSettings = AIAssistSettingsService.getSettings();

    Boolean isLicensed = true;
    if (isLicensedForTest != null) {
      isLicensed = isLicensedForTest;
    } else {
      try {
        isLicensed = UserInfo.isCurrentUserLicensed(
          AIMessagingSelector.getPackageNamespace()
        );
      } catch (Exception notAManagedPackage) {
        isLicensed = true; // Not installed as a managed package (a development org): there is no licence to hold.
      }
    }

    if (AIAssistSettingsService.isActivatedElsewhere()) {
      context.blockedState = AIAssistApplicationConstants.CHAT_BLOCKED_SANDBOX_NOT_ACTIVATED;
      context.blockedMessage = Label.AI_Chat_Blocked_Sandbox;
    } else if (appSettings.IsEnabled__c == false) {
      context.blockedState = AIAssistApplicationConstants.CHAT_BLOCKED_INACTIVE;
      context.blockedMessage = Label.AI_Error_Application_Inactive;
    } else if (!isLicensed) {
      context.blockedState = AIAssistApplicationConstants.CHAT_BLOCKED_NO_LICENCE;
      context.blockedMessage = Label.AI_Chat_Blocked_No_Licence;
    } else if (context.terms != null && context.terms.required) {
      context.blockedState = AIAssistApplicationConstants.CHAT_BLOCKED_TERMS;
    } else if (
      context.state == AIAssistApplicationConstants.CHAT_STATE_NO_AGENT
    ) {
      context.blockedState = AIAssistApplicationConstants.CHAT_BLOCKED_NOT_ASSIGNED;
      context.blockedMessage = Label.AI_Chat_Blocked_Not_Assigned;
    } else if (
      context.state == AIAssistApplicationConstants.CHAT_STATE_READY &&
      AIMessagingSelector.countQueuedMessageJobs() >=
      AIAssistApplicationConstants.MAX_PENDING_PROCESSING_JOBS
    ) {
      context.blockedState = AIAssistApplicationConstants.CHAT_BLOCKED_BUSY;
      context.blockedMessage = Label.AI_Error_Service_Busy;
    }
  }
}
