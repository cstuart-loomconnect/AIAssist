/*
Class Name: AIChatController

=================================================================
=================================================================

Description: The Apex controller behind the AI Assist chat window. Every @AuraEnabled method is one round trip the
window makes; the logic is in the chat services, so this class only translates between what the window
asks for and what it is shown.

Sending and processing a message belongs to AIConversationMessageService. A refusal the window should
render in place (limits, paused, not assigned, terms) comes back as a SendResult whose status is
SENT, BLOCKED, LIMIT or ERROR, chosen from AIMessagingException.code and never from message text, with
the code itself and the Custom Label to show. Anything unexpected is logged once and the window gets
the generic label; provider, configuration and class names never reach it.

Every method that touches a conversation or reply first proves the signed-in user owns it
(AIChatConversationService). Settings are read fresh on each call so a change shows on the next one.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from the old controller. Codes instead of message text, Custom Labels throughout, IsEnabled__c, the suggested action runs through the workflow dispatcher with its plan, user and assignment gates, and a decline records that the user cancelled.
*/

public with sharing class AIChatController {
  @AuraEnabled
  public static AIChatDataStructure.ChatContext getChatContext(
    String recordId,
    String objectApiName,
    String channel,
    String agentKey
  ) {
    try {
      AIChatDataStructure.ChatContext context = new AIChatDataStructure.ChatContext();
      context.channel = channel;

      AIAssistSettings__c appSettings = AIAssistSettingsService.getSettings();
      AIAssistUISettings__c uiSettings = AIAssistSettingsService.getUiSettings();
      AIUserSettings__c userSettings = AIChatStateService.getUserSettings();

      context.ui = AIChatStateService.buildUiSettings(uiSettings);
      context.user = AIChatStateService.buildUserState(userSettings);

      if (appSettings.IsEnabled__c == false) {
        context.state = AIAssistApplicationConstants.CHAT_STATE_INACTIVE;
        return context;
      }
      if (uiSettings.IsMaintenanceMode__c == true) {
        context.state = AIAssistApplicationConstants.CHAT_STATE_MAINTENANCE;
        return context;
      }
      if (!AIChatStateService.isChannelAllowed(userSettings, channel)) {
        context.state = AIAssistApplicationConstants.CHAT_STATE_CHANNEL_DISABLED;
        return context;
      }

      context.terms = AIChatStateService.buildTermsState(appSettings);
      if (context.terms.required) {
        context.state = AIAssistApplicationConstants.CHAT_STATE_TERMS;
        return context;
      }

      context.record = AIChatContextService.buildRecordContext(
        recordId,
        objectApiName
      );
      context.agents = AIChatContextService.getAvailableAgents(
        context.record.objectApiName
      );
      context.agent = AIChatContextService.selectAgent(
        context.agents,
        agentKey
      );

      if (context.agent == null) {
        context.state = AIAssistApplicationConstants.CHAT_STATE_NO_AGENT;
        return context;
      }

      context.state = AIAssistApplicationConstants.CHAT_STATE_READY;
      context.usage = AIChatUsageService.buildUsageState(userSettings);
      context.commands = AIChatCommandService.getAvailableCommands(
        context.agent.id,
        context.record
      );

      AIConversation__c activeConversation = AIChatConversationService.findActiveConversation(
        context.agent.id,
        context.record.recordId
      );

      if (activeConversation != null) {
        context.openConversation = AIChatConversationService.toConversationSummary(
          activeConversation
        );
        if (
          context.agent.loadTrigger !=
          AIAssistApplicationConstants.CONVERSATION_LOAD_TRIGGER_MANUAL_ONLY
        )
          context.conversation = AIChatConversationService.buildConversationView(
            activeConversation.Id,
            context.ui.messagePageSize,
            context.user,
            context.ui
          );
      }

      return context;
    } catch (Exception caughtException) {
      throw toAura(caughtException, 'getChatContext');
    }
  }

  @AuraEnabled
  public static AIChatDataStructure.MessagePage getEarlierMessages(
    Id conversationId,
    Id beforeMessageId
  ) {
    try {
      AIChatConversationService.assertOwnsConversation(conversationId);
      AIChatDataStructure.UiSettings uiSettings = AIChatStateService.buildUiSettings(
        AIAssistSettingsService.getUiSettings()
      );

      return AIChatConversationService.loadMessagePage(
        conversationId,
        beforeMessageId,
        uiSettings.messagePageSize,
        AIChatStateService.buildUserState(AIChatStateService.getUserSettings()),
        uiSettings
      );
    } catch (Exception caughtException) {
      throw toAura(caughtException, 'getEarlierMessages');
    }
  }

  // Called when AIMessageReadyEvent__e arrives, or by the polling fallback: every displayable message newer than afterMessageId, and whether a reply is still being worked on.
  @AuraEnabled
  public static AIChatDataStructure.ConversationUpdate getConversationUpdate(
    Id conversationId,
    Id afterMessageId
  ) {
    try {
      AIConversation__c conversation = AIChatConversationService.assertOwnsConversation(
        conversationId
      );
      AIUserSettings__c userSettings = AIChatStateService.getUserSettings();

      AIChatDataStructure.ConversationUpdate conversationUpdate = new AIChatDataStructure.ConversationUpdate();
      conversationUpdate.status = conversation.Status__c;
      conversationUpdate.isProcessing =
        conversation.ProcessingLockedUntil__c != null &&
        conversation.ProcessingLockedUntil__c > System.now();
      conversationUpdate.messages = AIChatConversationService.loadMessagesAfter(
        conversationId,
        afterMessageId,
        AIChatStateService.buildUserState(userSettings),
        AIChatStateService.buildUiSettings(
          AIAssistSettingsService.getUiSettings()
        )
      );
      conversationUpdate.usage = AIChatUsageService.buildUsageState(
        userSettings
      );

      return conversationUpdate;
    } catch (Exception caughtException) {
      throw toAura(caughtException, 'getConversationUpdate');
    }
  }

  // Never throws for an expected refusal: those come back as a status the window renders in place. Only an unexpected failure throws.
  @AuraEnabled
  public static AIChatDataStructure.SendResult sendMessage(String requestJson) {
    try {
      AIChatDataStructure.SendRequest request = (AIChatDataStructure.SendRequest) JSON.deserialize(
        requestJson,
        AIChatDataStructure.SendRequest.class
      );
      AIChatDataStructure.SendResult result = new AIChatDataStructure.SendResult();
      String trimmedText = request.text == null ? '' : request.text.trim();
      String messageBody = trimmedText;

      if (AIChatCommandService.isCommandText(trimmedText)) {
        AIChatCommand__mdt command = AIChatCommandService.findCommand(
          AIChatCommandService.getCommandToken(trimmedText),
          request.agentId,
          request.objectApiName
        );

        if (command == null) {
          result.status = AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR;
          result.code = AIAssistApplicationConstants.ERROR_COMMAND_UNKNOWN;
          result.message = Label.AI_Error_Command_Unknown;
          return result;
        }

        if (String.isNotBlank(command.PromptText__c))
          messageBody =
            trimmedText +
            AIAssistApplicationConstants.CHAT_COMMAND_PROMPT_SEPARATOR +
            command.PromptText__c;
      }

      try {
        AIConversationMessage__c sentMessage = AIConversationMessageService.sendMessage(
          request.conversationId,
          request.agentId,
          messageBody,
          request.channel,
          request.objectApiName,
          request.recordId
        );

        result.status = AIAssistApplicationConstants.CHAT_SEND_STATUS_SENT;
        result.conversationId = sentMessage.AIConversation__c;
        result.isNewConversation =
          request.conversationId != sentMessage.AIConversation__c;
        result.userMessage = AIChatConversationService.toChatMessage(
          sentMessage,
          new Map<Id, AIWorkflowAction__c>(),
          null,
          null
        );
      } catch (AIMessagingException refusal) {
        // Already logged by the service when it was a fault; a refusal is the system working. The message is always a Custom Label.
        // How the window shows a refusal: LIMIT refreshes the usage banner, BLOCKED shows the "Not sent" card, ERROR is anything else. Chosen from the code, never from the text.
        if (!refusal.isRefusal) {
          result.status = AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR;
        } else if (
          new Set<String>{
              AIAssistApplicationConstants.ERROR_CONCURRENT_LIMIT,
              AIAssistApplicationConstants.ERROR_CONVERSATION_LIMIT_DAILY,
              AIAssistApplicationConstants.ERROR_DAILY_USAGE_LIMIT,
              AIAssistApplicationConstants.ERROR_PLAN_LIMIT_MESSAGES,
              AIAssistApplicationConstants.ERROR_PLAN_LIMIT_USAGE
            }
            .contains(refusal.code)
        ) {
          result.status = AIAssistApplicationConstants.CHAT_SEND_STATUS_LIMIT;
        } else if (
          new Set<String>{
              AIAssistApplicationConstants.ERROR_MESSAGE_EMPTY,
              AIAssistApplicationConstants.ERROR_MESSAGE_TOO_LONG,
              AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND
            }
            .contains(refusal.code)
        ) {
          result.status = AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR;
        } else {
          result.status = AIAssistApplicationConstants.CHAT_SEND_STATUS_BLOCKED;
        }
        result.code = refusal.code;
        result.message = refusal.getMessage();
      }

      result.usage = AIChatUsageService.buildUsageState(
        AIChatStateService.getUserSettings()
      );

      return result;
    } catch (Exception caughtException) {
      throw toAura(caughtException, 'sendMessage');
    }
  }

  // Try again after a failed reply, and Regenerate on the newest suggestingMessage. The same gates as sendMessage are applied inside the service.
  @AuraEnabled
  public static void retryLatestMessage(Id conversationId) {
    try {
      AIChatConversationService.assertOwnsConversation(conversationId);
      AIConversationMessageService.retryLatestUserMessage(conversationId);
    } catch (Exception caughtException) {
      throw toAura(caughtException, 'retryLatestMessage');
    }
  }

  @AuraEnabled
  public static void closeConversation(Id conversationId) {
    try {
      AIChatConversationService.assertOwnsConversation(conversationId);
      AIConversationMessageService.closeConversation(
        conversationId,
        AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED
      );
    } catch (Exception caughtException) {
      throw toAura(caughtException, 'closeConversation');
    }
  }

  @AuraEnabled
  public static AIChatDataStructure.ConversationView openConversation(
    Id conversationId
  ) {
    try {
      AIChatConversationService.assertOwnsConversation(conversationId);
      AIChatDataStructure.UiSettings uiSettings = AIChatStateService.buildUiSettings(
        AIAssistSettingsService.getUiSettings()
      );

      return AIChatConversationService.buildConversationView(
        conversationId,
        uiSettings.messagePageSize,
        AIChatStateService.buildUserState(AIChatStateService.getUserSettings()),
        uiSettings
      );
    } catch (Exception caughtException) {
      throw toAura(caughtException, 'openConversation');
    }
  }

  // Reopens a closed conversation, only when its agent allows resuming.
  @AuraEnabled
  public static AIChatDataStructure.ConversationView resumeConversation(
    Id conversationId
  ) {
    try {
      AIChatConversationService.resumeConversation(conversationId);
      return openConversation(conversationId);
    } catch (Exception caughtException) {
      throw toAura(caughtException, 'resumeConversation');
    }
  }

  @AuraEnabled
  public static List<AIChatDataStructure.ConversationSummary> getConversationHistory(
    String recordId,
    Boolean onlyThisRecord
  ) {
    try {
      return AIChatConversationService.getConversationHistory(
        recordId,
        onlyThisRecord
      );
    } catch (Exception caughtException) {
      throw toAura(caughtException, 'getConversationHistory');
    }
  }

  @AuraEnabled
  public static void submitFeedback(
    Id messageId,
    String rating,
    String reason,
    String comment
  ) {
    try {
      if (
        !AIChatStateService.buildUiSettings(
            AIAssistSettingsService.getUiSettings()
          )
          .feedbackEnabled
      )
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_NOT_AUTHORISED,
          Label.AI_Error_Not_Authorised
        );

      AIChatFeedbackService.submitFeedback(messageId, rating, reason, comment);
    } catch (Exception caughtException) {
      throw toAura(caughtException, 'submitFeedback');
    }
  }

  @AuraEnabled
  public static void acknowledgeTerms() {
    try {
      AIChatFeedbackService.acknowledgeTerms();
    } catch (Exception caughtException) {
      throw toAura(caughtException, 'acknowledgeTerms');
    }
  }

  // Runs the Workflow Action suggested on a reply, after the window's own confirmation. The dispatcher checks the plan, the user's setting, the assignment and records the evidence.
  @AuraEnabled
  public static AIChatDataStructure.ActionResult runSuggestedAction(
    Id messageId,
    String inputsJson
  ) {
    try {
      AIChatDataStructure.UiSettings uiSettings = AIChatStateService.buildUiSettings(
        AIAssistSettingsService.getUiSettings()
      );
      if (!uiSettings.inlineActionsEnabled)
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_ACTION_NOT_PERMITTED,
          Label.AI_Error_Action_Not_Permitted
        );

      return AIChatActionService.runSuggestedAction(
        AIChatConversationService.assertOwnsAgentMessage(messageId),
        inputsJson,
        true
      );
    } catch (Exception caughtException) {
      throw toAura(caughtException, 'runSuggestedAction');
    }
  }

  // The user pressed Cancel on the confirmation. Nothing runs; the evidence records that it was offered and declined.
  @AuraEnabled
  public static void declineSuggestedAction(Id messageId) {
    try {
      AIConversationMessage__c suggestingMessage = AIChatConversationService.assertOwnsAgentMessage(
        messageId
      );
      AIWorkflowActionDispatcher.recordDeclinedAction(
        suggestingMessage.SuggestedWorkflowAction__c,
        suggestingMessage.AIConversation__r.AIAgent__c,
        suggestingMessage.Id,
        AIChatDataStructure.toIdOrNull(
          suggestingMessage.AIConversation__r.RelatedRecordId__c
        )
      );
    } catch (Exception caughtException) {
      throw toAura(caughtException, 'declineSuggestedAction');
    }
  }

  @AuraEnabled
  public static AIChatDataStructure.DebugTrace getDebugTrace(Id messageId) {
    try {
      if (
        !AIChatStateService.buildUserState(AIChatStateService.getUserSettings())
          .debugMode
      )
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_NOT_AUTHORISED,
          Label.AI_Error_Not_Authorised
        );

      return AIChatDebugService.getDebugTrace(
        AIChatConversationService.assertOwnsAgentMessage(messageId)
      );
    } catch (Exception caughtException) {
      throw toAura(caughtException, 'getDebugTrace');
    }
  }

  @AuraEnabled
  public static String getPiiMappings(Id messageId) {
    try {
      if (
        !AIChatStateService.buildUserState(AIChatStateService.getUserSettings())
          .debugMode
      )
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_NOT_AUTHORISED,
          Label.AI_Error_Not_Authorised
        );

      return AIChatDebugService.getPiiMappings(
        AIChatConversationService.assertOwnsAgentMessage(messageId)
          .AIConversation__c
      );
    } catch (Exception caughtException) {
      throw toAura(caughtException, 'getPiiMappings');
    }
  }

  @AuraEnabled
  public static AIChatDataStructure.FailureDetail getFailureDetail(
    Id conversationId
  ) {
    try {
      AIChatConversationService.assertOwnsConversation(conversationId);

      return AIChatDebugService.getFailureDetail(
        conversationId,
        AIChatStateService.buildUserState(AIChatStateService.getUserSettings())
          .debugMode
      );
    } catch (Exception caughtException) {
      throw toAura(caughtException, 'getFailureDetail');
    }
  }

  @AuraEnabled
  public static String exportConversation(Id conversationId) {
    try {
      if (
        !AIChatStateService.buildUserState(AIChatStateService.getUserSettings())
          .exportEnabled
      )
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_NOT_AUTHORISED,
          Label.AI_Error_Not_Authorised
        );

      AIChatConversationService.assertOwnsConversation(conversationId);

      return AIChatConversationService.exportConversation(conversationId);
    } catch (Exception caughtException) {
      throw toAura(caughtException, 'exportConversation');
    }
  }

  // A refusal's text is already a Custom Label and is shown as it is. Anything else is logged once and the window gets the generic label.
  private static AuraHandledException toAura(
    Exception caughtException,
    String methodName
  ) {
    String errorText = Label.AI_Error_Generic;

    if (caughtException instanceof AIMessagingException) {
      errorText = caughtException.getMessage();
    } else {
      AIPlatformLogManager.logException(
        caughtException,
        'AIChatController',
        methodName
      );
    }

    AuraHandledException auraException = new AuraHandledException(errorText);
    auraException.setMessage(errorText);

    return auraException;
  }
}
