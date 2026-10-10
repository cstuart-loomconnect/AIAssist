/*
Class Name: AIChatConversationService

=================================================================
=================================================================

Description: Loading, paging, listing, resuming and exporting the signed-in user's conversations.

Step 1: Check the user owns a conversation or an AI reply before anything else uses its Id
Step 2: Find, list and open the user's own conversations, and the shared ones they may read
Step 3: Load messages a page at a time, or all newer than the last one the window has, with steps, feedback and suggested actions
Step 4: Reopen a closed conversation when its agent allows it and the user is under their limit
Step 5: Export a conversation as a plain-text transcript with the real values restored

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIChatConversationService {

    public class AIChatConversationServiceException extends Exception {}

    private static final String MESSAGE_FIELDS = 'Id, AIConversation__c, Sender__c, MessageBody__c, TokenCount__c, ProcessingStatus__c, SuggestedWorkflowAction__c, ExecutionTraceJson__c, CreatedDate, (SELECT Rating__c FROM AIFeedbacks__r WHERE CreatedById = :userId ORDER BY CreatedDate DESC LIMIT 1)';

    private static final String CONVERSATION_FIELDS = 'Id, Name, Status__c, ConversationCloseReason__c, AIAgent__c, AIAgent__r.Name, AIAgent__r.IsActive__c, AIAgent__r.AllowConversationResume__c, MessageCount__c, RelatedRecordId__c, RelatedObjectAPIName__c, ProcessingLockedUntil__c, LastModifiedDate, (SELECT MessageBody__c FROM AIConversationMessages__r WHERE Sender__c = :userSender ORDER BY CreatedDate ASC LIMIT 1)';

    // The conversation, if the signed-in user owns it. Throws the same "not found" refusal for one they do not own and one that does not exist.
    public static AIConversation__c getOwnedConversation(Id conversationId) {

        // [1] Refuse an Id that is blank or is not a conversation
        if (conversationId == null || conversationId.getSobjectType() != AIConversation__c.SObjectType) throw new AIChatConversationServiceException(Label.AI_Error_Conversation_Not_Found);

        // [2] Find the conversation, only if the user owns it
        List<AIConversation__c> conversations = [SELECT Id, Status__c, AIAgent__c, ProcessingLockedUntil__c, RelatedRecordId__c FROM AIConversation__c WHERE Id = :conversationId AND OwnerId = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1];

        // [3] Refuse when there is none, with the same answer as for one that does not exist
        if (conversations.isEmpty()) throw new AIChatConversationServiceException(Label.AI_Error_Conversation_Not_Found);

        // [4] Return the conversation
        return conversations[0];
    }

    // The AI Agent reply, if it is in a conversation the signed-in user owns. Throws the "not found" refusal otherwise.
    public static AIConversationMessage__c getOwnedAgentMessage(Id messageId) {

        // [1] Refuse an Id that is blank or is not a message
        if (messageId == null || messageId.getSobjectType() != AIConversationMessage__c.SObjectType) throw new AIChatConversationServiceException(Label.AI_Error_Conversation_Not_Found);

        // [2] Find the message, only if it is an AI Agent reply in a conversation the user owns
        List<AIConversationMessage__c> messages = [SELECT Id, AIConversation__c, AIConversation__r.Name, AIConversation__r.RelatedRecordId__c, AIConversation__r.AIAgent__c, Sender__c, TokenCount__c, SuggestedWorkflowAction__c, ExecutionTraceJson__c, DebugRequestJson__c, DebugResponseJson__c, DebugSentPreviewText__c, PIIValuesMasked__c, CreatedDate FROM AIConversationMessage__c WHERE Id = :messageId AND AIConversation__r.OwnerId = :UserInfo.getUserId() AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT WITH SYSTEM_MODE LIMIT 1];

        // [3] Refuse when there is none
        if (messages.isEmpty()) throw new AIChatConversationServiceException(Label.AI_Error_Conversation_Not_Found);

        // [4] Return the message
        return messages[0];
    }

    // The user's newest Active conversation with this agent about this record (or about no record).
    public static AIConversation__c findActiveConversation(Id agentId, Id recordId) {

        // [1] Get the values the query needs
        String relatedRecordId = recordId == null ? null : String.valueOf(recordId);
        String userSender = AIAssistApplicationConstants.SENDER_USER;
        Id userId = UserInfo.getUserId();

        // [2] Find the user's newest Active conversation for this agent and record
        Map<String, Object> queryBinds = new Map<String, Object>{
            'userId' => userId,
            'agentId' => agentId,
            'relatedRecordId' => relatedRecordId,
            'activeStatus' => AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
            'userSender' => userSender
        };
        List<AIConversation__c> conversations = Database.queryWithBinds('SELECT ' + CONVERSATION_FIELDS + ' FROM AIConversation__c WHERE OwnerId = :userId AND AIAgent__c = :agentId AND RelatedRecordId__c = :relatedRecordId AND Status__c = :activeStatus ORDER BY LastModifiedDate DESC LIMIT 1', queryBinds, AccessLevel.SYSTEM_MODE);

        // [3] Return it, or nothing when there is none
        return conversations.isEmpty() ? null : conversations[0];
    }

    // Reopens a Closed conversation, only when its agent is active and allows resuming, and only if the user is under their concurrent limit.
    public static void resumeConversation(Id conversationId) {

        // [1] Check the user owns the conversation, and read its agent
        AIConversation__c conversation = getOwnedConversation(conversationId);
        List<AIAgent__c> conversationAgents = [SELECT Id, IsActive__c, AllowConversationResume__c, RetentionTrigger__c FROM AIAgent__c WHERE Id = :conversation.AIAgent__c WITH SYSTEM_MODE LIMIT 1];

        // [2] Refuse unless the conversation is Closed and its agent is active and allows resuming
        Boolean canResume = !conversationAgents.isEmpty() && conversationAgents[0].IsActive__c == true && conversationAgents[0].AllowConversationResume__c == true && conversation.Status__c == AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
        if (!canResume) throw new AIChatConversationServiceException(Label.AI_Error_Conversation_Closed);

        // [3] Refuse when the user is already at their concurrent conversation limit
        AIUsagePolicy__c usageLimits = AIUsagePolicyService.getUsageLimits(UserInfo.getUserId());

        if (usageLimits != null && usageLimits.MaxConcurrentConversations__c != null && countActiveConversations(UserInfo.getUserId()) >= usageLimits.MaxConcurrentConversations__c) {

            throw new AIChatConversationServiceException(Label.AI_Error_Concurrent_Limit);
        }

        // [4] Make the conversation Active again
        AIConversation__c reopened = new AIConversation__c(Id = conversationId, Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE, ConversationCloseReason__c = null, ConversationClosedTimestamp__c = null);

        // [5] Clear a retention date that counted from closing, because it is worked out again when the conversation next closes
        if (conversationAgents[0].RetentionTrigger__c == AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE) reopened.RetentionExpiryDate__c = null;

        // [6] Save it through the package gateway
        AIMessagingDataService.updateOrThrow(new List<SObject>{reopened});
    }

    // The history panel's list: the user's own conversations, newest activity first. onlyThisRecord narrows it to recordId.
    public static List<AIChatDataStructure.ConversationSummary> getConversationHistory(String recordId, Boolean onlyThisRecord) {

        // [1] Get the values the query needs
        Id userId = UserInfo.getUserId();
        Id typedRecordId = AIChatDataStructure.getIdOrNull(recordId);
        String userSender = AIAssistApplicationConstants.SENDER_USER;
        Boolean filterByRecord = onlyThisRecord == true && typedRecordId != null;

        // [2] Find the user's conversations, for this record only when asked
        Map<String, Object> queryBinds = new Map<String, Object>{
            'userId' => userId,
            'relatedRecordId' => typedRecordId == null ? null : String.valueOf(typedRecordId),
            'userSender' => userSender,
            'maxRows' => AIAssistApplicationConstants.CHAT_HISTORY_MAX_CONVERSATIONS
        };
        List<AIConversation__c> conversations = Database.queryWithBinds('SELECT ' + CONVERSATION_FIELDS + ' FROM AIConversation__c WHERE OwnerId = :userId' + (filterByRecord ? ' AND RelatedRecordId__c = :relatedRecordId' : '') + ' ORDER BY LastModifiedDate DESC LIMIT :maxRows', queryBinds, AccessLevel.SYSTEM_MODE);

        // [3] Turn each conversation into a summary
        List<AIChatDataStructure.ConversationSummary> summaries = new List<AIChatDataStructure.ConversationSummary>();

        for (AIConversation__c conversation : conversations) {

            summaries.add(buildConversationSummary(conversation));
        }

        // [4] Return the summaries
        return summaries;
    }

    // Conversations other people started that the user may read (see AIConversationVisibilityService), newest activity first. Read-only: none of them can be sent to, closed, resumed, exported or acted on.
    public static List<AIChatDataStructure.ConversationSummary> getSharedConversationHistory() {

        // [1] Start with no summaries
        List<AIChatDataStructure.ConversationSummary> summaries = new List<AIChatDataStructure.ConversationSummary>();

        // [2] Turn each conversation the user may read into a summary that names its owner
        List<AIConversation__c> sharedConversations = AIConversationVisibilityService.getSharedConversations(AIConversationVisibilityService.getEffectiveScope(AIChatStateService.getUserSettings()), CONVERSATION_FIELDS, new Map<String, Object>{'userSender' => AIAssistApplicationConstants.SENDER_USER}, AIAssistApplicationConstants.CHAT_HISTORY_MAX_CONVERSATIONS);

        for (AIConversation__c conversation : sharedConversations) {

            AIChatDataStructure.ConversationSummary summary = buildConversationSummary(conversation);
            summary.ownerName = conversation.Owner.Name;
            summaries.add(summary);
        }

        // [3] Return the summaries
        return summaries;
    }

    // A plain-text transcript, with the real values restored. Command instructions and System messages are left out. The caller has checked the user may export.
    public static String exportConversation(Id conversationId) {

        // [1] Read the conversation, only if the user owns it
        AIConversation__c conversation = [SELECT Name, AIAgent__r.Name FROM AIConversation__c WHERE Id = :conversationId AND OwnerId = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1];
        String agentName = conversation.AIAgent__r == null ? Label.AI_Chat_Title : conversation.AIAgent__r.Name;

        // [2] Start the transcript with the conversation and agent names and the time
        List<String> lines = new List<String>{
            conversation.Name + ' - ' + agentName,
            System.now().format(),
            ''
        };

        // [3] Find the real values behind the fake ones that masking sent to the model
        Map<String, String> realValueByFakeValue = AIChatDebugService.getRealValueByFakeValue(conversationId);

        // [4] Add each message that is not from the System, oldest first, with the real values restored in the AI Agent's replies
        for (AIConversationMessage__c message : [SELECT Sender__c, MessageBody__c, CreatedDate FROM AIConversationMessage__c WHERE AIConversation__c = :conversationId AND Sender__c != :AIAssistApplicationConstants.SENDER_SYSTEM WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC]) {

            String displayText = AIChatCommandService.getDisplayText(message.MessageBody__c);
            lines.add('[' + message.CreatedDate.format() + '] ' + (message.Sender__c == AIAssistApplicationConstants.SENDER_USER ? UserInfo.getName() : agentName) + ':');
            lines.add(message.Sender__c == AIAssistApplicationConstants.SENDER_AI_AGENT ? AIChatDebugService.restorePii(displayText, realValueByFakeValue) : displayText);
            lines.add('');
        }

        // [5] Return the transcript
        return String.join(lines, '\n');
    }

    // The caller has already checked the user may read the conversation: getOwnedConversation for their own, AIConversationVisibilityService.getViewableConversation when it may be someone else's.
    public static AIChatDataStructure.ConversationView buildConversationView(Id conversationId, Integer pageSize, AIChatDataStructure.UserState user, AIChatDataStructure.UiSettings ui) {

        // [1] Read the conversation
        String userSender = AIAssistApplicationConstants.SENDER_USER;
        Map<String, Object> queryBinds = new Map<String, Object>{
            'conversationId' => conversationId,
            'userSender' => userSender
        };
        AIConversation__c conversation = (AIConversation__c) Database.queryWithBinds('SELECT ' + CONVERSATION_FIELDS + ' FROM AIConversation__c WHERE Id = :conversationId LIMIT 1', queryBinds, AccessLevel.SYSTEM_MODE)[0];

        // [2] Copy its details onto the view, titling it after its first user message because a conversation has no title field
        AIChatDataStructure.ConversationView conversationView = new AIChatDataStructure.ConversationView();
        conversationView.id = conversation.Id;
        conversationView.name = conversation.Name;

        List<AIConversationMessage__c> firstUserMessages = conversation.AIConversationMessages__r;
        conversationView.title = firstUserMessages == null || firstUserMessages.isEmpty() ? conversation.Name : AIChatCommandService.getDisplayText(firstUserMessages[0].MessageBody__c).normalizeSpace().abbreviate(AIAssistApplicationConstants.CHAT_CONVERSATION_TITLE_MAX_LENGTH);

        conversationView.status = conversation.Status__c;
        conversationView.closeReason = conversation.ConversationCloseReason__c;
        conversationView.agentId = conversation.AIAgent__c;
        conversationView.agentName = conversation.AIAgent__r == null ? null : conversation.AIAgent__r.Name;
        conversationView.isActive = conversation.Status__c == AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE;
        conversationView.canResume = conversation.Status__c == AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED && conversation.AIAgent__r != null && conversation.AIAgent__r.IsActive__c == true && conversation.AIAgent__r.AllowConversationResume__c == true;
        conversationView.isProcessing = conversation.ProcessingLockedUntil__c != null && conversation.ProcessingLockedUntil__c > System.now();

        // [3] Add the latest page of messages
        AIChatDataStructure.MessagePage messagePage = loadMessagePage(conversationId, null, pageSize, user, ui);
        conversationView.messages = messagePage.messages;
        conversationView.hasMoreMessages = messagePage.hasMore;

        // [4] Return the view
        return conversationView;
    }

    // One page of displayable messages, oldest first. Queried newest first with one extra row, to learn whether there are more.
    public static AIChatDataStructure.MessagePage loadMessagePage(Id conversationId, Id beforeMessageId, Integer pageSize, AIChatDataStructure.UserState user, AIChatDataStructure.UiSettings ui) {

        // [1] Read the date of the message the page starts before, because messages from the same instant are split by Id
        List<AIConversationMessage__c> boundaryMessages = beforeMessageId == null ? new List<AIConversationMessage__c>() : [SELECT CreatedDate FROM AIConversationMessage__c WHERE Id = :beforeMessageId AND AIConversation__c = :conversationId WITH SYSTEM_MODE LIMIT 1];
        Datetime boundaryDate = boundaryMessages.isEmpty() ? null : boundaryMessages[0].CreatedDate;
        String boundaryFilter = boundaryMessages.isEmpty() ? '' : ' AND (CreatedDate < :boundaryDate OR (CreatedDate = :boundaryDate AND Id < :boundaryId))';

        // [2] Find the displayable messages before it, newest first, with one extra row
        Map<String, Object> queryBinds = new Map<String, Object>{
            'conversationId' => conversationId,
            'visibleSenders' => new Set<String>{AIAssistApplicationConstants.SENDER_USER, AIAssistApplicationConstants.SENDER_AI_AGENT},
            'boundaryDate' => boundaryDate,
            'boundaryId' => beforeMessageId,
            'userId' => UserInfo.getUserId(),
            'maxRows' => pageSize + 1
        };
        List<AIConversationMessage__c> newestFirst = (List<AIConversationMessage__c>) Database.queryWithBinds('SELECT ' + MESSAGE_FIELDS + ' FROM AIConversationMessage__c WHERE AIConversation__c = :conversationId AND Sender__c IN :visibleSenders AND IsSuperseded__c = FALSE' + boundaryFilter + ' ORDER BY CreatedDate DESC, Id DESC LIMIT :maxRows', queryBinds, AccessLevel.SYSTEM_MODE);

        // [3] Note whether there are more messages, and drop the extra row
        AIChatDataStructure.MessagePage messagePage = new AIChatDataStructure.MessagePage();
        messagePage.hasMore = newestFirst.size() > pageSize;

        if (messagePage.hasMore) newestFirst.remove(newestFirst.size() - 1);

        // [4] Put the messages oldest first
        List<AIConversationMessage__c> oldestFirst = new List<AIConversationMessage__c>();

        for (Integer index = newestFirst.size() - 1; index >= 0; index--) {

            oldestFirst.add(newestFirst[index]);
        }

        // [5] Find every suggested Workflow Action on the page in one query
        Map<Id, AIWorkflowAction__c> actionsById = new Map<Id, AIWorkflowAction__c>();

        if (ui.inlineActionsEnabled && user.workflowActionsEnabled) {

            Set<Id> actionIds = new Set<Id>();

            for (AIConversationMessage__c message : oldestFirst) {

                if (message.SuggestedWorkflowAction__c != null) actionIds.add(message.SuggestedWorkflowAction__c);
            }

            if (!actionIds.isEmpty()) actionsById = new Map<Id, AIWorkflowAction__c>([SELECT Id, ActionName__c, Description__c, RequiresConfirmation__c, ConfirmationMessage__c, InputSchema__c FROM AIWorkflowAction__c WHERE Id IN :actionIds AND IsActive__c = TRUE WITH SYSTEM_MODE]);
        }

        // [6] Turn each message into a chat message, restoring the real values in the AI Agent's replies
        List<AIChatDataStructure.ChatMessage> chatMessages = new List<AIChatDataStructure.ChatMessage>();
        Map<Id, Map<String, String>> realValueByFakeValueByConversation = new Map<Id, Map<String, String>>();

        for (AIConversationMessage__c message : oldestFirst) {

            AIChatDataStructure.ChatMessage chatMessage = buildChatMessage(message, actionsById, AIExecutionStepRecorder.parseTrace(message.ExecutionTraceJson__c), message.AIFeedbacks__r);

            if (chatMessage.sender == 'agent') {

                if (!realValueByFakeValueByConversation.containsKey(message.AIConversation__c)) realValueByFakeValueByConversation.put(message.AIConversation__c, AIChatDebugService.getRealValueByFakeValue(message.AIConversation__c));
                chatMessage.displayText = AIChatDebugService.restorePii(chatMessage.displayText, realValueByFakeValueByConversation.get(message.AIConversation__c));
            }

            chatMessages.add(chatMessage);
        }

        // [7] Return the page
        messagePage.messages = chatMessages;

        return messagePage;
    }

    // Every displayable message newer than afterMessageId (all of them when blank), oldest first, up to 200.
    public static List<AIChatDataStructure.ChatMessage> loadMessagesAfter(Id conversationId, Id afterMessageId, AIChatDataStructure.UserState user, AIChatDataStructure.UiSettings ui) {

        // [1] Read the date of the message the list starts after, because messages from the same instant are split by Id
        List<AIConversationMessage__c> boundaryMessages = afterMessageId == null ? new List<AIConversationMessage__c>() : [SELECT CreatedDate FROM AIConversationMessage__c WHERE Id = :afterMessageId AND AIConversation__c = :conversationId WITH SYSTEM_MODE LIMIT 1];
        Datetime boundaryDate = boundaryMessages.isEmpty() ? null : boundaryMessages[0].CreatedDate;
        String boundaryFilter = boundaryMessages.isEmpty() ? '' : ' AND (CreatedDate > :boundaryDate OR (CreatedDate = :boundaryDate AND Id > :boundaryId))';

        // [2] Find the displayable messages after it, oldest first
        Map<String, Object> queryBinds = new Map<String, Object>{
            'conversationId' => conversationId,
            'visibleSenders' => new Set<String>{AIAssistApplicationConstants.SENDER_USER, AIAssistApplicationConstants.SENDER_AI_AGENT},
            'boundaryDate' => boundaryDate,
            'boundaryId' => afterMessageId,
            'userId' => UserInfo.getUserId(),
            'maxRows' => 200
        };
        List<AIConversationMessage__c> newerMessages = (List<AIConversationMessage__c>) Database.queryWithBinds('SELECT ' + MESSAGE_FIELDS + ' FROM AIConversationMessage__c WHERE AIConversation__c = :conversationId AND Sender__c IN :visibleSenders AND IsSuperseded__c = FALSE' + boundaryFilter + ' ORDER BY CreatedDate ASC, Id ASC LIMIT :maxRows', queryBinds, AccessLevel.SYSTEM_MODE);

        // [3] Find every suggested Workflow Action in the list in one query
        Map<Id, AIWorkflowAction__c> actionsById = new Map<Id, AIWorkflowAction__c>();

        if (ui.inlineActionsEnabled && user.workflowActionsEnabled) {

            Set<Id> actionIds = new Set<Id>();

            for (AIConversationMessage__c message : newerMessages) {

                if (message.SuggestedWorkflowAction__c != null) actionIds.add(message.SuggestedWorkflowAction__c);
            }

            if (!actionIds.isEmpty()) actionsById = new Map<Id, AIWorkflowAction__c>([SELECT Id, ActionName__c, Description__c, RequiresConfirmation__c, ConfirmationMessage__c, InputSchema__c FROM AIWorkflowAction__c WHERE Id IN :actionIds AND IsActive__c = TRUE WITH SYSTEM_MODE]);
        }

        // [4] Turn each message into a chat message, restoring the real values in the AI Agent's replies
        List<AIChatDataStructure.ChatMessage> chatMessages = new List<AIChatDataStructure.ChatMessage>();
        Map<Id, Map<String, String>> realValueByFakeValueByConversation = new Map<Id, Map<String, String>>();

        for (AIConversationMessage__c message : newerMessages) {

            AIChatDataStructure.ChatMessage chatMessage = buildChatMessage(message, actionsById, AIExecutionStepRecorder.parseTrace(message.ExecutionTraceJson__c), message.AIFeedbacks__r);

            if (chatMessage.sender == 'agent') {

                if (!realValueByFakeValueByConversation.containsKey(message.AIConversation__c)) realValueByFakeValueByConversation.put(message.AIConversation__c, AIChatDebugService.getRealValueByFakeValue(message.AIConversation__c));
                chatMessage.displayText = AIChatDebugService.restorePii(chatMessage.displayText, realValueByFakeValueByConversation.get(message.AIConversation__c));
            }

            chatMessages.add(chatMessage);
        }

        // [5] Return the chat messages
        return chatMessages;
    }

    // Turns one message into what the window shows, with its steps, sources, feedback and suggested action.
    public static AIChatDataStructure.ChatMessage buildChatMessage(AIConversationMessage__c message, Map<Id, AIWorkflowAction__c> actionsById, List<AIExecutionStepRecorder.TraceStep> steps, List<AIFeedback__c> feedback) {

        // [1] Copy the message's details, with the hidden command instructions left out of the text
        AIChatDataStructure.ChatMessage chatMessage = new AIChatDataStructure.ChatMessage();
        chatMessage.id = message.Id;
        chatMessage.conversationId = message.AIConversation__c;
        chatMessage.sender = message.Sender__c == AIAssistApplicationConstants.SENDER_USER ? 'user' : 'agent';
        chatMessage.displayText = AIChatCommandService.getDisplayText(message.MessageBody__c);
        chatMessage.createdDate = message.CreatedDate == null ? System.now() : message.CreatedDate;
        chatMessage.tokenCount = message.TokenCount__c;

        // [2] Mark a user message that is a slash command
        if (chatMessage.sender == 'user' && AIChatCommandService.isCommandText(chatMessage.displayText)) {

            chatMessage.isCommand = true;
            chatMessage.commandName = AIChatCommandService.getCommandToken(chatMessage.displayText);
        }

        // [3] Add the user's latest rating
        if (feedback != null && !feedback.isEmpty()) chatMessage.feedbackRating = feedback[0].Rating__c;

        // [4] Add each execution step, noting the data sources it read and the actions that ran
        Set<Id> ranActionIds = new Set<Id>();
        Set<String> sourceNames = new Set<String>();

        for (AIExecutionStepRecorder.TraceStep step : steps == null ? new List<AIExecutionStepRecorder.TraceStep>() : steps) {

            chatMessage.steps.add(buildExecutionStep(step));
            if (String.isNotBlank(step.dataSource)) sourceNames.add(AIChatDataStructure.humanise(step.dataSource));
            if (String.isNotBlank(step.workflowActionId) && step.status == AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS) ranActionIds.add(Id.valueOf(step.workflowActionId));
        }

        chatMessage.sources.addAll(sourceNames);

        // [5] Add the suggested action card, and whether the action has already run
        if (message.SuggestedWorkflowAction__c != null && actionsById.containsKey(message.SuggestedWorkflowAction__c)) {

            chatMessage.suggestedAction = AIChatActionService.buildSuggestionAction(actionsById.get(message.SuggestedWorkflowAction__c));
            chatMessage.suggestedAction.hasRun = ranActionIds.contains(message.SuggestedWorkflowAction__c);
        }

        // [6] Return the chat message
        return chatMessage;
    }

    // The label is the step's stored detail, which names the template, data source or fields involved; a step with none is labelled by its type with a Custom Label.
    public static AIChatDataStructure.ExecutionStep buildExecutionStep(AIExecutionStepRecorder.TraceStep step) {

        // [1] Copy the four things a user may see, and the step number
        AIChatDataStructure.ExecutionStep executionStep = new AIChatDataStructure.ExecutionStep();
        executionStep.stepOrder = step.step;
        executionStep.stepType = step.stepType;
        executionStep.status = step.status;
        executionStep.isSuccess = step.status == AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS;
        executionStep.durationMs = step.ms;
        executionStep.stepDetail = step.stepDetail;

        // [2] Label the step: its stored detail, else the data source or action it used, else by its type
        if (String.isNotBlank(step.stepDetail)) executionStep.label = step.stepDetail;
        else if (String.isNotBlank(step.dataSource)) executionStep.label = Label.AI_Step_Reading_Data + ': ' + AIChatDataStructure.humanise(step.dataSource);
        else if (String.isNotBlank(step.workflowActionName)) executionStep.label = Label.AI_Step_Running_Action + ': ' + step.workflowActionName;
        else if (step.stepType == AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL) executionStep.label = Label.AI_Step_Calling_Model;
        else if (step.stepType == AIAssistApplicationConstants.STEP_TYPE_PII_MASKING) executionStep.label = Label.AI_Step_Protecting_Data;
        else if (step.stepType == AIAssistApplicationConstants.STEP_TYPE_PROMPT_ASSEMBLY) executionStep.label = Label.AI_Step_Preparing_Request;
        else executionStep.label = Label.AI_Step_Finalising;

        // [3] Return the step
        return executionStep;
    }

    // Turns one conversation into the summary the history panel shows.
    public static AIChatDataStructure.ConversationSummary buildConversationSummary(AIConversation__c conversation) {

        // [1] Copy the conversation's details onto the summary, titling it after its first user message because a conversation has no title field
        AIChatDataStructure.ConversationSummary summary = new AIChatDataStructure.ConversationSummary();
        summary.id = conversation.Id;

        List<AIConversationMessage__c> firstUserMessages = conversation.AIConversationMessages__r;
        summary.title = firstUserMessages == null || firstUserMessages.isEmpty() ? conversation.Name : AIChatCommandService.getDisplayText(firstUserMessages[0].MessageBody__c).normalizeSpace().abbreviate(AIAssistApplicationConstants.CHAT_CONVERSATION_TITLE_MAX_LENGTH);

        summary.status = conversation.Status__c;
        summary.closeReason = conversation.ConversationCloseReason__c;
        summary.agentName = conversation.AIAgent__r == null ? null : conversation.AIAgent__r.Name;
        summary.messageCount = conversation.MessageCount__c == null ? 0 : conversation.MessageCount__c.intValue();
        summary.lastActivity = conversation.LastModifiedDate;

        // [2] Return the summary
        return summary;
    }

    // The user's conversations that count towards the concurrent limit: Active, and with activity inside their agent's idle timeout. One past its timeout is only waiting for the maintenance job to close it, so it does not hold a place. An agent with no timeout counts every Active conversation.
    @TestVisible
    private static Integer countActiveConversations(Id userId) {

        // [1] Start counting from none
        Datetime currentTime = System.now();
        Integer activeConversations = 0;

        // [2] Count each Active conversation that is inside its agent's idle timeout, or whose agent has no timeout
        for (AIConversation__c conversation : [SELECT CreatedDate, LastMessageTimestamp__c, AIAgent__r.IdleTimeoutMinutes__c FROM AIConversation__c WHERE OwnerId = :userId AND Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE WITH SYSTEM_MODE ORDER BY LastModifiedDate DESC LIMIT :AIAssistApplicationConstants.MAX_ACTIVE_CONVERSATIONS_COUNTED]) {

            Datetime lastActivity = conversation.LastMessageTimestamp__c == null ? conversation.CreatedDate : conversation.LastMessageTimestamp__c;

            if (conversation.AIAgent__r?.IdleTimeoutMinutes__c == null || lastActivity.addMinutes(Integer.valueOf(conversation.AIAgent__r.IdleTimeoutMinutes__c)) > currentTime) activeConversations++;
        }

        // [3] Return the count
        return activeConversations;
    }
}
