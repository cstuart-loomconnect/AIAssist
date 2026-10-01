/*
Class Name: AIExecutionStepRecorderTest

=================================================================
=================================================================

Description: Testing utility for AIExecutionStepRecorder: the execution evidence saved for a turn, what is kept only in debug mode, and that a bookkeeping problem never breaks the turn.

=================================================================
=================================================================
Applicable Classes:

AIExecutionStepRecorder

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIExecutionStepRecorderTest {
  // testScenario1: A provider call step is saved with the provider and model from the caller when the tracker did not name them, in order, with the attempt and tool-calling figures.
  // testScenario2: A step naming a data source is a data source step, and a failed step is saved as Failed.
  // testScenario3: A workflow action step keeps the target and who confirmed it and when, as the evidence the security model asks for.
  // testScenario4: Request and response payloads are saved only for a debug-mode user and only on the last provider call, and are cut to the field size.
  // testScenario5: Masking entries are saved under the step that sent the data, with Masked as the outcome when none was given.
  // testScenario6: Nothing is saved, and nothing throws, for no message, no trace or a trace with no steps.
  // testScenario7: A value longer than its field is cut instead of losing the evidence row.
  // testScenario8: Bulk: two hundred steps are saved in one insert, in order.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  @IsTest
  static void testScenario1() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      10,
      1,
      true
    )[0];
    AIExecutionStepTracker trace = new AIExecutionStepTracker(
      conversation.Id,
      reply.Id,
      false,
      false
    );
    AIExecutionStepTracker.StepEntry step = new AIExecutionStepTracker.StepEntry();
    step.durationMilliseconds = 250;
    step.recordsSentCount = 4;
    step.fieldsSentCount = 12;
    step.objectsSent = 'Account';
    step.fieldsSent = 'Name,Phone';
    trace.steps.add(step);
    trace.attemptNumber = 2;
    trace.toolCallingIterationsUsed = 1;
    trace.toolCallingIterationsMax = 5;

    Test.startTest();
    AIExecutionStepRecorder.recordExecutionSteps(
      reply.Id,
      trace,
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC,
      'test-model'
    );
    Test.stopTest();

    AIExecutionStep__c saved = [
      SELECT
        StepType__c,
        StepOrder__c,
        Status__c,
        Provider__c,
        ModelIdentifier__c,
        AttemptNumber__c,
        ToolCallingIterationsUsed__c,
        ToolCallingIterationsMax__c,
        RecordsSentCount__c,
        ObjectsSent__c
      FROM AIExecutionStep__c
      WHERE AIConversationMessage__c = :reply.Id
    ];
    Assert.areEqual(
      AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL,
      saved.StepType__c,
      'No data source, so a provider call.'
    );
    Assert.areEqual(1, saved.StepOrder__c, 'Ordered from one.');
    Assert.areEqual(
      AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS,
      saved.Status__c,
      'Successful.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC,
      saved.Provider__c,
      'The provider from the caller.'
    );
    Assert.areEqual(
      'test-model',
      saved.ModelIdentifier__c,
      'The model from the caller.'
    );
    Assert.areEqual(2, saved.AttemptNumber__c, 'The attempt.');
    Assert.areEqual(
      5,
      saved.ToolCallingIterationsMax__c,
      'The tool-calling limit.'
    );
    Assert.areEqual(4, saved.RecordsSentCount__c, 'What was sent is recorded.');
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      10,
      1,
      true
    )[0];
    AIExecutionStepTracker trace = new AIExecutionStepTracker(
      conversation.Id,
      reply.Id,
      false,
      false
    );
    AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(
      1,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      true
    )[0];
    AIExecutionStepTracker.StepEntry step = new AIExecutionStepTracker.StepEntry();
    step.dataSourceId = dataSource.Id;
    step.isSuccess = false;
    trace.steps.add(step);

    Test.startTest();
    AIExecutionStepRecorder.recordExecutionSteps(
      reply.Id,
      trace,
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC,
      'test-model'
    );
    Test.stopTest();

    AIExecutionStep__c saved = [
      SELECT StepType__c, Status__c, AIDataSource__c, Provider__c
      FROM AIExecutionStep__c
      WHERE AIConversationMessage__c = :reply.Id
    ];
    Assert.areEqual(
      AIAssistApplicationConstants.STEP_TYPE_DATA_SOURCE,
      saved.StepType__c,
      'A data source step.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED,
      saved.Status__c,
      'Failed.'
    );
    Assert.areEqual(
      dataSource.Id,
      saved.AIDataSource__c,
      'It names the source.'
    );
    Assert.isNull(
      saved.Provider__c,
      'Provider detail belongs to provider calls only.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      10,
      1,
      true
    )[0];
    AIExecutionStepTracker trace = new AIExecutionStepTracker(
      conversation.Id,
      reply.Id,
      false,
      false
    );
    AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'Some_Flow',
      true
    )[0];
    AIExecutionStepTracker.StepEntry step = new AIExecutionStepTracker.StepEntry();
    step.stepType = AIAssistApplicationConstants.STEP_TYPE_WORKFLOW_ACTION;
    step.workflowActionId = action.Id;
    step.targetObject = 'Account';
    step.targetRecordId = '001000000000001AAA';
    step.requiredConfirmation = true;
    step.confirmedBy = UserInfo.getUserId();
    step.confirmedDate = Datetime.now();
    trace.steps.add(step);

    Test.startTest();
    AIExecutionStepRecorder.recordExecutionSteps(
      reply.Id,
      trace,
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC,
      'test-model'
    );
    Test.stopTest();

    AIExecutionStep__c saved = [
      SELECT
        AIWorkflowAction__c,
        TargetObject__c,
        TargetRecordId__c,
        RequiredConfirmation__c,
        ConfirmedBy__c,
        ConfirmedDate__c
      FROM AIExecutionStep__c
      WHERE AIConversationMessage__c = :reply.Id
    ];
    Assert.areEqual(action.Id, saved.AIWorkflowAction__c, 'The action.');
    Assert.areEqual('Account', saved.TargetObject__c, 'The object acted on.');
    Assert.isTrue(saved.RequiredConfirmation__c, 'It required confirmation.');
    Assert.areEqual(
      UserInfo.getUserId(),
      saved.ConfirmedBy__c,
      'Who confirmed.'
    );
    Assert.isNotNull(saved.ConfirmedDate__c, 'And when.');
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      10,
      1,
      true
    )[0];
    AIExecutionStepTracker trace = new AIExecutionStepTracker(
      conversation.Id,
      reply.Id,
      false,
      false
    );
    AIExecutionStepTracker debugTrace = new AIExecutionStepTracker(
      conversation.Id,
      reply.Id,
      false,
      true
    );
    debugTrace.steps.add(new AIExecutionStepTracker.StepEntry());
    debugTrace.steps.add(new AIExecutionStepTracker.StepEntry());
    debugTrace.lastRequestJson = 'r'
      .repeat(AIAssistApplicationConstants.STEP_JSON_FIELD_LENGTH + 10);
    debugTrace.lastResponseJson = '{"ok":true}';
    debugTrace.sentPreviewText = 'p'
      .repeat(AIAssistApplicationConstants.STEP_SENT_PREVIEW_LENGTH + 10);
    trace.steps.add(new AIExecutionStepTracker.StepEntry());
    trace.lastRequestJson = '{"secret":"customer data"}';

    AIConversationMessage__c debugReply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      10,
      1,
      true
    )[0];

    Test.startTest();
    AIExecutionStepRecorder.recordExecutionSteps(
      reply.Id,
      trace,
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC,
      'test-model'
    );
    AIExecutionStepRecorder.recordExecutionSteps(
      debugReply.Id,
      debugTrace,
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC,
      'test-model'
    );
    Test.stopTest();

    AIExecutionStep__c normal = [
      SELECT RequestJson__c
      FROM AIExecutionStep__c
      WHERE AIConversationMessage__c = :reply.Id
    ];
    List<AIExecutionStep__c> debugSteps = [
      SELECT RequestJson__c, ResponseJson__c, SentPreviewText__c
      FROM AIExecutionStep__c
      WHERE AIConversationMessage__c = :debugReply.Id
      ORDER BY StepOrder__c
    ];
    Assert.isNull(
      normal.RequestJson__c,
      'Without debug mode customer data is not kept.'
    );
    Assert.isNull(debugSteps[0].RequestJson__c, 'Not on an earlier call.');
    Assert.areEqual(
      AIAssistApplicationConstants.STEP_JSON_FIELD_LENGTH,
      debugSteps[1].RequestJson__c.length(),
      'On the last call, cut to the field size.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.STEP_SENT_PREVIEW_LENGTH,
      debugSteps[1].SentPreviewText__c.length(),
      'The preview too.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      10,
      1,
      true
    )[0];
    AIExecutionStepTracker trace = new AIExecutionStepTracker(
      conversation.Id,
      reply.Id,
      false,
      false
    );
    AIExecutionStepTracker.StepEntry step = new AIExecutionStepTracker.StepEntry();
    AIExecutionStepTracker.MaskingEntry first = new AIExecutionStepTracker.MaskingEntry();
    first.sourceObject = 'Contact';
    first.sourceField = 'Email';
    first.piiFieldType = AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL;
    first.complianceGroup = 'GDPR';
    first.maskingStrategy = AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST;
    first.valuesMasked = 3;
    AIExecutionStepTracker.MaskingEntry second = new AIExecutionStepTracker.MaskingEntry();
    second.sourceObject = 'Contact';
    second.sourceField = 'Phone';
    second.piiFieldType = AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL;
    second.complianceGroup = 'GDPR';
    second.maskingStrategy = AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST;
    second.valuesMasked = 0;
    second.outcome = AIAssistApplicationConstants.MASKING_OUTCOME_SKIPPED;
    step.maskingEntries.add(first);
    step.maskingEntries.add(second);
    trace.steps.add(step);

    Test.startTest();
    AIExecutionStepRecorder.recordExecutionSteps(
      reply.Id,
      trace,
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC,
      'test-model'
    );
    Test.stopTest();

    List<AIPIIMaskingRecord__c> records = [
      SELECT
        SourceField__c,
        Outcome__c,
        ValuesMasked__c,
        AIExecutionStep__r.AIConversationMessage__c
      FROM AIPIIMaskingRecord__c
      ORDER BY SourceField__c
    ];
    Assert.areEqual(2, records.size(), 'One row per masked field.');
    Assert.areEqual(
      AIAssistApplicationConstants.MASKING_OUTCOME_MASKED,
      records[0].Outcome__c,
      'Masked by default.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.MASKING_OUTCOME_SKIPPED,
      records[1].Outcome__c,
      'The given outcome is kept.'
    );
    Assert.areEqual(
      reply.Id,
      records[0].AIExecutionStep__r.AIConversationMessage__c,
      'Under the step of this reply.'
    );
  }

  @IsTest
  static void testScenario6() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      10,
      1,
      true
    )[0];
    AIExecutionStepTracker trace = new AIExecutionStepTracker(
      conversation.Id,
      reply.Id,
      false,
      false
    );

    Test.startTest();
    try {
      AIExecutionStepRecorder.recordExecutionSteps(null, trace, 'p', 'm');
      AIExecutionStepRecorder.recordExecutionSteps(reply.Id, null, 'p', 'm');
      AIExecutionStepRecorder.recordExecutionSteps(reply.Id, trace, 'p', 'm');
    } catch (Exception ex) {
      Assert.fail('Recording evidence must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIExecutionStep__c],
      'Nothing to save.'
    );
  }

  @IsTest
  static void testScenario7() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      10,
      1,
      true
    )[0];
    AIExecutionStepTracker trace = new AIExecutionStepTracker(
      conversation.Id,
      reply.Id,
      false,
      false
    );
    AIExecutionStepTracker.StepEntry step = new AIExecutionStepTracker.StepEntry();
    step.objectsSent = 'o'
      .repeat(AIAssistApplicationConstants.STEP_OBJECTS_SENT_LENGTH + 50);
    step.fieldsSent = 'f'
      .repeat(AIAssistApplicationConstants.STEP_FIELDS_SENT_LENGTH + 50);
    trace.steps.add(step);

    Test.startTest();
    AIExecutionStepRecorder.recordExecutionSteps(reply.Id, trace, 'p', 'm');
    Test.stopTest();

    AIExecutionStep__c saved = [
      SELECT ObjectsSent__c, FieldsSent__c
      FROM AIExecutionStep__c
      WHERE AIConversationMessage__c = :reply.Id
    ];
    Assert.areEqual(
      AIAssistApplicationConstants.STEP_OBJECTS_SENT_LENGTH,
      saved.ObjectsSent__c.length(),
      'Objects cut to size.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.STEP_FIELDS_SENT_LENGTH,
      saved.FieldsSent__c.length(),
      'Fields cut to size.'
    );
  }

  @IsTest
  static void testScenario8() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      10,
      1,
      true
    )[0];
    AIExecutionStepTracker trace = new AIExecutionStepTracker(
      conversation.Id,
      reply.Id,
      false,
      false
    );
    for (Integer i = 0; i < 200; i++)
      trace.steps.add(new AIExecutionStepTracker.StepEntry());
    Integer statements;

    Test.startTest();
    AIExecutionStepRecorder.recordExecutionSteps(reply.Id, trace, 'p', 'm');
    statements = Limits.getDmlStatements();
    Test.stopTest();

    Assert.areEqual(
      200,
      [
        SELECT COUNT()
        FROM AIExecutionStep__c
        WHERE AIConversationMessage__c = :reply.Id
      ],
      'All saved.'
    );
    Assert.isTrue(
      statements <= 2,
      'Steps and masking rows are each one statement, however many there are.'
    );
    Assert.areEqual(
      200,
      [
        SELECT StepOrder__c
        FROM AIExecutionStep__c
        WHERE AIConversationMessage__c = :reply.Id
        ORDER BY StepOrder__c DESC
        LIMIT 1
      ]
      .StepOrder__c,
      'Numbered to the end.'
    );
  }
}
