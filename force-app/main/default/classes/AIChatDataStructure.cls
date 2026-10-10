/*
Class Name: AIChatDataStructure

=================================================================
=================================================================

Description: The response shapes and small shared helpers the chat services pass to the aiAssistChat component family.

Step 1: The chat services fill in these wrapper types, so none depends on AIChatController
Step 2: The controller returns them to the chat window, which already reads these shapes
Step 3: The helpers turn text into an Id and a developer name into a readable label

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIChatDataStructure {

    public class ChatContext {
        @AuraEnabled
        public String state;
        @AuraEnabled
        public String channel;
        @AuraEnabled
        public UiSettings ui;
        @AuraEnabled
        public UserState user;
        @AuraEnabled
        public TermsState terms;
        @AuraEnabled
        public RecordContext record;
        @AuraEnabled
        public List<AgentOption> agents = new List<AgentOption>();
        @AuraEnabled
        public AgentOption agent;
        @AuraEnabled
        public List<CommandOption> commands = new List<CommandOption>();
        @AuraEnabled
        public ConversationView conversation;
        @AuraEnabled
        public ConversationSummary openConversation;
        // Why the user cannot send a message right now (AIAssistApplicationConstants.CHAT_BLOCKED_*), and what to tell them. Both are empty when they can.
        @AuraEnabled
        public String blockedState;
        @AuraEnabled
        public String blockedMessage;
    }

    public class UiSettings {
        @AuraEnabled
        public Boolean showTimestamps = false;
        @AuraEnabled
        public Boolean feedbackEnabled = true;
        @AuraEnabled
        public Boolean typingIndicatorEnabled = true;
        @AuraEnabled
        public Boolean showExecutionTrace = false;
        @AuraEnabled
        public Boolean inlineActionsEnabled = true;
        @AuraEnabled
        public String suggestedActionsDisplay = AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_CARDS;
        @AuraEnabled
        public Integer messagePageSize = AIAssistApplicationConstants.CHAT_DEFAULT_MESSAGE_PAGE_SIZE;
        // Copied from UserState.newChatsDisabled by AIChatController, because the chat window reads it from the UI settings.
        @AuraEnabled
        public Boolean newChatsDisabled = false;
    }

    public class UserState {
        @AuraEnabled
        public Id userId;
        @AuraEnabled
        public Boolean debugMode = false;
        @AuraEnabled
        public Boolean exportEnabled = false;
        @AuraEnabled
        public Boolean workflowActionsEnabled = false;
        @AuraEnabled
        public Boolean newChatsDisabled = false;
    }

    public class TermsState {
        @AuraEnabled
        public Boolean required = false;
        @AuraEnabled
        public String version;
        @AuraEnabled
        public String policyUrl;
    }

    public class RecordContext {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public String objectApiName;
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public String objectLabelPlural;
        @AuraEnabled
        public String recordName;
        @AuraEnabled
        public Boolean piiProtected = false;
    }

    public class AgentOption {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public String greeting;
        @AuraEnabled
        public String objectApiName;
        @AuraEnabled
        public String loadTrigger;
        @AuraEnabled
        public Boolean allowResume = false;
    }

    public class CommandOption {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String command;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public String scopeLabel;
        @AuraEnabled
        public Boolean isRecordSpecific = false;
    }

    public class ConversationView {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String closeReason;
        @AuraEnabled
        public Id agentId;
        @AuraEnabled
        public String agentName;
        @AuraEnabled
        public Boolean isActive = false;
        @AuraEnabled
        public Boolean canResume = false;
        @AuraEnabled
        public Boolean isProcessing = false;
        @AuraEnabled
        public List<ChatMessage> messages = new List<ChatMessage>();
        @AuraEnabled
        public Boolean hasMoreMessages = false;
    }

    public class ConversationSummary {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String closeReason;
        @AuraEnabled
        public String agentName;
        @AuraEnabled
        public Integer messageCount = 0;
        @AuraEnabled
        public Datetime lastActivity;
        @AuraEnabled
        public String ownerName; // Only set on a conversation someone else started.
    }

    public class ChatMessage {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Id conversationId;
        @AuraEnabled
        public String sender;
        @AuraEnabled
        public String displayText;
        @AuraEnabled
        public Boolean isCommand = false;
        @AuraEnabled
        public String commandName;
        @AuraEnabled
        public Datetime createdDate;
        @AuraEnabled
        public Decimal tokenCount;
        @AuraEnabled
        public String feedbackRating;
        @AuraEnabled
        public SuggestedAction suggestedAction;
        @AuraEnabled
        public List<String> sources = new List<String>();
        @AuraEnabled
        public List<ExecutionStep> steps = new List<ExecutionStep>();
    }

    public class SuggestedAction {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public Boolean requiresConfirmation = false;
        @AuraEnabled
        public String confirmationMessage;
        @AuraEnabled
        public Boolean hasRun = false;
        @AuraEnabled
        public Boolean isScreenFlow = false;
        @AuraEnabled
        public List<ActionInputField> inputFields = new List<ActionInputField>();
    }

    public class ActionInputField {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String inputType;
        @AuraEnabled
        public Boolean required = false;
        @AuraEnabled
        public String helpText;
    }

    public class ExecutionStep {
        @AuraEnabled
        public Integer stepOrder;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Boolean isSuccess = false;
        @AuraEnabled
        public Long durationMs;
        @AuraEnabled
        public String stepType;
        @AuraEnabled
        public String stepDetail;
    }

    public class MessagePage {
        @AuraEnabled
        public List<ChatMessage> messages = new List<ChatMessage>();
        @AuraEnabled
        public Boolean hasMore = false;
    }

    public class ConversationUpdate {
        @AuraEnabled
        public List<ChatMessage> messages = new List<ChatMessage>();
        @AuraEnabled
        public Boolean isProcessing = false;
        @AuraEnabled
        public Boolean isHeld = false;
        @AuraEnabled
        public String status;
    }

    public class SendRequest {
        public Id conversationId;
        public Id agentId;
        public String text;
        public String channel;
        public Id recordId;
        public String objectApiName;
    }

    // The status is SENT, BLOCKED, LIMIT or ERROR.
    public class SendResult {
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String message;
        @AuraEnabled
        public Id conversationId;
        @AuraEnabled
        public Boolean isNewConversation = false;
        @AuraEnabled
        public ChatMessage userMessage;
    }

    public class FailureDetail {
        @AuraEnabled
        public String reference;
        @AuraEnabled
        public String debugDetail;
    }

    public class ActionResult {
        @AuraEnabled
        public Boolean isSuccess = false;
        @AuraEnabled
        public String message;
    }

    // What the window needs to render a Screen Flow: the flow to start and its input variables in the shape lightning-flow takes (name, type, value).
    public class ScreenFlowLaunch {
        @AuraEnabled
        public String flowApiName;
        @AuraEnabled
        public List<Map<String, Object>> inputVariables = new List<Map<String, Object>>();
    }

    public class DebugTrace {
        @AuraEnabled
        public Id conversationId;
        @AuraEnabled
        public String conversationName;
        @AuraEnabled
        public Id userMessageId;
        @AuraEnabled
        public Id replyMessageId;
        @AuraEnabled
        public Boolean isSuccess = true;
        @AuraEnabled
        public Long durationMs;
        @AuraEnabled
        public String modelConfiguration;
        @AuraEnabled
        public String provider;
        @AuraEnabled
        public String model;
        @AuraEnabled
        public Decimal promptTokens;
        @AuraEnabled
        public Decimal replyTokens;
        @AuraEnabled
        public Integer toolCalls = 0;
        @AuraEnabled
        public Integer piiFieldsMasked = 0;
        @AuraEnabled
        public Integer toolCallingIterationsUsed;
        @AuraEnabled
        public Integer toolCallingIterationsMax;
        @AuraEnabled
        public Integer attemptNumber;
        @AuraEnabled
        public String sentPreviewText;
        @AuraEnabled
        public String requestJson;
        @AuraEnabled
        public String responseJson;
        @AuraEnabled
        public List<ExecutionStep> steps = new List<ExecutionStep>();
    }

    // Turns text into an Id, or null when it is blank or not a valid Id.
    public static Id getIdOrNull(String value) {

        try {

            // [1] Blank text has no Id
            if (String.isBlank(value)) return null;

            // [2] Convert the text to an Id
            return Id.valueOf(value);

        } catch (Exception ex) {
            return null;
        }
    }

    // "ContactRoles" / "Contact_Roles" become "Contact Roles".
    public static String humanise(String developerName) {

        // [1] Nothing to tidy when the name is blank
        if (String.isBlank(developerName)) return '';

        // [2] Put a space at each underscore and each lower-to-upper change
        String spaced = developerName.replace('_', ' ').replaceAll('([a-z0-9])([A-Z])', '$1 $2').normalizeSpace();

        // [3] Capitalise the first letter
        return spaced.left(1).toUpperCase() + spaced.substring(1);
    }
}
