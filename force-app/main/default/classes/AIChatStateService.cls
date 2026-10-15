/*
Class Name: AIChatStateService

=================================================================
=================================================================

Description: Works out what state the chat window is in for the signed-in user (the settings behind ChatContext.state).

Step 1: Build the UI settings from the org's UI settings record
Step 2: Build what this user may do (debug, export, new chats, Workflow Actions) from their usage policy and the UI settings
Step 3: Check the channel is allowed and whether the terms have to be accepted
Step 4: Name the one reason the user cannot send a message right now, if there is one
Step 5: Say whether the user may use AI Assist (they need an active AI Usage Policy), and refuse a request from a user who may not

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIChatStateService {

    public class AIChatStateServiceException extends Exception {}

    // Builds the UI settings the chat window uses, with a sensible default for anything left blank.
    public static AIChatDataStructure.UiSettings buildUiSettings(AIAssistUISettings__c uiSettings) {

        // [1] Create the result
        AIChatDataStructure.UiSettings uiState = new AIChatDataStructure.UiSettings();

        // [2] Copy each flag across, keeping the default when the setting is blank
        uiState.showTimestamps = uiSettings.ShowTimestampOnMessages__c == true;
        uiState.feedbackEnabled = uiSettings.IsFeedbackEnabled__c != false;
        uiState.typingIndicatorEnabled = uiSettings.TypingIndicatorEnabled__c != false;
        uiState.showExecutionTrace = uiSettings.ShouldShowExecutionTrace__c == true;
        uiState.inlineActionsEnabled = uiSettings.IsInlineWorkflowActionsEnabled__c != false;

        // [3] Show suggested actions as cards unless inline buttons were asked for
        uiState.suggestedActionsDisplay = uiSettings.SuggestedActionsDisplay__c != null && uiSettings.SuggestedActionsDisplay__c.trim().equalsIgnoreCase(AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS) ? AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS : AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_CARDS;

        // [4] Use the configured page size when it is at least 1, otherwise the default
        uiState.messagePageSize = uiSettings.MaxVisibleMessageHistory__c != null && uiSettings.MaxVisibleMessageHistory__c >= 1 ? uiSettings.MaxVisibleMessageHistory__c.intValue() : AIAssistApplicationConstants.CHAT_DEFAULT_MESSAGE_PAGE_SIZE;

        return uiState;
    }

    // Builds what the signed-in user may do. Workflow Actions follow the UI settings; debug mode, export and new chats follow the user's usage policy, so with none there is no debug and no export, and new chats are allowed.
    public static AIChatDataStructure.UserState buildUserState(AIUsagePolicy__c usagePolicy) {

        // [1] Create the result for the signed-in user
        AIChatDataStructure.UserState userState = new AIChatDataStructure.UserState();
        userState.userId = UserInfo.getUserId();

        // [2] Use an empty policy when the user has none
        AIUsagePolicy__c policy = usagePolicy == null ? new AIUsagePolicy__c() : usagePolicy;

        // [3] Workflow Actions come from the UI settings, and debug mode, export and new chats from the user's usage policy; all need the application on
        Boolean isApplicationOn = AIAssistSettingsService.isEnabled();
        AIAssistUISettings__c uiSettings = AIAssistSettingsService.getUiSettings();
        userState.debugMode = isApplicationOn && policy.DebugModeEnabled__c == true;
        userState.exportEnabled = isApplicationOn && policy.ConversationExportEnabled__c == true;
        userState.workflowActionsEnabled = isApplicationOn && uiSettings.IsWorkflowActionsEnabled__c == true;
        userState.newChatsDisabled = usagePolicy != null && usagePolicy.IsUserInitiatedChatEnabled__c == false;

        return userState;
    }

    // The same rule the validator applies: no policy, no allow-list or no channel means allowed.
    public static Boolean isChannelAllowed(AIUsagePolicy__c usagePolicy, String channel) {

        // [1] Allow the channel when there is nothing to check it against
        if (usagePolicy == null || String.isBlank(usagePolicy.AllowedChannels__c) || String.isBlank(channel)) return true;

        // [2] Allow it only when it is on the user's list
        return new Set<String>(usagePolicy.AllowedChannels__c.split(AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR)).contains(channel);
    }

    // Required when terms are configured and the user has not signed the current version. With none configured there is nothing to accept.
    public static AIChatDataStructure.TermsState buildTermsState(AIAssistSettings__c appSettings) {

        // [1] Create the result
        AIChatDataStructure.TermsState termsState = new AIChatDataStructure.TermsState();

        // [2] Take the configured version and policy link
        termsState.version = String.isBlank(appSettings.CurrentTermsVersion__c) ? null : appSettings.CurrentTermsVersion__c.trim();
        termsState.policyUrl = appSettings.AIUsagePolicyUrl__c;

        // [3] The terms are required unless the user has already accepted this version
        termsState.required = AIMessageValidator.getTermsAcceptanceStatus(UserInfo.getUserId(), termsState.version) != AIMessageValidator.TERMS_ACCEPTED;

        return termsState;
    }

    // Fills in why the user cannot send a message right now. One reason is given, the first that applies, most fundamental first: the application, access, the terms, then the agent assignment. Every state the window can be blocked in is named here, so it does not have to work one out from the other fields.
    public static void setBlockedState(AIChatDataStructure.ChatContext context) {

        // [1] Read the application settings
        AIAssistSettings__c appSettings = AIAssistSettingsService.getSettings();

        // [2] Name the first reason that applies
        if (appSettings.IsEnabled__c == false) {

            context.blockedState = AIAssistApplicationConstants.CHAT_BLOCKED_INACTIVE;
            context.blockedMessage = Label.AI_Error_Application_Inactive;
        } else if (context.state == AIAssistApplicationConstants.CHAT_STATE_NO_ACCESS) {

            context.blockedState = AIAssistApplicationConstants.CHAT_BLOCKED_NO_ACCESS;
            context.blockedMessage = Label.AI_Error_No_Access;
        } else if (context.terms != null && context.terms.required) {

            context.blockedState = AIAssistApplicationConstants.CHAT_BLOCKED_TERMS;
        } else if (context.state == AIAssistApplicationConstants.CHAT_STATE_NO_AGENT) {

            context.blockedState = AIAssistApplicationConstants.CHAT_BLOCKED_NOT_ASSIGNED;
            context.blockedMessage = Label.AI_Chat_Blocked_Not_Assigned;
        }
    }

    // What the signed-in user may do with AI Assist: full use with an active AI Usage Policy, none without one.
    public static String getAccessLevel() {

        // [1] Ask the policy service
        return AIUsagePolicyService.getAccessLevel(UserInfo.getUserId());
    }

    // True when the signed-in user may use the window: an active AI Usage Policy applies to them.
    public static Boolean hasAccess() {

        // [1] Anything but none may use it
        return getAccessLevel() != AIAssistApplicationConstants.ACCESS_LEVEL_NONE;
    }

    // Stops a request from a user who may not use the window, with a Custom Label the window shows as it is.
    public static void requireAccess() {

        // [1] Refuse the user who has no active AI Usage Policy
        if (!hasAccess()) throw new AIChatStateServiceException(Label.AI_Error_No_Access);
    }

    // Gets the signed-in user's usage policy, or null when none applies to them. It is read in system mode because the User permission set cannot read the policy objects; only the signed-in user's policy is ever asked for.
    public static AIUsagePolicy__c getUsagePolicy() {

        // [1] Read the combined usage policy for the signed-in user
        return AIUsagePolicyService.getUsagePolicy(UserInfo.getUserId());
    }
}
