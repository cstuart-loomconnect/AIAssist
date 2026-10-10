/*
Class Name: AIChatController

=================================================================
=================================================================

Description: The Apex controller behind the AI Assist chat window.

Step 1: Open the window: build the chat context, up to the first state that stops it
Step 2: Send a message: turn a slash command into its hidden instructions and the Prompt Template it names, then hand the message to AIConversationMessageService
Step 3: Read and change conversations: earlier messages, updates, history, open, resume, retry and close
Step 4: Run, decline, give feedback on or debug a reply, and export a conversation, each after proving the user owns it
Step 5: Turn an expected refusal into its Custom Label, and log anything unexpected once and show the generic label

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIChatController {

    public class AIChatControllerException extends Exception {}

    // Opens the window: the chat context, plus why the user cannot send right now, if they cannot.
    @AuraEnabled
    public static AIChatDataStructure.ChatContext getChatContext(String recordId, String objectApiName, String channel, String agentKey) {

        try {

            // [1] Build everything the window needs to open
            AIChatDataStructure.ChatContext context = buildChatContext(recordId, objectApiName, channel, agentKey);

            // [2] Name why the user cannot send right now, and the plan-cap warning, for the window rather than leaving it to work them out
            AIChatStateService.setBlockedState(context);

            // [3] Return the context
            return context;

        } catch (Exception ex) {

            // [4] Show a package refusal as it is, which is already a Custom Label, and log anything else once so the window gets the generic label
            String errorText = Label.AI_Error_Generic;
            if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
            else AIPlatformLogManager.logException(ex, 'AIChatController', 'getChatContext');

            AuraHandledException auraException = new AuraHandledException(errorText);
            auraException.setMessage(errorText);
            throw auraException;
        }
    }

    // The page of messages before the one the window already shows.
    @AuraEnabled
    public static AIChatDataStructure.MessagePage getEarlierMessages(Id conversationId, Id beforeMessageId) {

        try {

            // [1] Check the user may view the conversation
            AIConversationVisibilityService.getViewableConversation(conversationId);

            // [2] Read the window's settings
            AIChatDataStructure.UiSettings uiSettings = AIChatStateService.buildUiSettings(AIAssistSettingsService.getUiSettings());

            // [3] Return the page of earlier messages
            return AIChatConversationService.loadMessagePage(conversationId, beforeMessageId, uiSettings.messagePageSize, AIChatStateService.buildUserState(AIChatStateService.getUserSettings()), uiSettings);

        } catch (Exception ex) {

            // [4] Show a package refusal as it is, which is already a Custom Label, and log anything else once so the window gets the generic label
            String errorText = Label.AI_Error_Generic;
            if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
            else AIPlatformLogManager.logException(ex, 'AIChatController', 'getEarlierMessages');

            AuraHandledException auraException = new AuraHandledException(errorText);
            auraException.setMessage(errorText);
            throw auraException;
        }
    }

    // Called by the window's polling: every displayable message newer than afterMessageId, and whether a reply is still being worked on.
    @AuraEnabled
    public static AIChatDataStructure.ConversationUpdate getConversationUpdate(Id conversationId, Id afterMessageId) {

        try {

            // [1] Check the user may view the conversation
            AIConversation__c conversation = AIConversationVisibilityService.getViewableConversation(conversationId);
            AIUserSettings__c userSettings = AIChatStateService.getUserSettings();

            // [2] Start a message of this user's that was held at the cap on messages in flight, now that a place may be free, because only its sender can start it. Only a conversation with a held message asks, so the other updates do no org-wide work
            Boolean isHeld = AIAssistSettingsService.getSettings().MaxMessagesInFlight__c != null && AIConversationMessageService.hasHeldMessage(conversationId);

            if (isHeld && AIConversationMessageService.startHeldMessage()) {

                conversation.ProcessingLockedUntil__c = System.now().addMinutes(1);
                isHeld = false;
            }

            // [3] Report the conversation's status, whether a reply is still being worked on and whether the message is still waiting for a place
            AIChatDataStructure.ConversationUpdate conversationUpdate = new AIChatDataStructure.ConversationUpdate();
            conversationUpdate.status = conversation.Status__c;
            conversationUpdate.isHeld = isHeld;
            conversationUpdate.isProcessing = isHeld || (conversation.ProcessingLockedUntil__c != null && conversation.ProcessingLockedUntil__c > System.now());

            // [4] Add the messages newer than the last one the window has
            conversationUpdate.messages = AIChatConversationService.loadMessagesAfter(conversationId, afterMessageId, AIChatStateService.buildUserState(userSettings), AIChatStateService.buildUiSettings(AIAssistSettingsService.getUiSettings()));

            // [5] Return the update
            return conversationUpdate;

        } catch (Exception ex) {

            // [6] Show a package refusal as it is, which is already a Custom Label, and log anything else once so the window gets the generic label
            String errorText = Label.AI_Error_Generic;
            if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
            else AIPlatformLogManager.logException(ex, 'AIChatController', 'getConversationUpdate');

            AuraHandledException auraException = new AuraHandledException(errorText);
            auraException.setMessage(errorText);
            throw auraException;
        }
    }

    // Never throws for an expected refusal: those come back as a status the window renders in place. Only an unexpected failure throws.
    @AuraEnabled
    public static AIChatDataStructure.SendResult sendMessage(String requestJson) {

        try {

            // [1] Read the request and trim the text the user typed
            AIChatDataStructure.SendRequest request = (AIChatDataStructure.SendRequest) JSON.deserialize(requestJson, AIChatDataStructure.SendRequest.class);
            AIChatDataStructure.SendResult result = new AIChatDataStructure.SendResult();
            String trimmedText = request.text == null ? '' : request.text.trim();
            String messageBody = trimmedText;
            Id promptTemplateId = null;

            if (AIChatCommandService.isCommandText(trimmedText)) {

                // [2] Find the slash command the user typed
                AIChatCommand__mdt command = AIChatCommandService.findCommand(AIChatCommandService.getCommandToken(trimmedText), request.agentId, request.objectApiName);

                // [3] Refuse a command that is unknown or not available to this user
                if (command == null) {

                    result.status = AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR;
                    result.message = Label.AI_Error_Command_Unknown;
                    return result;
                }

                // [4] Add the command's hidden instructions after what the user typed
                if (String.isNotBlank(command.PromptText__c)) messageBody = trimmedText + AIAssistApplicationConstants.CHAT_COMMAND_PROMPT_SEPARATOR + command.PromptText__c;

                // [5] Find the prompt template the command asks for, and refuse the command when that template is missing, inactive or another agent's
                if (String.isNotBlank(command.PromptTemplateDeveloperName__c)) {

                    AIPromptTemplate__c commandPromptTemplate = AIPromptTemplateService.findActiveTemplate(request.agentId, command.PromptTemplateDeveloperName__c);

                    if (commandPromptTemplate == null) {

                        result.status = AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR;
                        result.message = Label.AI_Error_Prompt_Template_Unavailable;
                        return result;
                    }

                    promptTemplateId = commandPromptTemplate.Id;
                }
            }

            try {

                // [6] Send the message and report it back to the window
                AIConversationMessage__c sentMessage = AIConversationMessageService.sendMessage(request.conversationId, request.agentId, messageBody, request.channel, request.objectApiName, request.recordId, promptTemplateId);

                result.status = AIAssistApplicationConstants.CHAT_SEND_STATUS_SENT;
                result.conversationId = sentMessage.AIConversation__c;
                result.isNewConversation = request.conversationId != sentMessage.AIConversation__c;
                result.userMessage = AIChatConversationService.buildChatMessage(sentMessage, new Map<Id, AIWorkflowAction__c>(), null, null);

            } catch (Exception ex) {

                // [7] Pass on an unexpected failure, because a package exception's message is always a Custom Label and anything else goes to the outer handler, which logs it and shows the generic label
                if (ex.getTypeName().startsWith('System.')) throw ex;

                // [8] Show the refusal in place
                result.status = AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR;
                result.message = ex.getMessage();
            }

            // [9] Return the result
            return result;

        } catch (Exception ex) {

            // [10] Show a package refusal as it is, which is already a Custom Label, and log anything else once so the window gets the generic label
            String errorText = Label.AI_Error_Generic;
            if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
            else AIPlatformLogManager.logException(ex, 'AIChatController', 'sendMessage');

            AuraHandledException auraException = new AuraHandledException(errorText);
            auraException.setMessage(errorText);
            throw auraException;
        }
    }

    // Try again after a failed reply, and Regenerate on the newest suggestingMessage. The same gates as sendMessage are applied inside the service.
    @AuraEnabled
    public static void retryLatestMessage(Id conversationId) {

        try {

            // [1] Check the user owns the conversation
            AIChatConversationService.getOwnedConversation(conversationId);

            // [2] Send the latest user message again
            AIConversationMessageService.retryLatestUserMessage(conversationId);

        } catch (Exception ex) {

            // [3] Show a package refusal as it is, which is already a Custom Label, and log anything else once so the window gets the generic label
            String errorText = Label.AI_Error_Generic;
            if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
            else AIPlatformLogManager.logException(ex, 'AIChatController', 'retryLatestMessage');

            AuraHandledException auraException = new AuraHandledException(errorText);
            auraException.setMessage(errorText);
            throw auraException;
        }
    }

    // Closes the conversation at the user's request.
    @AuraEnabled
    public static void closeConversation(Id conversationId) {

        try {

            // [1] Check the user owns the conversation
            AIChatConversationService.getOwnedConversation(conversationId);

            // [2] Close it, recording that the user closed it
            AIConversationMessageService.closeConversation(conversationId, AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED);

        } catch (Exception ex) {

            // [3] Show a package refusal as it is, which is already a Custom Label, and log anything else once so the window gets the generic label
            String errorText = Label.AI_Error_Generic;
            if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
            else AIPlatformLogManager.logException(ex, 'AIChatController', 'closeConversation');

            AuraHandledException auraException = new AuraHandledException(errorText);
            auraException.setMessage(errorText);
            throw auraException;
        }
    }

    // Opens a conversation the user may view, with its latest messages.
    @AuraEnabled
    public static AIChatDataStructure.ConversationView openConversation(Id conversationId) {

        try {

            // [1] Check the user may view the conversation
            AIConversationVisibilityService.getViewableConversation(conversationId);

            // [2] Read the window's settings
            AIChatDataStructure.UiSettings uiSettings = AIChatStateService.buildUiSettings(AIAssistSettingsService.getUiSettings());

            // [3] Return the conversation with its latest messages
            return AIChatConversationService.buildConversationView(conversationId, uiSettings.messagePageSize, AIChatStateService.buildUserState(AIChatStateService.getUserSettings()), uiSettings);

        } catch (Exception ex) {

            // [4] Show a package refusal as it is, which is already a Custom Label, and log anything else once so the window gets the generic label
            String errorText = Label.AI_Error_Generic;
            if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
            else AIPlatformLogManager.logException(ex, 'AIChatController', 'openConversation');

            AuraHandledException auraException = new AuraHandledException(errorText);
            auraException.setMessage(errorText);
            throw auraException;
        }
    }

    // Reopens a closed conversation, only when its agent allows resuming.
    @AuraEnabled
    public static AIChatDataStructure.ConversationView resumeConversation(Id conversationId) {

        try {

            // [1] Reopen the conversation, which the service refuses unless its agent allows resuming
            AIChatConversationService.resumeConversation(conversationId);

            // [2] Return the reopened conversation
            return openConversation(conversationId);

        } catch (Exception ex) {

            // [3] Show a package refusal as it is, which is already a Custom Label, and log anything else once so the window gets the generic label
            String errorText = Label.AI_Error_Generic;
            if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
            else AIPlatformLogManager.logException(ex, 'AIChatController', 'resumeConversation');

            AuraHandledException auraException = new AuraHandledException(errorText);
            auraException.setMessage(errorText);
            throw auraException;
        }
    }

    // The user's own past conversations, for this record only or for all records.
    @AuraEnabled
    public static List<AIChatDataStructure.ConversationSummary> getConversationHistory(String recordId, Boolean onlyThisRecord) {

        try {

            // [1] Return the user's conversation history
            return AIChatConversationService.getConversationHistory(recordId, onlyThisRecord);

        } catch (Exception ex) {

            // [2] Show a package refusal as it is, which is already a Custom Label, and log anything else once so the window gets the generic label
            String errorText = Label.AI_Error_Generic;
            if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
            else AIPlatformLogManager.logException(ex, 'AIChatController', 'getConversationHistory');

            AuraHandledException auraException = new AuraHandledException(errorText);
            auraException.setMessage(errorText);
            throw auraException;
        }
    }

    // Other people's conversations this user may read, under the agent's visibility and the user's own scope. Read-only.
    @AuraEnabled
    public static List<AIChatDataStructure.ConversationSummary> getSharedConversationHistory() {

        try {

            // [1] Return the shared conversation history
            return AIChatConversationService.getSharedConversationHistory();

        } catch (Exception ex) {

            // [2] Show a package refusal as it is, which is already a Custom Label, and log anything else once so the window gets the generic label
            String errorText = Label.AI_Error_Generic;
            if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
            else AIPlatformLogManager.logException(ex, 'AIChatController', 'getSharedConversationHistory');

            AuraHandledException auraException = new AuraHandledException(errorText);
            auraException.setMessage(errorText);
            throw auraException;
        }
    }

    // Records the user's rating of a reply, when the window has feedback switched on.
    @AuraEnabled
    public static void submitFeedback(Id messageId, String rating, String reason, String comment) {

        try {

            // [1] Refuse when feedback is switched off
            if (!AIChatStateService.buildUiSettings(AIAssistSettingsService.getUiSettings()).feedbackEnabled) throw new AIChatControllerException(Label.AI_Error_Not_Authorised);

            // [2] Save the feedback
            AIChatFeedbackService.submitFeedback(messageId, rating, reason, comment);

        } catch (Exception ex) {

            // [3] Show a package refusal as it is, which is already a Custom Label, and log anything else once so the window gets the generic label
            String errorText = Label.AI_Error_Generic;
            if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
            else AIPlatformLogManager.logException(ex, 'AIChatController', 'submitFeedback');

            AuraHandledException auraException = new AuraHandledException(errorText);
            auraException.setMessage(errorText);
            throw auraException;
        }
    }

    // Records that the user accepted the terms.
    @AuraEnabled
    public static void acknowledgeTerms() {

        try {

            // [1] Save the acknowledgment
            AIChatTermsService.acknowledgeTerms();

        } catch (Exception ex) {

            // [2] Show a package refusal as it is, which is already a Custom Label, and log anything else once so the window gets the generic label
            String errorText = Label.AI_Error_Generic;
            if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
            else AIPlatformLogManager.logException(ex, 'AIChatController', 'acknowledgeTerms');

            AuraHandledException auraException = new AuraHandledException(errorText);
            auraException.setMessage(errorText);
            throw auraException;
        }
    }

    // Runs the Workflow Action suggested on a reply, after the window's own confirmation. The dispatcher checks the plan, the user's setting, the assignment and records the evidence.
    @AuraEnabled
    public static AIChatDataStructure.ActionResult runSuggestedAction(Id messageId, String inputsJson) {

        try {

            // [1] Refuse when inline actions are switched off
            AIChatDataStructure.UiSettings uiSettings = AIChatStateService.buildUiSettings(AIAssistSettingsService.getUiSettings());
            if (!uiSettings.inlineActionsEnabled) throw new AIChatControllerException(Label.AI_Error_Action_Not_Permitted);

            // [2] Run the action on the reply the user owns, as confirmed
            return AIChatActionService.runSuggestedAction(AIChatConversationService.getOwnedAgentMessage(messageId), inputsJson, true);

        } catch (Exception ex) {

            // [3] Show a package refusal as it is, which is already a Custom Label, and log anything else once so the window gets the generic label
            String errorText = Label.AI_Error_Generic;
            if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
            else AIPlatformLogManager.logException(ex, 'AIChatController', 'runSuggestedAction');

            AuraHandledException auraException = new AuraHandledException(errorText);
            auraException.setMessage(errorText);
            throw auraException;
        }
    }

    // The user pressed Cancel on the confirmation. Nothing runs; the evidence records that it was offered and declined.
    @AuraEnabled
    public static void declineSuggestedAction(Id messageId) {

        try {

            // [1] Check the user owns the reply that suggested the action
            AIConversationMessage__c suggestingMessage = AIChatConversationService.getOwnedAgentMessage(messageId);

            // [2] Record that the action was offered and declined
            AIWorkflowActionDispatcher.recordDeclinedAction(suggestingMessage.SuggestedWorkflowAction__c, suggestingMessage.AIConversation__r.AIAgent__c, suggestingMessage.Id, AIChatDataStructure.getIdOrNull(suggestingMessage.AIConversation__r.RelatedRecordId__c));

        } catch (Exception ex) {

            // [3] Show a package refusal as it is, which is already a Custom Label, and log anything else once so the window gets the generic label
            String errorText = Label.AI_Error_Generic;
            if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
            else AIPlatformLogManager.logException(ex, 'AIChatController', 'declineSuggestedAction');

            AuraHandledException auraException = new AuraHandledException(errorText);
            auraException.setMessage(errorText);
            throw auraException;
        }
    }

    // The debug trace of a reply, only for a user with debug mode on.
    @AuraEnabled
    public static AIChatDataStructure.DebugTrace getDebugTrace(Id messageId) {

        try {

            // [1] Refuse when the user does not have debug mode
            if (!AIChatStateService.buildUserState(AIChatStateService.getUserSettings()).debugMode) throw new AIChatControllerException(Label.AI_Error_Not_Authorised);

            // [2] Return the trace of the reply the user owns
            return AIChatDebugService.getDebugTrace(AIChatConversationService.getOwnedAgentMessage(messageId));

        } catch (Exception ex) {

            // [3] Show a package refusal as it is, which is already a Custom Label, and log anything else once so the window gets the generic label
            String errorText = Label.AI_Error_Generic;
            if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
            else AIPlatformLogManager.logException(ex, 'AIChatController', 'getDebugTrace');

            AuraHandledException auraException = new AuraHandledException(errorText);
            auraException.setMessage(errorText);
            throw auraException;
        }
    }

    // Why a conversation failed, with more detail for a user with debug mode on.
    @AuraEnabled
    public static AIChatDataStructure.FailureDetail getFailureDetail(Id conversationId) {

        try {

            // [1] Check the user owns the conversation
            AIChatConversationService.getOwnedConversation(conversationId);

            // [2] Return the failure detail, with more for a user with debug mode on
            return AIChatDebugService.getFailureDetail(conversationId, AIChatStateService.buildUserState(AIChatStateService.getUserSettings()).debugMode);

        } catch (Exception ex) {

            // [3] Show a package refusal as it is, which is already a Custom Label, and log anything else once so the window gets the generic label
            String errorText = Label.AI_Error_Generic;
            if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
            else AIPlatformLogManager.logException(ex, 'AIChatController', 'getFailureDetail');

            AuraHandledException auraException = new AuraHandledException(errorText);
            auraException.setMessage(errorText);
            throw auraException;
        }
    }

    // Exports the conversation, only for a user with export switched on.
    @AuraEnabled
    public static String exportConversation(Id conversationId) {

        try {

            // [1] Refuse when export is switched off for the user
            if (!AIChatStateService.buildUserState(AIChatStateService.getUserSettings()).exportEnabled) throw new AIChatControllerException(Label.AI_Error_Not_Authorised);

            // [2] Check the user owns the conversation
            AIChatConversationService.getOwnedConversation(conversationId);

            // [3] Return the export
            return AIChatConversationService.exportConversation(conversationId);

        } catch (Exception ex) {

            // [4] Show a package refusal as it is, which is already a Custom Label, and log anything else once so the window gets the generic label
            String errorText = Label.AI_Error_Generic;
            if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
            else AIPlatformLogManager.logException(ex, 'AIChatController', 'exportConversation');

            AuraHandledException auraException = new AuraHandledException(errorText);
            auraException.setMessage(errorText);
            throw auraException;
        }
    }

    // Everything the window needs to open, up to the first state that stops it.
    private static AIChatDataStructure.ChatContext buildChatContext(String recordId, String objectApiName, String channel, String agentKey) {

        // [1] Start the context and read the settings
        AIChatDataStructure.ChatContext context = new AIChatDataStructure.ChatContext();
        context.channel = channel;

        AIAssistSettings__c appSettings = AIAssistSettingsService.getSettings();
        AIAssistUISettings__c uiSettings = AIAssistSettingsService.getUiSettings();
        AIUserSettings__c userSettings = AIChatStateService.getUserSettings();

        context.ui = AIChatStateService.buildUiSettings(uiSettings);
        context.user = AIChatStateService.buildUserState(userSettings);

        // [2] Stop when chat is switched off, or switched on in another org (a copied sandbox)
        if (!AIAssistSettingsService.isEnabled()) {

            context.state = AIAssistApplicationConstants.CHAT_STATE_INACTIVE;
            return context;
        }

        // [3] Stop when chat is in maintenance mode
        if (uiSettings.IsMaintenanceMode__c == true) {

            context.state = AIAssistApplicationConstants.CHAT_STATE_MAINTENANCE;
            return context;
        }

        // [4] Stop when the user's settings do not allow this channel
        if (!AIChatStateService.isChannelAllowed(userSettings, channel)) {

            context.state = AIAssistApplicationConstants.CHAT_STATE_CHANNEL_DISABLED;
            return context;
        }

        // [5] Stop when the user must accept the terms first
        context.terms = AIChatStateService.buildTermsState(appSettings);

        if (context.terms.required) {

            context.state = AIAssistApplicationConstants.CHAT_STATE_TERMS;
            return context;
        }

        // [6] Add the record and the agents offered for it, and pick the agent to open with
        context.record = AIChatContextService.buildRecordContext(recordId, objectApiName);
        context.agents = AIChatContextService.getAvailableAgents(context.record.objectApiName);
        context.agent = AIChatContextService.selectAgent(context.agents, agentKey);

        // [7] Stop when no agent is offered
        if (context.agent == null) {

            context.state = AIAssistApplicationConstants.CHAT_STATE_NO_AGENT;
            return context;
        }

        // [8] The window is ready: add the slash commands the user can use
        context.state = AIAssistApplicationConstants.CHAT_STATE_READY;
        context.commands = AIChatCommandService.getAvailableCommands(context.agent.id, context.record);

        // [9] Open the active conversation for this agent and record, if there is one
        AIConversation__c activeConversation = AIChatConversationService.findActiveConversation(context.agent.id, context.record.recordId);

        if (activeConversation != null) {

            context.openConversation = AIChatConversationService.buildConversationSummary(activeConversation);

            // [10] Load its messages unless the agent loads them only when the user asks
            if (context.agent.loadTrigger != AIAssistApplicationConstants.CONVERSATION_LOAD_TRIGGER_MANUAL_ONLY) context.conversation = AIChatConversationService.buildConversationView(activeConversation.Id, context.ui.messagePageSize, context.user, context.ui);
        }

        // [11] Return the context
        return context;
    }
}
