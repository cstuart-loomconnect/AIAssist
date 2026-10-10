/*
Script Name: 04-activity.apex

=================================================================
=================================================================

Description: What using the agents leaves behind: conversations with messages, execution steps and masking
evidence, PII mappings, feedback, a terms acknowledgment
and platform logs. Run 02-agents.apex and 03-tools-and-rules.apex first.

Skipped when a sample agent already has a conversation.

It writes through AIMessagingDataService, as the package does, for what a user may not write (the
assistant's messages, evidence), so it does not run where AI Assist is installed as a
managed package.

Part of the sample data set: run scripts/load-sample-data.sh <org alias> to load all five parts in
order, or this part alone with sf apex run --file.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public class SampleDataLoader {
  // =============================================================
  // Options
  // =============================================================

  Boolean isProductionAllowed = false; // The script refuses to run outside a sandbox or scratch org unless this is set.
  Integer conversationsPerAgent = 8;

  // =============================================================

  final String PREFIX = 'Sample - ';
  List<String> summary = new List<String>();
  List<String> problems = new List<String>();
  Id runningUserId = UserInfo.getUserId();

  public void run() {
    if (
      !isProductionAllowed &&
      ![SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox
    )
      problems.add('Not a sandbox or scratch org. Nothing was loaded.');
    else
      load();

    System.debug(
      LoggingLevel.ERROR,
      'SAMPLE DATA: 04-activity.apex\n  ' +
        String.join(summary, '\n  ') +
        (problems.isEmpty()
          ? '\nNo problems.'
          : '\nPROBLEMS (' +
            problems.size() +
            ')\n  ' +
            String.join(problems, '\n  '))
    );
  }

  void load() {
    if (
      [
        SELECT COUNT()
        FROM AIConversation__c
        WHERE AIAgent__r.Name LIKE 'Sample - %'
      ] > 0
    ) {
      summary.add('Skipped: the sample agents already have conversations');
      return;
    }

    // ---------- Users: the running user, and up to four others who can use AI Assist.
    List<Id> userIds = new List<Id>{ runningUserId };
    for (PermissionSetAssignment assignment : [
      SELECT AssigneeId
      FROM PermissionSetAssignment
      WHERE
        PermissionSet.Name = 'AIAssistUser'
        AND Assignee.IsActive = TRUE
        AND AssigneeId != :runningUserId
      LIMIT 4
    ])
      userIds.add(assignment.AssigneeId);


    // ---------- Accounts, for conversations opened from a record.
    List<Account> accounts = [SELECT Id, Name FROM Account LIMIT 3];
    if (accounts.isEmpty()) {
      accounts = new List<Account>{
        new Account(Name = PREFIX + 'Northwind Traders'),
        new Account(Name = PREFIX + 'Harbour Logistics'),
        new Account(Name = PREFIX + 'Brightwater Health')
      };
      save('Account', accounts, false);
    }


    // ---------- What the earlier scripts made.
    List<AIAgent__c> chatAgents = [
      SELECT Id, Name, AIModelConfiguration__c
      FROM AIAgent__c
      WHERE Name LIKE 'Sample - %' AND AIModelConfiguration__c != NULL
      ORDER BY Name
    ];
    if (chatAgents.isEmpty()) {
      problems.add('No sample agents: run 02-agents.apex first.');
      return;
    }
    List<AIModelConfiguration__c> models = [
      SELECT Id, AIProvider__c, ModelIdentifier__c
      FROM AIModelConfiguration__c
      WHERE Name LIKE 'Sample - %'
    ];
    Map<Id, Id> templateIdByAgentId = new Map<Id, Id>();
    for (AIPromptTemplate__c template : [
      SELECT Id, AIAgent__c
      FROM AIPromptTemplate__c
      WHERE AIAgent__c IN :chatAgents AND IsActive__c = TRUE
    ])
      templateIdByAgentId.put(template.AIAgent__c, template.Id);
    Map<Id, Id> dataSourceIdByAgentId = new Map<Id, Id>();
    for (AIAgentDataSource__c agentDataSource : [
      SELECT AIAgent__c, AIDataSource__c
      FROM AIAgentDataSource__c
      WHERE AIAgent__c IN :chatAgents
      ORDER BY Name DESC
    ])
      dataSourceIdByAgentId.put(
        agentDataSource.AIAgent__c,
        agentDataSource.AIDataSource__c
      );
    List<AIWorkflowAction__c> actions = [
      SELECT Id
      FROM AIWorkflowAction__c
      WHERE ActionName__c LIKE 'Sample - %'
      ORDER BY Name
      LIMIT 1
    ];
    Id firstActionId = actions.isEmpty() ? null : actions[0].Id;

    // ---------- Conversations.
    List<String> channels = new List<String>{
      'Utility Bar',
      'Record Page Chat',
      'Mobile'
    };
    List<AIConversation__c> conversations = new List<AIConversation__c>();
    for (AIAgent__c agent : chatAgents) {
      for (
        Integer conversationIndex = 0;
        conversationIndex < conversationsPerAgent;
        conversationIndex++
      ) {
        String channel = channels[Math.mod(conversationIndex, channels.size())];
        AIConversation__c conversation = new AIConversation__c(
          AIAgent__c = agent.Id,
          AIPromptTemplate__c = templateIdByAgentId.get(agent.Id),
          Channel__c = channel,
          Status__c = 'Active',
          OwnerId = userIds[Math.mod(conversationIndex, userIds.size())]
        );
        if (channel == 'Record Page Chat' && accounts[0].Id != null) {
          conversation.RelatedObjectAPIName__c = 'Account';
          conversation.RelatedRecordId__c = accounts[
              Math.mod(conversationIndex, accounts.size())
            ]
            .Id;
        }
        conversations.add(conversation);
      }
    }
    save('AIConversation__c', conversations, false);

    // ---------- Messages. Each turn is a user message and, when it completed, the agent's reply; a failed turn has a System message instead.
    List<String> questions = new List<String>{
      'Summarise this account for me.',
      'What are the open opportunities and their next steps?',
      'Draft a short follow-up email to the main contact.',
      'Which cases are still open, and how old are they?',
      'Who should I speak to about renewals?',
      'What changed here in the last week?'
    };
    List<String> answers = new List<String>{
      'Here is a summary:\n- Industry: Logistics\n- Two open opportunities worth 84,000 in total\n- One open case, raised four days ago\n- Main contact: Alex Morgan (Operations Director)',
      'There are two open opportunities:\n1. Fleet renewal, Negotiation, closes at the end of the month. Next step: send the revised quote.\n2. Tracking add-on, Qualification. Next step: book a demo.',
      'Subject: Following up on our call\n\nHi Alex,\n\nThanks for your time today. As agreed, I will send the revised quote by Friday. Let me know if anything else would help.\n\nBest regards',
      'One case is still open: "Portal login fails for new users", High priority, opened four days ago. Nothing has been logged on it since Tuesday.',
      'Jamie Carter is the Procurement Manager and was the contact on the last renewal.',
      'In the last week the fleet renewal moved to Negotiation and a new contact, Sam Patel, was added.'
    };
    List<String> failureReasons = new List<String>{
      'Provider Error',
      'Timeout',
      'Rate Limited',
      'Limit Reached',
      'Request Blocked'
    };
    Map<Id, AIAgent__c> agentById = new Map<Id, AIAgent__c>(chatAgents);
    Map<Id, AIModelConfiguration__c> modelById = new Map<Id, AIModelConfiguration__c>();
    for (AIModelConfiguration__c model : models) {
      if (model.Id != null)
        modelById.put(model.Id, model);
    }

    List<AIConversationMessage__c> userMessages = new List<AIConversationMessage__c>();
    List<Integer> conversationIndexByTurn = new List<Integer>();
    for (
      Integer conversationIndex = 0;
      conversationIndex < conversations.size();
      conversationIndex++
    ) {
      AIConversation__c conversation = conversations[conversationIndex];
      if (conversation.Id == null)
        continue;
      Integer turns = 2 + Math.mod(conversationIndex, 3);
      for (Integer turnIndex = 0; turnIndex < turns; turnIndex++) {
        Boolean isLastTurn = turnIndex == turns - 1;
        String status = isLastTurn && Math.mod(conversationIndex, 6) == 4
          ? 'Failed'
          : isLastTurn && Math.mod(conversationIndex, 12) == 6
              ? 'Queued'
              : 'Complete';
        AIConversationMessage__c userMessage = new AIConversationMessage__c(
          AIConversation__c = conversation.Id,
          Sender__c = 'User',
          MessageBody__c = questions[
            Math.mod(conversationIndex + turnIndex, questions.size())
          ],
          ProcessingStatus__c = status,
          IsAwaitingCapacity__c = status == 'Queued',
          AIPromptTemplate__c = conversation.AIPromptTemplate__c
        );
        if (status == 'Failed')
          userMessage.FailureReason__c = failureReasons[
            Math.mod(conversationIndex, failureReasons.size())
          ];
        userMessages.add(userMessage);
        conversationIndexByTurn.add(conversationIndex);
      }
    }
    save('AIConversationMessage__c (user)', userMessages, true);

    List<AIConversationMessage__c> replies = new List<AIConversationMessage__c>();
    List<AIExecutionStep__c> steps = new List<AIExecutionStep__c>();
    for (Integer turnIndex = 0; turnIndex < userMessages.size(); turnIndex++) {
      AIConversationMessage__c userMessage = userMessages[turnIndex];
      if (
        userMessage.Id == null ||
        userMessage.ProcessingStatus__c == 'Queued'
      )
        continue;
      Integer conversationIndex = conversationIndexByTurn[turnIndex];
      AIAgent__c agent = agentById.get(
        conversations[conversationIndex].AIAgent__c
      );
      AIModelConfiguration__c model = modelById.get(
        agent.AIModelConfiguration__c
      );
      Boolean isFailed = userMessage.ProcessingStatus__c == 'Failed';
      Integer inputTokens = 600 + Math.mod(turnIndex * 137, 900);
      Integer outputTokens = 120 + Math.mod(turnIndex * 53, 300);

      AIConversationMessage__c reply = new AIConversationMessage__c(
        AIConversation__c = userMessage.AIConversation__c,
        InReplyTo__c = userMessage.Id,
        AIPromptTemplate__c = userMessage.AIPromptTemplate__c,
        AIModelConfiguration__c = model?.Id,
        ProcessingStatus__c = userMessage.ProcessingStatus__c
      );
      if (isFailed) {
        reply.Sender__c = 'System';
        reply.MessageBody__c = 'Sorry, the assistant could not answer that. Please try again.';
        reply.FailureReason__c = userMessage.FailureReason__c;
      } else {
        reply.Sender__c = 'AI Agent';
        reply.MessageBody__c = answers[
          Math.mod(conversationIndex + turnIndex, answers.size())
        ];
        reply.InputTokenCount__c = inputTokens;
        reply.OutputTokenCount__c = outputTokens;
        reply.TokenCount__c = inputTokens + outputTokens;
        reply.LatencyMilliseconds__c = 900 + Math.mod(turnIndex * 211, 4000);
        reply.PromptTemplateVersion__c = 1;
        reply.IsSuperseded__c = Math.mod(turnIndex, 17) == 5;
        if (Math.mod(turnIndex, 7) == 2)
          reply.SuggestedWorkflowAction__c = firstActionId;
      }
      replies.add(reply);

      // The evidence of the turn, on the user message that started it.
      Id dataSourceId = dataSourceIdByAgentId.get(agent.Id);
      Integer stepOrder = 1;
      steps.add(
        new AIExecutionStep__c(
          AIConversationMessage__c = userMessage.Id,
          StepType__c = 'Template Match',
          Status__c = 'Success',
          StepOrder__c = stepOrder++,
          DurationMilliseconds__c = 12,
          StepDetail__c = 'Matched the agent\'s active prompt template.'
        )
      );
      if (dataSourceId != null)
        steps.add(
          new AIExecutionStep__c(
            AIConversationMessage__c = userMessage.Id,
            AIDataSource__c = dataSourceId,
            StepType__c = 'Data Source',
            Status__c = 'Success',
            StepOrder__c = stepOrder++,
            DurationMilliseconds__c = 85 + Math.mod(turnIndex * 31, 200),
            TargetObject__c = 'Account',
            TargetRecordId__c = conversations[conversationIndex]
              .RelatedRecordId__c,
            ObjectsSent__c = 'Account, Contact',
            FieldsSent__c = 'Account.Name, Account.Industry, Account.Phone, Contact.Name, Contact.Email, Contact.Phone',
            FieldsSentCount__c = 6,
            RecordsSentCount__c = 1 + Math.mod(turnIndex, 5),
            PIIMaskingApplied__c = true,
            SentPreviewText__c = 'Account: Harbour Logistics; Contact: Jamie Carter, jamie.carter@example.com'
          )
        );
      steps.add(
        new AIExecutionStep__c(
          AIConversationMessage__c = userMessage.Id,
          StepType__c = 'Prompt Assembly',
          Status__c = 'Success',
          StepOrder__c = stepOrder++,
          DurationMilliseconds__c = 30,
          StepDetail__c = 'System context, tone, exclusion rules and conversation history.'
        )
      );
      steps.add(
        new AIExecutionStep__c(
          AIConversationMessage__c = userMessage.Id,
          StepType__c = 'Provider Call',
          Status__c = isFailed ? 'Failed' : 'Success',
          StepOrder__c = stepOrder++,
          AttemptNumber__c = isFailed ? 3 : 1,
          DurationMilliseconds__c = 800 + Math.mod(turnIndex * 211, 4000),
          Provider__c = model == null ? 'Anthropic' : model.AIProvider__c,
          ModelIdentifier__c = model == null
            ? 'claude-sonnet-5-5'
            : model.ModelIdentifier__c,
          ToolCallingIterationsUsed__c = 1 + Math.mod(turnIndex, 3),
          ToolCallingIterationsMax__c = 5,
          RequestJson__c = '{"model":"sample","max_tokens":2048,"messages":[{"role":"user","content":"(masked)"}]}',
          ResponseJson__c = isFailed
            ? '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}'
            : '{"stop_reason":"end_turn","usage":{"input_tokens":' +
              inputTokens +
              ',"output_tokens":' +
              outputTokens +
              '}}',
          StepDetail__c = isFailed
            ? 'The provider did not answer: ' + userMessage.FailureReason__c
            : null
        )
      );
      if (firstActionId != null && Math.mod(turnIndex, 7) == 2 && !isFailed)
        steps.add(
          new AIExecutionStep__c(
            AIConversationMessage__c = userMessage.Id,
            AIWorkflowAction__c = firstActionId,
            StepType__c = 'Workflow Action',
            Status__c = 'Success',
            StepOrder__c = stepOrder++,
            DurationMilliseconds__c = 140,
            RequiredConfirmation__c = true,
            ConfirmedBy__c = conversations[conversationIndex].OwnerId,
            ConfirmedDate__c = Datetime.now(),
            TargetObject__c = 'Task',
            StepDetail__c = 'The user confirmed and the action ran.'
          )
        );
    }
    save('AIConversationMessage__c (replies)', replies, true);
    save('AIExecutionStep__c', steps, true);

    // ---------- Masking evidence under each data source step.
    List<AIPIIMaskingRecord__c> maskingRecords = new List<AIPIIMaskingRecord__c>();
    Integer maskingIndex = 0;
    for (AIExecutionStep__c step : steps) {
      if (step.Id == null || step.PIIMaskingApplied__c != true)
        continue;
      maskingIndex++;
      maskingRecords.add(
        new AIPIIMaskingRecord__c(
          AIExecutionStep__c = step.Id,
          SourceObject__c = 'Contact',
          SourceField__c = 'Email',
          PIIFieldType__c = 'Email',
          ComplianceGroup__c = 'GDPR',
          MaskingStrategy__c = 'SubstituteFromList',
          ValuesMasked__c = 1 + Math.mod(maskingIndex, 4),
          Outcome__c = 'Masked'
        )
      );
      maskingRecords.add(
        new AIPIIMaskingRecord__c(
          AIExecutionStep__c = step.Id,
          SourceObject__c = 'Contact',
          SourceField__c = 'Phone',
          PIIFieldType__c = 'Phone',
          ComplianceGroup__c = 'PII',
          MaskingStrategy__c = 'RandomizeByPattern',
          ValuesMasked__c = Math.mod(maskingIndex, 5) == 0 ? 0 : 1,
          Outcome__c = Math.mod(maskingIndex, 9) == 0
            ? 'Failed'
            : Math.mod(maskingIndex, 5) == 0 ? 'Skipped' : 'Masked'
        )
      );
    }
    save('AIPIIMaskingRecord__c', maskingRecords, true);

    // ---------- The real-to-fake value map of every third conversation. No permission set grants this object, so it is built by name.
    List<SObject> mappings = new List<SObject>();
    for (
      Integer conversationIndex = 0;
      conversationIndex < conversations.size();
      conversationIndex += 3
    ) {
      if (conversations[conversationIndex].Id == null)
        continue;
      SObject mapping = (SObject) Type.forName('AIPIIMapping__c').newInstance();
      mapping.put('Name', 'Sample mapping ' + (conversationIndex + 1));
      mapping.put('AIConversation__c', conversations[conversationIndex].Id);
      mapping.put(
        'MappingJson__c',
        JSON.serialize(
          new Map<String, String>{
            'alex.morgan@harbourlogistics.example' => 'jamie.carter@example.com',
            'Alex Morgan' => 'Jamie Carter',
            '020 7946 0321' => '020 7946 0958'
          }
        )
      );
      mappings.add(mapping);
    }
    save('AIPIIMapping__c', mappings, true);

    // ---------- Feedback on every fourth reply.
    List<String> feedbackReasons = new List<String>{
      'Inaccurate',
      'Incomplete',
      'Not Relevant',
      'Too Slow',
      'Unsafe Or Inappropriate',
      'Other'
    };
    List<AIFeedback__c> feedback = new List<AIFeedback__c>();
    for (
      Integer replyIndex = 0; replyIndex < replies.size(); replyIndex += 4
    ) {
      AIConversationMessage__c reply = replies[replyIndex];
      if (reply.Id == null || reply.Sender__c != 'AI Agent')
        continue;
      Boolean isHelpful = Math.mod(replyIndex, 12) != 8;
      feedback.add(
        new AIFeedback__c(
          AIConversation__c = reply.AIConversation__c,
          AIConversationMessage__c = reply.Id,
          Rating__c = isHelpful ? 'Helpful' : 'Not Helpful',
          Reason__c = isHelpful
            ? null
            : feedbackReasons[Math.mod(replyIndex, feedbackReasons.size())],
          Comment__c = isHelpful
            ? 'Exactly what I needed.'
            : 'The answer missed the open case.'
        )
      );
    }
    save('AIFeedback__c', feedback, false);

    // ---------- Terms: an acknowledgment can only be the running user's own.
    save(
      'AITermsAcknowledgment__c',
      new List<AITermsAcknowledgment__c>{
        new AITermsAcknowledgment__c(
          User__c = runningUserId,
          TermsVersion__c = '1.0',
          SignatureText__c = UserInfo.getName(),
          AcknowledgedDate__c = Datetime.now()
        )
      },
      false
    );

    // ---------- Platform logs.
    List<AIPlatformLog__c> logs = new List<AIPlatformLog__c>();
    List<List<String>> logRows = new List<List<String>>{
      new List<String>{ 'Error', 'AIMessageProcessingQueueable', 'execute', 'System.CalloutException', 'Read timed out' },
      new List<String>{ 'Error', 'AIDataSourceDispatcher', 'run', 'System.QueryException', 'No such column \'Segment__c\' on entity \'Account\'' },
      new List<String>{ 'Warning', 'AIPiiPseudonymizationService', 'pseudonymize', null, 'No masking rule for field type Other; a generic value was used.' },
      new List<String>{ 'Info', 'AIMaintenanceScheduler', 'execute', null, 'Housekeeping finished: 14 conversations closed as idle.' },
      new List<String>{ 'Info', 'AIPiiRegistrySyncWorker', 'execute', null, 'Contact registry synced: 9 fields, 7 PII.' }
    };
    for (Integer logIndex = 0; logIndex < logRows.size(); logIndex++) {
      List<String> logRow = logRows[logIndex];
      logs.add(
        new AIPlatformLog__c(
          Severity__c = logRow[0],
          ClassName__c = logRow[1],
          MethodName__c = logRow[2],
          ExceptionType__c = logRow[3],
          ExceptionMessage__c = logRow[4],
          ExceptionLogDetail__c = 'Sample log entry created by 04-activity.apex.',
          StackTrace__c = logRow[3] == null
            ? null
            : 'Class.' + logRow[1] + '.' + logRow[2] + ': line 42, column 1',
          OccurredAt__c = Datetime.now().addHours(-logIndex * 5),
          User__c = runningUserId,
          RelatedRecordId__c = conversations.isEmpty()
            ? null
            : conversations[0].Id
        )
      );
    }
    save('AIPlatformLog__c', logs, true);

    // ---------- Last, so the messages above could be added while every conversation was open: close some, and put one per agent on legal hold.
    List<String> closeReasons = new List<String>{
      'User Closed',
      'Idle Timeout',
      'Message Limit Reached',
      'Token Limit Reached',
      'System Override'
    };
    List<AIConversation__c> conversationChanges = new List<AIConversation__c>();
    for (
      Integer conversationIndex = 0;
      conversationIndex < conversations.size();
      conversationIndex++
    ) {
      if (conversations[conversationIndex].Id == null)
        continue;
      Integer position = Math.mod(conversationIndex, conversationsPerAgent);
      if (position != 1 && Math.mod(position, 4) != 3 && position != 5)
        continue;
      AIConversation__c change = new AIConversation__c(
        Id = conversations[conversationIndex].Id
      );
      if (position == 1) {
        change.IsOnLegalHold__c = true;
      } else {
        change.Status__c = 'Closed';
        change.ConversationCloseReason__c = closeReasons[
          Math.mod(conversationIndex, closeReasons.size())
        ];
        change.ConversationClosedTimestamp__c = Datetime.now();
      }
      conversationChanges.add(change);
    }
    try {
      AIMessagingDataService.updateAsPackage(conversationChanges);
      summary.add(
        'AIConversation__c closed or on legal hold: ' +
        conversationChanges.size()
      );
    } catch (Exception caughtException) {
      problems.add('AIConversation__c update: ' + caughtException.getMessage());
    }
  }

  // Inserts what it can and records the rest. asPackage writes in system mode, as the package does, for the objects and fields a user may not write (the assistant's messages, evidence).
  void save(String label, List<SObject> records, Boolean asPackage) {
    if (records.isEmpty())
      return;

    if (asPackage) {
      try {
        AIMessagingDataService.insertAsPackage(records);
      } catch (Exception caughtException) {
        problems.add(label + ': ' + caughtException.getMessage());
      }
    } else {
      List<Database.SaveResult> saveResults = Database.insert(records, false);
      for (Integer rowIndex = 0; rowIndex < saveResults.size(); rowIndex++) {
        if (!saveResults[rowIndex].isSuccess())
          problems.add(
            label +
              ' [' +
              rowIndex +
              ']: ' +
              saveResults[rowIndex].getErrors()[0].getMessage()
          );
      }
    }

    Integer savedCount = 0;
    for (SObject record : records) {
      if (record.Id != null)
        savedCount++;
    }
    summary.add(label + ': ' + savedCount + ' of ' + records.size());
  }
}

new SampleDataLoader().run();
