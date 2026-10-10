/*
Class Name: AIExecutionStepRecorderTest

=================================================================
=================================================================

Description: Testing utility for AIExecutionStepRecorder: the execution evidence saved for a turn, what is kept only in debug mode, and that a bookkeeping problem never breaks the turn.

=================================================================
=================================================================
Applicable Classes:

AIExecutionStepRecorder: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIExecutionStepRecorderTest {
  // testScenario1: A provider call step is saved with the provider and model from the caller when the tracker did not name them, in order, with the attempt and tool-calling figures -> the step carries them.
  // testScenario2: A step naming a data source is a data source step, and a failed step is saved as Failed -> Data Source type, Failed status, no provider.
  // testScenario3: A workflow action step keeps the target and who confirmed it and when -> the evidence the security model asks for is saved.
  // testScenario4: Request and response payloads are saved only for a debug-mode user and only on the last provider call, and are cut to the field size -> other steps keep none.
  // testScenario5: Masking entries are saved under the step that sent the data, with Masked as the outcome when none was given -> one row per masked field.
  // testScenario6: Recording with no message, no trace or a trace with no steps -> nothing is saved.
  // testScenario7: A value longer than its field -> it is cut instead of losing the evidence row.
  // testScenario8: Bulk: two hundred steps -> all saved in one insert, in order.
  // testScenario9: Each capture mode -> Off stores no step for the turn, Summary, Full and a blank or unknown setting store steps.

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
    // [1] Create an agent, a conversation and a reply message
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
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

    // [2] Build a tracker with one provider step and its attempt figures
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

    // [3] Record the execution steps
    Test.startTest();
    AIExecutionStepRecorder.recordExecutionSteps(
      reply.Id,
      trace,
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC,
      'test-model'
    );
    Test.stopTest();

    // [4] Read the saved step back
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

    // [5] Check the step carries the provider, model and figures
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
    // [1] Create an agent, a conversation and a reply message
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
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

    // [2] Build a tracker with a failed step that names a data source
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

    // [3] Record the execution steps
    Test.startTest();
    AIExecutionStepRecorder.recordExecutionSteps(
      reply.Id,
      trace,
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC,
      'test-model'
    );
    Test.stopTest();

    // [4] Read the saved step back
    AIExecutionStep__c saved = [
      SELECT StepType__c, Status__c, AIDataSource__c, Provider__c
      FROM AIExecutionStep__c
      WHERE AIConversationMessage__c = :reply.Id
    ];

    // [5] Check it is a failed data source step with no provider
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
    // [1] Create an agent, a conversation and a reply message
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
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

    // [2] Build a tracker with a confirmed workflow action step
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

    // [3] Record the execution steps
    Test.startTest();
    AIExecutionStepRecorder.recordExecutionSteps(
      reply.Id,
      trace,
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC,
      'test-model'
    );
    Test.stopTest();

    // [4] Read the saved step back
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

    // [5] Check the target and the confirmation evidence are saved
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
    // [1] Create an agent, a conversation and a reply message
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
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

    // [2] Build a normal tracker and a debug tracker holding oversized payloads
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

    // [3] Record both trackers
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

    // [4] Read back the normal step and the debug steps
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

    // [5] Check payloads are kept only for debug, on the last call, cut to size
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
    // [1] Create an agent, a conversation and a reply message
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
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

    // [2] Build a tracker with one step holding two masking entries
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

    // [3] Record the execution steps
    Test.startTest();
    AIExecutionStepRecorder.recordExecutionSteps(
      reply.Id,
      trace,
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC,
      'test-model'
    );
    Test.stopTest();

    // [4] Read the masking records back
    List<AIPIIMaskingRecord__c> records = [
      SELECT
        SourceField__c,
        Outcome__c,
        ValuesMasked__c,
        AIExecutionStep__r.AIConversationMessage__c
      FROM AIPIIMaskingRecord__c
      ORDER BY SourceField__c
    ];

    // [5] Check one row per entry with the right outcome and parent step
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
    // [1] Create an agent, a conversation, a reply message and an empty tracker
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];

    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
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

    // [2] Record with no message, no trace and a trace with no steps
    Test.startTest();
    AIExecutionStepRecorder.recordExecutionSteps(null, trace, 'p', 'm');
    AIExecutionStepRecorder.recordExecutionSteps(reply.Id, null, 'p', 'm');
    AIExecutionStepRecorder.recordExecutionSteps(reply.Id, trace, 'p', 'm');
    Test.stopTest();

    // [3] Count the saved steps
    Integer stepCount = [SELECT COUNT() FROM AIExecutionStep__c];

    // [4] Check nothing was saved
    Assert.areEqual(0, stepCount, 'Nothing to save.');
  }

  @IsTest
  static void testScenario7() {
    // [1] Create an agent, a conversation and a reply message
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
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

    // [2] Build a tracker with a step whose values are longer than their fields
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

    // [3] Record the execution steps
    Test.startTest();
    AIExecutionStepRecorder.recordExecutionSteps(reply.Id, trace, 'p', 'm');
    Test.stopTest();

    // [4] Read the saved step back
    AIExecutionStep__c saved = [
      SELECT ObjectsSent__c, FieldsSent__c
      FROM AIExecutionStep__c
      WHERE AIConversationMessage__c = :reply.Id
    ];

    // [5] Check the values were cut to the field sizes
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
    // [1] Create an agent, a conversation and a reply message
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
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

    // [2] Build a tracker with 200 steps
    AIExecutionStepTracker trace = new AIExecutionStepTracker(
      conversation.Id,
      reply.Id,
      false,
      false
    );
    for (Integer i = 0; i < 200; i++)
      trace.steps.add(new AIExecutionStepTracker.StepEntry());
    Integer statements;

    // [3] Record the steps and note the DML statements used
    Test.startTest();
    AIExecutionStepRecorder.recordExecutionSteps(reply.Id, trace, 'p', 'm');
    statements = Limits.getDmlStatements();
    Test.stopTest();

    // [4] Count the saved steps and find the last one
    Integer stepCount = [
      SELECT COUNT()
      FROM AIExecutionStep__c
      WHERE AIConversationMessage__c = :reply.Id
    ];
    AIExecutionStep__c lastStep = [
      SELECT StepOrder__c
      FROM AIExecutionStep__c
      WHERE AIConversationMessage__c = :reply.Id
      ORDER BY StepOrder__c DESC
      LIMIT 1
    ];

    // [5] Check all steps were saved in one insert, in order
    Assert.areEqual(200, stepCount, 'All saved.');
    Assert.isTrue(
      statements <= 2,
      'Steps and masking rows are each one statement, however many there are.'
    );
    Assert.areEqual(200, lastStep.StepOrder__c, 'Numbered to the end.');
  }

  @IsTest
  static void testScenario9() {
    // [1] Create an agent, a conversation and a message
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];

    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
      1,
      true
    )[0];

    AIConversationMessage__c message = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_USER,
      5,
      1,
      true
    )[0];

    Map<String, Integer> stepsBySetting = new Map<String, Integer>();

    // [2] Record one step under each capture mode setting
    Test.startTest();
    for (
      String configured : new List<String>{
        'Off',
        'Summary',
        'full',
        '',
        'Everything'
      }
    ) {
      AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
      settings.StepCaptureMode__c = configured;
      update settings;
      AIAssistSettingsService.cachedSettings = null;

      AIExecutionStepTracker trace = new AIExecutionStepTracker(
        conversation.Id,
        message.Id,
        false,
        false
      );
      trace.startStep('Calling the model', null);
      trace.endStep(true);
      delete [SELECT Id FROM AIExecutionStep__c];
      AIExecutionStepRecorder.recordExecutionSteps(
        message.Id,
        trace,
        'Anthropic',
        'model-1'
      );
      stepsBySetting.put(configured, [SELECT COUNT() FROM AIExecutionStep__c]);
    }
    Test.stopTest();

    // [3] Check Off stores nothing and every other setting stores the step
    Assert.areEqual(0, stepsBySetting.get('Off'), 'Off stores no step.');
    Assert.areEqual(1, stepsBySetting.get('Summary'), 'Summary stores it.');
    Assert.areEqual(1, stepsBySetting.get('full'), 'Full stores it.');
    Assert.areEqual(1, stepsBySetting.get(''), 'A blank setting stores steps.');
    Assert.areEqual(
      1,
      stepsBySetting.get('Everything'),
      'And so does an unknown one.'
    );
  }
}
