/*
Class Name: AIChatConversationService

=================================================================
=================================================================

Description: Loading, paging, listing, resuming and exporting the signed-in user's conversations, and the two
ownership checks every conversation or message Id goes through first.

Queries run in system mode because the User permission set cannot read execution steps or data source
names (the Sources chips), but every query is limited to conversations the signed-in user owns, so no
other user's conversation can be reached. Messages from the System sender (the record of a failed turn)
are never shown. Replies show the real values behind the fake ones masking sent to the model; the
restored text is built for display and export and is never saved.

Writes (resuming) go through the package gateway after the checks here.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from the old conversation service. One parameterised message query instead of four, ownership in every query, resume checks the concurrent limit, and step labels are Custom Labels.
2.0          Chandler Stuart          getSharedConversationHistory lists conversations other users started that the viewer may read; buildConversationView no longer filters on the owner, its callers check access.
*/

public with sharing class AIChatConversationService {
  private static final String MESSAGE_FIELDS =
    'Id, AIConversation__c, Sender__c, MessageBody__c, TokenCount__c, ProcessingStatus__c, SuggestedWorkflowAction__c, CreatedDate, ' +
    '(SELECT StepOrder__c, Status__c, StepType__c, StepDetail__c, DurationMilliseconds__c, AIDataSource__c, AIDataSource__r.DeveloperName__c, AIWorkflowAction__c, AIWorkflowAction__r.ActionName__c FROM AIExecutionSteps__r ORDER BY StepOrder__c), ' +
    '(SELECT Rating__c FROM AIFeedbacks__r WHERE CreatedById = :userId ORDER BY CreatedDate DESC LIMIT 1)';

  private static final String CONVERSATION_FIELDS =
    'Id, Name, Status__c, ConversationCloseReason__c, AIAgent__c, AIAgent__r.Name, AIAgent__r.IsActive__c, AIAgent__r.AllowConversationResume__c, MessageCount__c, RelatedRecordId__c, RelatedObjectAPIName__c, ProcessingLockedUntil__c, LastModifiedDate, ' +
    '(SELECT MessageBody__c FROM AIConversationMessages__r WHERE Sender__c = :userSender ORDER BY CreatedDate ASC LIMIT 1)';

  // Throws unless the signed-in user owns the conversation; the same answer for one that does not exist.
  public static AIConversation__c assertOwnsConversation(Id conversationId) {
    if (
      conversationId == null ||
      conversationId.getSobjectType() != AIConversation__c.SObjectType
    )
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
        Label.AI_Error_Conversation_Not_Found
      );

    List<AIConversation__c> conversations = [
      SELECT
        Id,
        Status__c,
        AIAgent__c,
        ProcessingLockedUntil__c,
        RelatedRecordId__c
      FROM AIConversation__c
      WHERE Id = :conversationId AND OwnerId = :UserInfo.getUserId()
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (conversations.isEmpty())
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
        Label.AI_Error_Conversation_Not_Found
      );

    return conversations[0];
  }

  // Throws unless messageId is an AI Agent reply in a conversation the signed-in user owns.
  public static AIConversationMessage__c assertOwnsAgentMessage(Id messageId) {
    if (
      messageId == null ||
      messageId.getSobjectType() != AIConversationMessage__c.SObjectType
    )
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
        Label.AI_Error_Conversation_Not_Found
      );

    List<AIConversationMessage__c> messages = [
      SELECT
        Id,
        AIConversation__c,
        AIConversation__r.Name,
        AIConversation__r.PublicId__c,
        AIConversation__r.RelatedRecordId__c,
        AIConversation__r.AIAgent__c,
        Sender__c,
        TokenCount__c,
        SuggestedWorkflowAction__c,
        CreatedDate
      FROM AIConversationMessage__c
      WHERE
        Id = :messageId
        AND AIConversation__r.OwnerId = :UserInfo.getUserId()
        AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (messages.isEmpty())
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
        Label.AI_Error_Conversation_Not_Found
      );

    return messages[0];
  }

  // The user's newest Active conversation with this agent about this record (or about no record).
  public static AIConversation__c findActiveConversation(
    Id agentId,
    Id recordId
  ) {
    String relatedRecordId = recordId == null ? null : String.valueOf(recordId);
    String userSender = AIAssistApplicationConstants.SENDER_USER;
    Id userId = UserInfo.getUserId();

    List<AIConversation__c> conversations = Database.queryWithBinds(
      'SELECT ' +
        CONVERSATION_FIELDS +
        ' FROM AIConversation__c WHERE OwnerId = :userId AND AIAgent__c = :agentId AND RelatedRecordId__c = :relatedRecordId AND Status__c = :activeStatus ORDER BY LastModifiedDate DESC LIMIT 1',
      new Map<String, Object>{
        'userId' => userId,
        'agentId' => agentId,
        'relatedRecordId' => relatedRecordId,
        'activeStatus' => AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
        'userSender' => userSender
      },
      AccessLevel.SYSTEM_MODE
    );

    return conversations.isEmpty() ? null : conversations[0];
  }

  // Reopens a Closed conversation, only when its agent is active and allows resuming, and only if the user is under their concurrent limit.
  public static void resumeConversation(Id conversationId) {
    AIConversation__c conversation = assertOwnsConversation(conversationId);
    List<AIAgent__c> conversationAgents = [
      SELECT Id, IsActive__c, AllowConversationResume__c, RetentionTrigger__c
      FROM AIAgent__c
      WHERE Id = :conversation.AIAgent__c
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    Boolean canResume =
      !conversationAgents.isEmpty() &&
      conversationAgents[0].IsActive__c == true &&
      conversationAgents[0].AllowConversationResume__c == true &&
      conversation.Status__c ==
      AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
    if (!canResume)
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_CONVERSATION_CLOSED,
        Label.AI_Error_Conversation_Closed
      );

    AIUserSettings__c userSettings = AIChatStateService.getUserSettings();
    if (
      userSettings != null &&
      userSettings.IsActive__c == true &&
      userSettings.MaxConcurrentConversations__c != null &&
      AIMessagingSelector.countActiveConversations(UserInfo.getUserId()) >=
      userSettings.MaxConcurrentConversations__c
    ) {
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_CONCURRENT_LIMIT,
        Label.AI_Error_Concurrent_Limit
      );
    }

    AIConversation__c reopened = new AIConversation__c(
      Id = conversationId,
      Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
      ConversationCloseReason__c = null,
      ConversationClosedTimestamp__c = null
    );

    // A retention that counted from closing no longer applies; it is worked out again when the conversation next closes.
    if (
      conversationAgents[0].RetentionTrigger__c ==
      AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE
    )
      reopened.RetentionExpiryDate__c = null;

    AIMessagingDataService.updateAsPackage(new List<SObject>{ reopened });
  }

  // The history panel's list: the user's own conversations, newest activity first. onlyThisRecord narrows it to recordId.
  public static List<AIChatDataStructure.ConversationSummary> getConversationHistory(
    String recordId,
    Boolean onlyThisRecord
  ) {
    Id userId = UserInfo.getUserId();
    Id typedRecordId = AIChatDataStructure.toIdOrNull(recordId);
    String userSender = AIAssistApplicationConstants.SENDER_USER;
    Boolean filterByRecord = onlyThisRecord == true && typedRecordId != null;

    List<AIConversation__c> conversations = Database.queryWithBinds(
      'SELECT ' +
        CONVERSATION_FIELDS +
        ' FROM AIConversation__c WHERE OwnerId = :userId' +
        (filterByRecord ? ' AND RelatedRecordId__c = :relatedRecordId' : '') +
        ' ORDER BY LastModifiedDate DESC LIMIT :maxRows',
      new Map<String, Object>{
        'userId' => userId,
        'relatedRecordId' => typedRecordId == null
          ? null
          : String.valueOf(typedRecordId),
        'userSender' => userSender,
        'maxRows' => AIAssistApplicationConstants.CHAT_HISTORY_MAX_CONVERSATIONS
      },
      AccessLevel.SYSTEM_MODE
    );

    List<AIChatDataStructure.ConversationSummary> summaries = new List<AIChatDataStructure.ConversationSummary>();
    for (AIConversation__c conversation : conversations)
      summaries.add(toConversationSummary(conversation));

    return summaries;
  }

  // Conversations other people started that the user may read (see AIConversationVisibilityService), newest activity first. Read-only: none of them can be sent to, closed, resumed, exported or acted on.
  public static List<AIChatDataStructure.ConversationSummary> getSharedConversationHistory() {
    Id viewerId = UserInfo.getUserId();
    List<AIChatDataStructure.ConversationSummary> summaries = new List<AIChatDataStructure.ConversationSummary>();

    for (
      AIConversation__c conversation : AIConversationVisibilityService.getSharedConversations(
        viewerId,
        AIConversationVisibilityService.getEffectiveScope(
          AIChatStateService.getUserSettings()
        ),
        CONVERSATION_FIELDS,
        new Map<String, Object>{
          'userSender' => AIAssistApplicationConstants.SENDER_USER
        },
        AIAssistApplicationConstants.CHAT_HISTORY_MAX_CONVERSATIONS
      )
    ) {
      AIChatDataStructure.ConversationSummary summary = toConversationSummary(
        conversation
      );
      summary.ownerName = conversation.Owner.Name;
      summaries.add(summary);
    }

    return summaries;
  }

  // A plain-text transcript, with the real values restored. Command instructions and System messages are left out. The caller has checked the user may export.
  public static String exportConversation(Id conversationId) {
    AIConversation__c conversation = [
      SELECT Name, AIAgent__r.Name
      FROM AIConversation__c
      WHERE Id = :conversationId AND OwnerId = :UserInfo.getUserId()
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    String agentName = conversation.AIAgent__r == null
      ? Label.AI_Chat_Title
      : conversation.AIAgent__r.Name;

    List<String> lines = new List<String>{
      conversation.Name +
      ' - ' +
      agentName,
      System.now().format(),
      ''
    };
    Map<String, String> realValueByFakeValue = AIChatDebugService.getRealValueByFakeValue(
      conversationId
    );

    for (AIConversationMessage__c message : [
      SELECT Sender__c, MessageBody__c, CreatedDate
      FROM AIConversationMessage__c
      WHERE
        AIConversation__c = :conversationId
        AND Sender__c != :AIAssistApplicationConstants.SENDER_SYSTEM
      WITH SYSTEM_MODE
      ORDER BY CreatedDate ASC, Id ASC
    ]) {
      String displayText = AIChatCommandService.getDisplayText(
        message.MessageBody__c
      );
      lines.add(
        '[' +
          message.CreatedDate.format() +
          '] ' +
          (message.Sender__c == AIAssistApplicationConstants.SENDER_USER
            ? UserInfo.getName()
            : agentName) +
          ':'
      );
      lines.add(
        message.Sender__c == AIAssistApplicationConstants.SENDER_AI_AGENT
          ? AIChatDebugService.restorePii(displayText, realValueByFakeValue)
          : displayText
      );
      lines.add('');
    }

    return String.join(lines, '\n');
  }

  // The caller has already checked the user may read the conversation: assertOwnsConversation for their own, AIConversationVisibilityService.assertCanView when it may be someone else's.
  public static AIChatDataStructure.ConversationView buildConversationView(
    Id conversationId,
    Integer pageSize,
    AIChatDataStructure.UserState user,
    AIChatDataStructure.UiSettings ui
  ) {
    String userSender = AIAssistApplicationConstants.SENDER_USER;
    AIConversation__c conversation = (AIConversation__c) Database.queryWithBinds(
      'SELECT ' +
        CONVERSATION_FIELDS +
        ' FROM AIConversation__c WHERE Id = :conversationId LIMIT 1',
      new Map<String, Object>{
        'conversationId' => conversationId,
        'userSender' => userSender
      },
      AccessLevel.SYSTEM_MODE
    )[0];

    AIChatDataStructure.ConversationView conversationView = new AIChatDataStructure.ConversationView();
    conversationView.id = conversation.Id;
    conversationView.name = conversation.Name;
    // A conversation has no title field: it is named after its first user message.
    List<AIConversationMessage__c> firstUserMessages = conversation.AIConversationMessages__r;
    conversationView.title = firstUserMessages == null ||
      firstUserMessages.isEmpty()
      ? conversation.Name
      : AIChatCommandService.getDisplayText(firstUserMessages[0].MessageBody__c)
          .normalizeSpace()
          .abbreviate(
            AIAssistApplicationConstants.CHAT_CONVERSATION_TITLE_MAX_LENGTH
          );
    conversationView.status = conversation.Status__c;
    conversationView.closeReason = conversation.ConversationCloseReason__c;
    conversationView.agentId = conversation.AIAgent__c;
    conversationView.agentName = conversation.AIAgent__r == null
      ? null
      : conversation.AIAgent__r.Name;
    conversationView.isActive =
      conversation.Status__c ==
      AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE;
    conversationView.canResume =
      conversation.Status__c ==
      AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED &&
      conversation.AIAgent__r != null &&
      conversation.AIAgent__r.IsActive__c == true &&
      conversation.AIAgent__r.AllowConversationResume__c == true;
    conversationView.isProcessing =
      conversation.ProcessingLockedUntil__c != null &&
      conversation.ProcessingLockedUntil__c > System.now();
    conversationView.relatedRecordId = conversation.RelatedRecordId__c;
    conversationView.relatedObjectApiName = conversation.RelatedObjectAPIName__c;

    AIChatDataStructure.MessagePage messagePage = loadMessagePage(
      conversationId,
      null,
      pageSize,
      user,
      ui
    );
    conversationView.messages = messagePage.messages;
    conversationView.hasMoreMessages = messagePage.hasMore;

    return conversationView;
  }

  // One page of displayable messages, oldest first. Queried newest first with one extra row, to learn whether there are more.
  public static AIChatDataStructure.MessagePage loadMessagePage(
    Id conversationId,
    Id beforeMessageId,
    Integer pageSize,
    AIChatDataStructure.UserState user,
    AIChatDataStructure.UiSettings ui
  ) {
    // Same-instant messages are split by Id, so the boundary message's own date is read first.
    List<AIConversationMessage__c> boundaryMessages = beforeMessageId == null
      ? new List<AIConversationMessage__c>()
      : [
          SELECT CreatedDate
          FROM AIConversationMessage__c
          WHERE Id = :beforeMessageId AND AIConversation__c = :conversationId
          WITH SYSTEM_MODE
          LIMIT 1
        ];
    Datetime boundaryDate = boundaryMessages.isEmpty()
      ? null
      : boundaryMessages[0].CreatedDate;
    String boundaryFilter = boundaryMessages.isEmpty()
      ? ''
      : ' AND (CreatedDate < :boundaryDate OR (CreatedDate = :boundaryDate AND Id < :boundaryId))';

    List<AIConversationMessage__c> newestFirst = (List<AIConversationMessage__c>) Database.queryWithBinds(
      'SELECT ' +
        MESSAGE_FIELDS +
        ' FROM AIConversationMessage__c WHERE AIConversation__c = :conversationId AND Sender__c IN :visibleSenders' +
        boundaryFilter +
        ' ORDER BY CreatedDate DESC, Id DESC LIMIT :maxRows',
      new Map<String, Object>{
        'conversationId' => conversationId,
        'visibleSenders' => new Set<String>{
          AIAssistApplicationConstants.SENDER_USER,
          AIAssistApplicationConstants.SENDER_AI_AGENT
        },
        'boundaryDate' => boundaryDate,
        'boundaryId' => beforeMessageId,
        'userId' => UserInfo.getUserId(),
        'maxRows' => pageSize + 1
      },
      AccessLevel.SYSTEM_MODE
    );

    AIChatDataStructure.MessagePage messagePage = new AIChatDataStructure.MessagePage();

    messagePage.hasMore = newestFirst.size() > pageSize;
    if (messagePage.hasMore)
      newestFirst.remove(newestFirst.size() - 1);

    List<AIConversationMessage__c> oldestFirst = new List<AIConversationMessage__c>();
    for (Integer index = newestFirst.size() - 1; index >= 0; index--)
      oldestFirst.add(newestFirst[index]);

    // Resolves every suggested Workflow Action on the page in one query, then maps each message.
    Map<Id, AIWorkflowAction__c> actionsById = new Map<Id, AIWorkflowAction__c>();

    if (ui.inlineActionsEnabled && user.workflowActionsEnabled) {
      Set<Id> actionIds = new Set<Id>();
      for (AIConversationMessage__c message : oldestFirst) {
        if (message.SuggestedWorkflowAction__c != null)
          actionIds.add(message.SuggestedWorkflowAction__c);
      }
      if (!actionIds.isEmpty())
        actionsById = new Map<Id, AIWorkflowAction__c>(
          [
            SELECT
              Id,
              ActionName__c,
              Description__c,
              RequiresConfirmation__c,
              ConfirmationMessage__c,
              InputSchema__c
            FROM AIWorkflowAction__c
            WHERE Id IN :actionIds AND IsActive__c = TRUE
            WITH SYSTEM_MODE
          ]
        );
    }

    List<AIChatDataStructure.ChatMessage> chatMessages = new List<AIChatDataStructure.ChatMessage>();
    Map<Id, Map<String, String>> realValueByFakeValueByConversation = new Map<Id, Map<String, String>>();

    for (AIConversationMessage__c message : oldestFirst) {
      AIChatDataStructure.ChatMessage chatMessage = toChatMessage(
        message,
        actionsById,
        message.AIExecutionSteps__r,
        message.AIFeedbacks__r
      );

      if (chatMessage.sender == 'agent') {
        if (
          !realValueByFakeValueByConversation.containsKey(
            message.AIConversation__c
          )
        )
          realValueByFakeValueByConversation.put(
            message.AIConversation__c,
            AIChatDebugService.getRealValueByFakeValue(
              message.AIConversation__c
            )
          );
        chatMessage.displayText = AIChatDebugService.restorePii(
          chatMessage.displayText,
          realValueByFakeValueByConversation.get(message.AIConversation__c)
        );
      }

      chatMessages.add(chatMessage);
    }

    messagePage.messages = chatMessages;

    return messagePage;
  }

  // Every displayable message newer than afterMessageId (all of them when blank), oldest first, up to 200.
  public static List<AIChatDataStructure.ChatMessage> loadMessagesAfter(
    Id conversationId,
    Id afterMessageId,
    AIChatDataStructure.UserState user,
    AIChatDataStructure.UiSettings ui
  ) {
    // Same-instant messages are split by Id, so the boundary message's own date is read first.
    List<AIConversationMessage__c> boundaryMessages = afterMessageId == null
      ? new List<AIConversationMessage__c>()
      : [
          SELECT CreatedDate
          FROM AIConversationMessage__c
          WHERE Id = :afterMessageId AND AIConversation__c = :conversationId
          WITH SYSTEM_MODE
          LIMIT 1
        ];
    Datetime boundaryDate = boundaryMessages.isEmpty()
      ? null
      : boundaryMessages[0].CreatedDate;
    String boundaryFilter = boundaryMessages.isEmpty()
      ? ''
      : ' AND (CreatedDate > :boundaryDate OR (CreatedDate = :boundaryDate AND Id > :boundaryId))';

    List<AIConversationMessage__c> newerMessages = (List<AIConversationMessage__c>) Database.queryWithBinds(
      'SELECT ' +
        MESSAGE_FIELDS +
        ' FROM AIConversationMessage__c WHERE AIConversation__c = :conversationId AND Sender__c IN :visibleSenders' +
        boundaryFilter +
        ' ORDER BY CreatedDate ASC, Id ASC LIMIT :maxRows',
      new Map<String, Object>{
        'conversationId' => conversationId,
        'visibleSenders' => new Set<String>{
          AIAssistApplicationConstants.SENDER_USER,
          AIAssistApplicationConstants.SENDER_AI_AGENT
        },
        'boundaryDate' => boundaryDate,
        'boundaryId' => afterMessageId,
        'userId' => UserInfo.getUserId(),
        'maxRows' => 200
      },
      AccessLevel.SYSTEM_MODE
    );

    // Resolves every suggested Workflow Action on the page in one query, then maps each message.
    Map<Id, AIWorkflowAction__c> actionsById = new Map<Id, AIWorkflowAction__c>();

    if (ui.inlineActionsEnabled && user.workflowActionsEnabled) {
      Set<Id> actionIds = new Set<Id>();
      for (AIConversationMessage__c message : newerMessages) {
        if (message.SuggestedWorkflowAction__c != null)
          actionIds.add(message.SuggestedWorkflowAction__c);
      }
      if (!actionIds.isEmpty())
        actionsById = new Map<Id, AIWorkflowAction__c>(
          [
            SELECT
              Id,
              ActionName__c,
              Description__c,
              RequiresConfirmation__c,
              ConfirmationMessage__c,
              InputSchema__c
            FROM AIWorkflowAction__c
            WHERE Id IN :actionIds AND IsActive__c = TRUE
            WITH SYSTEM_MODE
          ]
        );
    }

    List<AIChatDataStructure.ChatMessage> chatMessages = new List<AIChatDataStructure.ChatMessage>();
    Map<Id, Map<String, String>> realValueByFakeValueByConversation = new Map<Id, Map<String, String>>();

    for (AIConversationMessage__c message : newerMessages) {
      AIChatDataStructure.ChatMessage chatMessage = toChatMessage(
        message,
        actionsById,
        message.AIExecutionSteps__r,
        message.AIFeedbacks__r
      );

      if (chatMessage.sender == 'agent') {
        if (
          !realValueByFakeValueByConversation.containsKey(
            message.AIConversation__c
          )
        )
          realValueByFakeValueByConversation.put(
            message.AIConversation__c,
            AIChatDebugService.getRealValueByFakeValue(
              message.AIConversation__c
            )
          );
        chatMessage.displayText = AIChatDebugService.restorePii(
          chatMessage.displayText,
          realValueByFakeValueByConversation.get(message.AIConversation__c)
        );
      }

      chatMessages.add(chatMessage);
    }

    return chatMessages;
  }

  public static AIChatDataStructure.ChatMessage toChatMessage(
    AIConversationMessage__c message,
    Map<Id, AIWorkflowAction__c> actionsById,
    List<AIExecutionStep__c> steps,
    List<AIFeedback__c> feedback
  ) {
    AIChatDataStructure.ChatMessage chatMessage = new AIChatDataStructure.ChatMessage();
    chatMessage.id = message.Id;
    chatMessage.conversationId = message.AIConversation__c;
    chatMessage.sender = message.Sender__c ==
      AIAssistApplicationConstants.SENDER_USER
      ? 'user'
      : 'agent';
    chatMessage.displayText = AIChatCommandService.getDisplayText(
      message.MessageBody__c
    );
    chatMessage.createdDate = message.CreatedDate == null
      ? System.now()
      : message.CreatedDate;
    chatMessage.tokenCount = message.TokenCount__c;
    chatMessage.processingStatus = message.ProcessingStatus__c;

    if (
      chatMessage.sender == 'user' &&
      AIChatCommandService.isCommandText(chatMessage.displayText)
    ) {
      chatMessage.isCommand = true;
      chatMessage.commandName = AIChatCommandService.getCommandToken(
        chatMessage.displayText
      );
    }

    if (feedback != null && !feedback.isEmpty())
      chatMessage.feedbackRating = feedback[0].Rating__c;

    Set<Id> ranActionIds = new Set<Id>();
    Set<String> sourceNames = new Set<String>();

    for (
      AIExecutionStep__c step : steps == null
        ? new List<AIExecutionStep__c>()
        : steps
    ) {
      chatMessage.steps.add(toExecutionStep(step));
      if (step.AIDataSource__c != null && step.AIDataSource__r != null)
        sourceNames.add(
          AIChatDataStructure.humanise(step.AIDataSource__r.DeveloperName__c)
        );
      if (
        step.AIWorkflowAction__c != null &&
        step.Status__c ==
        AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS
      )
        ranActionIds.add(step.AIWorkflowAction__c);
    }

    chatMessage.sources.addAll(sourceNames);

    if (
      message.SuggestedWorkflowAction__c != null &&
      actionsById.containsKey(message.SuggestedWorkflowAction__c)
    ) {
      chatMessage.suggestedAction = AIChatActionService.toSuggestedAction(
        actionsById.get(message.SuggestedWorkflowAction__c)
      );
      chatMessage.suggestedAction.hasRun = ranActionIds.contains(
        message.SuggestedWorkflowAction__c
      );
    }

    return chatMessage;
  }

  // The label is a Custom Label chosen by what the step did, with the data source or action name added; the stored step detail is shown when there is one.
  public static AIChatDataStructure.ExecutionStep toExecutionStep(
    AIExecutionStep__c step
  ) {
    AIChatDataStructure.ExecutionStep executionStep = new AIChatDataStructure.ExecutionStep();
    executionStep.stepOrder = step.StepOrder__c == null
      ? null
      : step.StepOrder__c.intValue();
    executionStep.status = step.Status__c;
    executionStep.isSuccess =
      step.Status__c ==
      AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS;
    executionStep.durationMs = step.DurationMilliseconds__c == null
      ? null
      : step.DurationMilliseconds__c.longValue();

    if (String.isNotBlank(step.StepDetail__c))
      executionStep.label = step.StepDetail__c;
    else if (step.AIDataSource__r != null)
      executionStep.label =
        Label.AI_Step_Reading_Data +
        ': ' +
        AIChatDataStructure.humanise(step.AIDataSource__r.DeveloperName__c);
    else if (step.AIWorkflowAction__r != null)
      executionStep.label =
        Label.AI_Step_Running_Action +
        ': ' +
        step.AIWorkflowAction__r.ActionName__c;
    else if (
      step.StepType__c == AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL
    )
      executionStep.label = Label.AI_Step_Calling_Model;
    else if (
      step.StepType__c == AIAssistApplicationConstants.STEP_TYPE_PII_MASKING
    )
      executionStep.label = Label.AI_Step_Protecting_Data;
    else if (
      step.StepType__c == AIAssistApplicationConstants.STEP_TYPE_PROMPT_ASSEMBLY
    )
      executionStep.label = Label.AI_Step_Preparing_Request;
    else
      executionStep.label = Label.AI_Step_Finalising;

    return executionStep;
  }

  public static AIChatDataStructure.ConversationSummary toConversationSummary(
    AIConversation__c conversation
  ) {
    AIChatDataStructure.ConversationSummary summary = new AIChatDataStructure.ConversationSummary();
    summary.id = conversation.Id;
    // A conversation has no title field: it is named after its first user message.
    List<AIConversationMessage__c> firstUserMessages = conversation.AIConversationMessages__r;
    summary.title = firstUserMessages == null || firstUserMessages.isEmpty()
      ? conversation.Name
      : AIChatCommandService.getDisplayText(firstUserMessages[0].MessageBody__c)
          .normalizeSpace()
          .abbreviate(
            AIAssistApplicationConstants.CHAT_CONVERSATION_TITLE_MAX_LENGTH
          );
    summary.status = conversation.Status__c;
    summary.closeReason = conversation.ConversationCloseReason__c;
    summary.agentName = conversation.AIAgent__r == null
      ? null
      : conversation.AIAgent__r.Name;
    summary.messageCount = conversation.MessageCount__c == null
      ? 0
      : conversation.MessageCount__c.intValue();
    summary.lastActivity = conversation.LastModifiedDate;
    summary.relatedRecordId = conversation.RelatedRecordId__c;
    summary.relatedObjectApiName = conversation.RelatedObjectAPIName__c;

    return summary;
  }
}
