/*
Class Name: AIExecutionStepRecorderTest

=================================================================
=================================================================

Description: Testing utility for AIExecutionStepRecorder: the execution trace saved on a message, what is kept only in debug mode, the masking records, and that a bookkeeping problem never breaks the turn.

=================================================================
=================================================================
Applicable Classes:

AIExecutionStepRecorder: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIExecutionStepRecorderTest {

    // testScenario1: A provider call step is saved with the provider and model from the caller when the tracker did not name them, with the attempt and tool-calling figures on the last call -> the trace entry carries them.
    // testScenario2: A step naming a data source is a data source step, and a failed step is saved as Failed -> Data Source type, Failed status, no provider.
    // testScenario3: A workflow action step keeps the action, the target and who confirmed it and when -> the evidence the security model asks for is saved.
    // testScenario4: Request and response payloads are saved on the message only for a debug-mode user, and are cut to the field size -> a normal turn keeps none.
    // testScenario5: Masking entries are saved against the message and the step that masked them, with Masked as the outcome when none was given -> one row per masked field.
    // testScenario6: Recording with no message, no trace or a trace with no steps -> nothing is saved.
    // testScenario7: A value longer than its field -> it is cut instead of losing the trace.
    // testScenario8: Bulk: two hundred steps -> all saved in one update, in order.
    // testScenario9: A trace the user has step capture off for, and one with it on -> the first stores no trace for the turn, the second stores its step.
    // testScenario10: A workflow action recorded after the reply -> it is added to the end of the saved trace, and a second one after that.
    // testScenario11: A trace too long for the field -> the middle is taken out, one entry says how many, and the start and the end are kept.
    // testScenario12: Blank and unreadable trace text -> an empty trace, never an error.
    // testScenario13: The plain wording of a step the tracker was given -> the detail is saved as written.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    private static AIConversationMessage__c createReply() {

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];

        return AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 10, 1, true)[0];
    }

    private static List<AIExecutionStepRecorder.TraceStep> readTrace(Id messageId) {

        return AIExecutionStepRecorder.parseTrace([SELECT ExecutionTraceJson__c FROM AIConversationMessage__c WHERE Id = :messageId].ExecutionTraceJson__c);
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a reply message
            AIConversationMessage__c reply = createReply();

            // [2] Build a tracker with one provider step and its attempt figures
            AIExecutionStepTracker trace = new AIExecutionStepTracker(reply.AIConversation__c, reply.Id, false, false);

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
                AIExecutionStepRecorder.recordExecutionSteps(reply.Id, trace, AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, 'test-model');
            Test.stopTest();

            // [4] Read the saved trace back
            List<AIExecutionStepRecorder.TraceStep> saved = readTrace(reply.Id);

            // [5] Check the entry carries the provider, model and figures
            Assert.areEqual(1, saved.size(), 'One entry.');
            Assert.areEqual(AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL, saved[0].stepType, 'No data source, so a provider call.');
            Assert.areEqual(1, saved[0].step, 'Numbered from one.');
            Assert.areEqual(AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS, saved[0].status, 'Successful.');
            Assert.areEqual(250, saved[0].ms, 'The time it took.');
            Assert.areEqual(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, saved[0].provider, 'The provider from the caller.');
            Assert.areEqual('test-model', saved[0].model, 'The model from the caller.');
            Assert.areEqual(2, saved[0].attempt, 'The attempt.');
            Assert.areEqual(5, saved[0].iterationsMax, 'The tool-calling limit.');
            Assert.areEqual(4, saved[0].recordsSent, 'What was sent is recorded.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a reply message
            AIConversationMessage__c reply = createReply();

            // [2] Build a tracker with a failed step that names a data source
            AIExecutionStepTracker trace = new AIExecutionStepTracker(reply.AIConversation__c, reply.Id, false, false);

            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true)[0];

            AIExecutionStepTracker.StepEntry step = new AIExecutionStepTracker.StepEntry();
            step.dataSourceId = dataSource.Id;
            step.dataSourceName = 'Get_Open_Orders';
            step.isSuccess = false;
            trace.steps.add(step);

            // [3] Record the execution steps
            Test.startTest();
                AIExecutionStepRecorder.recordExecutionSteps(reply.Id, trace, AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, 'test-model');
            Test.stopTest();

            // [4] Read the saved trace back
            List<AIExecutionStepRecorder.TraceStep> saved = readTrace(reply.Id);

            // [5] Check it is a failed data source step with no provider
            Assert.areEqual(AIAssistApplicationConstants.STEP_TYPE_DATA_SOURCE, saved[0].stepType, 'A data source step.');
            Assert.areEqual(AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED, saved[0].status, 'Failed.');
            Assert.areEqual('Get_Open_Orders', saved[0].dataSource, 'It names the source.');
            Assert.isNull(saved[0].provider, 'Provider detail belongs to provider calls only.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a reply message
            AIConversationMessage__c reply = createReply();

            // [2] Build a tracker with a confirmed workflow action step
            AIExecutionStepTracker trace = new AIExecutionStepTracker(reply.AIConversation__c, reply.Id, false, false);

            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'Some_Flow', true)[0];

            AIExecutionStepTracker.StepEntry step = new AIExecutionStepTracker.StepEntry();
            step.stepType = AIAssistApplicationConstants.STEP_TYPE_WORKFLOW_ACTION;
            step.workflowActionId = action.Id;
            step.workflowActionName = 'Update Order Note';
            step.targetObject = 'Account';
            step.targetRecordId = '001000000000001AAA';
            step.requiredConfirmation = true;
            step.confirmedBy = UserInfo.getUserId();
            step.confirmedDate = Datetime.now();
            trace.steps.add(step);

            // [3] Record the execution steps
            Test.startTest();
                AIExecutionStepRecorder.recordExecutionSteps(reply.Id, trace, AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, 'test-model');
            Test.stopTest();

            // [4] Read the saved trace back
            List<AIExecutionStepRecorder.TraceStep> saved = readTrace(reply.Id);

            // [5] Check the target and the confirmation evidence are saved
            Assert.areEqual(String.valueOf(action.Id), saved[0].workflowActionId, 'The action.');
            Assert.areEqual('Update Order Note', saved[0].workflowActionName, 'Its name.');
            Assert.areEqual('Account', saved[0].targetObject, 'The object acted on.');
            Assert.isTrue(saved[0].requiredConfirmation, 'It required confirmation.');
            Assert.areEqual(String.valueOf(UserInfo.getUserId()), saved[0].confirmedBy, 'Who confirmed.');
            Assert.isNotNull(saved[0].confirmedDate, 'And when.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two reply messages
            AIConversationMessage__c reply = createReply();
            AIConversationMessage__c debugReply = AIAssistTestDataFactory.createAIConversationMessages(reply.AIConversation__c, AIAssistApplicationConstants.SENDER_AI_AGENT, 10, 1, true)[0];

            // [2] Build a normal tracker and a debug tracker holding oversized payloads
            AIExecutionStepTracker trace = new AIExecutionStepTracker(reply.AIConversation__c, reply.Id, false, false);
            trace.steps.add(new AIExecutionStepTracker.StepEntry());
            trace.lastRequestJson = '{"secret":"customer data"}';

            AIExecutionStepTracker debugTrace = new AIExecutionStepTracker(reply.AIConversation__c, reply.Id, false, true);
            debugTrace.steps.add(new AIExecutionStepTracker.StepEntry());
            debugTrace.lastRequestJson = 'r'.repeat(AIAssistApplicationConstants.STEP_JSON_FIELD_LENGTH + 10);
            debugTrace.lastResponseJson = '{"ok":true}';
            debugTrace.sentPreviewText = 'p'.repeat(AIAssistApplicationConstants.STEP_SENT_PREVIEW_LENGTH + 10);

            // [3] Record both trackers
            Test.startTest();
                AIExecutionStepRecorder.recordExecutionSteps(reply.Id, trace, AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, 'test-model');
                AIExecutionStepRecorder.recordExecutionSteps(debugReply.Id, debugTrace, AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, 'test-model');
            Test.stopTest();

            // [4] Read back both messages
            AIConversationMessage__c normal = [SELECT DebugRequestJson__c, DebugResponseJson__c FROM AIConversationMessage__c WHERE Id = :reply.Id];
            AIConversationMessage__c debug = [SELECT DebugRequestJson__c, DebugResponseJson__c, DebugSentPreviewText__c FROM AIConversationMessage__c WHERE Id = :debugReply.Id];

            // [5] Check payloads are kept only for debug, cut to size
            Assert.isNull(normal.DebugRequestJson__c, 'Without debug mode customer data is not kept.');
            Assert.areEqual(AIAssistApplicationConstants.STEP_JSON_FIELD_LENGTH, debug.DebugRequestJson__c.length(), 'Cut to the field size.');
            Assert.areEqual('{"ok":true}', debug.DebugResponseJson__c, 'The response is kept.');
            Assert.areEqual(AIAssistApplicationConstants.STEP_SENT_PREVIEW_LENGTH, debug.DebugSentPreviewText__c.length(), 'The preview too.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a reply message
            AIConversationMessage__c reply = createReply();

            // [2] Build a tracker with a provider step and a masking step holding two masking entries
            AIExecutionStepTracker trace = new AIExecutionStepTracker(reply.AIConversation__c, reply.Id, false, false);
            AIExecutionStepTracker.StepEntry maskingStep = trace.addStep(AIAssistApplicationConstants.STEP_TYPE_PII_MASKING, true, null, 'Masked 3 values in the request.');

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
            maskingStep.maskingEntries.add(first);
            maskingStep.maskingEntries.add(second);

            trace.addStep(AIAssistApplicationConstants.STEP_TYPE_OTHER, true, 1L, 'After the masking step.');

            // [3] Record the execution steps
            Test.startTest();
                AIExecutionStepRecorder.recordExecutionSteps(reply.Id, trace, AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, 'test-model');
            Test.stopTest();

            // [4] Read the masking records and the message total back
            List<AIPIIMaskingRecord__c> records = [SELECT SourceField__c, Outcome__c, ValuesMasked__c, StepOrder__c, AIConversationMessage__c FROM AIPIIMaskingRecord__c ORDER BY SourceField__c];
            AIConversationMessage__c savedReply = [SELECT PIIValuesMasked__c FROM AIConversationMessage__c WHERE Id = :reply.Id];

            // [5] Check one row per entry with the right outcome, message and step
            Assert.areEqual(2, records.size(), 'One row per masked field.');
            Assert.areEqual(AIAssistApplicationConstants.MASKING_OUTCOME_MASKED, records[0].Outcome__c, 'Masked by default.');
            Assert.areEqual(AIAssistApplicationConstants.MASKING_OUTCOME_SKIPPED, records[1].Outcome__c, 'The given outcome is kept.');
            Assert.areEqual(reply.Id, records[0].AIConversationMessage__c, 'Against this reply.');
            Assert.areEqual(1, records[0].StepOrder__c, 'Against the masking step.');
            Assert.areEqual(3, savedReply.PIIValuesMasked__c, 'The message adds up the values masked.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a reply message and an empty tracker
            AIConversationMessage__c reply = createReply();

            AIExecutionStepTracker trace = new AIExecutionStepTracker(reply.AIConversation__c, reply.Id, false, false);

            // [2] Record with no message, no trace and a trace with no steps
            Test.startTest();
                AIExecutionStepRecorder.recordExecutionSteps(null, trace, 'p', 'm');
                AIExecutionStepRecorder.recordExecutionSteps(reply.Id, null, 'p', 'm');
                AIExecutionStepRecorder.recordExecutionSteps(reply.Id, trace, 'p', 'm');
            Test.stopTest();

            // [3] Check nothing was saved
            Assert.isNull([SELECT ExecutionTraceJson__c FROM AIConversationMessage__c WHERE Id = :reply.Id].ExecutionTraceJson__c, 'Nothing to save.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a reply message
            AIConversationMessage__c reply = createReply();

            // [2] Build a tracker with a step whose values are longer than their limits
            AIExecutionStepTracker trace = new AIExecutionStepTracker(reply.AIConversation__c, reply.Id, false, false);

            AIExecutionStepTracker.StepEntry step = new AIExecutionStepTracker.StepEntry();
            step.objectsSent = 'o'.repeat(AIAssistApplicationConstants.STEP_OBJECTS_SENT_LENGTH + 50);
            step.fieldsSent = 'f'.repeat(AIAssistApplicationConstants.STEP_FIELDS_SENT_LENGTH + 50);
            step.stepDetail = 'd'.repeat(AIAssistApplicationConstants.STEP_DETAIL_LENGTH + 50);
            trace.steps.add(step);

            // [3] Record the execution steps
            Test.startTest();
                AIExecutionStepRecorder.recordExecutionSteps(reply.Id, trace, 'p', 'm');
            Test.stopTest();

            // [4] Read the saved trace back
            List<AIExecutionStepRecorder.TraceStep> saved = readTrace(reply.Id);

            // [5] Check the values were cut to size
            Assert.areEqual(AIAssistApplicationConstants.STEP_OBJECTS_SENT_LENGTH, saved[0].objectsSent.length(), 'Objects cut to size.');
            Assert.areEqual(AIAssistApplicationConstants.STEP_FIELDS_SENT_LENGTH, saved[0].fieldsSent.length(), 'Fields cut to size.');
            Assert.areEqual(AIAssistApplicationConstants.STEP_DETAIL_LENGTH, saved[0].stepDetail.length(), 'The detail cut to size.');
        }
    }

    @IsTest static void testScenario8() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a reply message
            AIConversationMessage__c reply = createReply();

            // [2] Build a tracker with 200 steps
            AIExecutionStepTracker trace = new AIExecutionStepTracker(reply.AIConversation__c, reply.Id, false, false);
            for (Integer i = 0; i < 200; i++) trace.steps.add(new AIExecutionStepTracker.StepEntry());
            Integer statements;

            // [3] Record the steps and note the DML statements used
            Test.startTest();
                AIExecutionStepRecorder.recordExecutionSteps(reply.Id, trace, 'p', 'm');
                statements = Limits.getDmlStatements();
            Test.stopTest();

            // [4] Read the saved trace back
            List<AIExecutionStepRecorder.TraceStep> saved = readTrace(reply.Id);

            // [5] Check all steps were saved in one update, in order
            Assert.areEqual(200, saved.size(), 'All saved.');
            Assert.isTrue(statements <= 2, 'The trace and the masking rows are each one statement, however many steps there are.');
            Assert.areEqual(200, saved[199].step, 'Numbered to the end.');
        }
    }

    @IsTest static void testScenario9() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a conversation and a message
            AIConversationMessage__c message = createReply();

            Map<Boolean, Integer> stepsByCaptureSetting = new Map<Boolean, Integer>();

            // [2] Record one step with step capture off, then on
            Test.startTest();
                for (Boolean shouldCaptureSteps : new List<Boolean>{ false, true }) {

                    AIExecutionStepTracker trace = new AIExecutionStepTracker(message.AIConversation__c, message.Id, false, false);
                    trace.shouldCaptureSteps = shouldCaptureSteps;
                    trace.startStep('Calling the model', null);
                    trace.endStep(true);
                    AIMessagingDataService.updateOrThrow(new List<SObject>{ new AIConversationMessage__c(Id = message.Id, ExecutionTraceJson__c = null) });
                    AIExecutionStepRecorder.recordExecutionSteps(message.Id, trace, 'Anthropic', 'model-1');
                    stepsByCaptureSetting.put(shouldCaptureSteps, readTrace(message.Id).size());
                }
            Test.stopTest();

            // [3] Check off stores nothing and on stores the step
            Assert.areEqual(0, stepsByCaptureSetting.get(false), 'With step capture off nothing is stored.');
            Assert.areEqual(1, stepsByCaptureSetting.get(true), 'With step capture on the step is stored.');
        }
    }

    @IsTest static void testScenario10() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a reply that already has a one-step trace, and an action
            AIConversationMessage__c reply = createReply();
            AIAssistTestDataFactory.createAIExecutionTraceSteps(reply.Id, 1, true);

            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'Some_Flow', true)[0];
            action = [SELECT Id, ActionName__c, TargetObject__c, RequiresConfirmation__c FROM AIWorkflowAction__c WHERE Id = :action.Id];

            // [2] Record the action twice: confirmed and successful, then cancelled
            Test.startTest();
                AIExecutionStepRecorder.recordWorkflowActionStep(reply.Id, action, null, AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS, true, 30);
                AIExecutionStepRecorder.recordWorkflowActionStep(reply.Id, action, null, AIAssistApplicationConstants.EXECUTION_STEP_STATUS_CANCELLED, false, null);
            Test.stopTest();

            // [3] Read the trace back
            List<AIExecutionStepRecorder.TraceStep> saved = readTrace(reply.Id);

            // [4] Check both went to the end, in order, and the first trace entry is kept
            Assert.areEqual(3, saved.size(), 'The earlier step and both actions.');
            Assert.areEqual(AIAssistApplicationConstants.STEP_TYPE_OTHER, saved[0].stepType, 'The earlier step is kept.');
            Assert.areEqual(2, saved[1].step, 'The first action is next.');
            Assert.areEqual(AIAssistApplicationConstants.STEP_TYPE_WORKFLOW_ACTION, saved[1].stepType, 'It is a workflow action.');
            Assert.areEqual(AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS, saved[1].status, 'Its status.');
            Assert.areEqual(String.valueOf(action.Id), saved[1].workflowActionId, 'Which action.');
            Assert.areEqual(3, saved[2].step, 'The second action follows.');
            Assert.areEqual(AIAssistApplicationConstants.EXECUTION_STEP_STATUS_CANCELLED, saved[2].status, 'Cancelled.');
            Assert.isNull(saved[2].confirmedBy, 'A declined action was not confirmed.');
        }
    }

    @IsTest static void testScenario11() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a trace far too long for the field
            List<AIExecutionStepRecorder.TraceStep> longTrace = new List<AIExecutionStepRecorder.TraceStep>();

            for (Integer i = 1; i <= 200; i++) {

                AIExecutionStepRecorder.TraceStep traceStep = new AIExecutionStepRecorder.TraceStep();
                traceStep.step = i;
                traceStep.stepType = AIAssistApplicationConstants.STEP_TYPE_OTHER;
                traceStep.status = AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS;
                traceStep.stepDetail = 'x'.repeat(AIAssistApplicationConstants.STEP_DETAIL_LENGTH);
                longTrace.add(traceStep);
            }

            // [2] Serialise it
            String traceJson;

            Test.startTest();
                traceJson = AIExecutionStepRecorder.serializeTrace(longTrace);
            Test.stopTest();

            // [3] Check it fits, keeps the start and the end, and says how many are missing
            List<AIExecutionStepRecorder.TraceStep> saved = AIExecutionStepRecorder.parseTrace(traceJson);

            Assert.isTrue(traceJson.length() <= AIAssistApplicationConstants.STEP_JSON_FIELD_LENGTH, 'It fits the field.');
            Assert.isTrue(saved.size() < 200, 'Some entries were taken out.');
            Assert.areEqual(1, saved[0].step, 'The first entry is kept.');
            Assert.areEqual(200, saved[saved.size() - 1].step, 'The last entry is kept.');

            Boolean hasOmissionNote = false;

            for (AIExecutionStepRecorder.TraceStep savedStep : saved) {

                if (savedStep.step == null && savedStep.stepDetail != null && savedStep.stepDetail.contains('not shown')) hasOmissionNote = true;
            }

            Assert.isTrue(hasOmissionNote, 'One entry says steps are not shown.');
        }
    }

    @IsTest static void testScenario12() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Read blank and unreadable text
            List<AIExecutionStepRecorder.TraceStep> fromNull;
            List<AIExecutionStepRecorder.TraceStep> fromBlank;
            List<AIExecutionStepRecorder.TraceStep> fromGarbage;

            Test.startTest();
                fromNull = AIExecutionStepRecorder.parseTrace(null);
                fromBlank = AIExecutionStepRecorder.parseTrace('  ');
                fromGarbage = AIExecutionStepRecorder.parseTrace('{not json');
            Test.stopTest();

            // [2] Check each is an empty trace
            Assert.isTrue(fromNull.isEmpty() && fromBlank.isEmpty() && fromGarbage.isEmpty(), 'Nothing readable is an empty trace.');
        }
    }

    @IsTest static void testScenario13() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a reply and a tracker with steps the caller described
            AIConversationMessage__c reply = createReply();

            AIExecutionStepTracker trace = new AIExecutionStepTracker(reply.AIConversation__c, reply.Id, false, false);
            trace.addStep(AIAssistApplicationConstants.STEP_TYPE_PROMPT_ASSEMBLY, true, 4L, 'Built the prompt for agent Support using prompt template General Support.');
            trace.addStep(AIAssistApplicationConstants.STEP_TYPE_TEMPLATE_MATCH, true, 1L, 'Switched from General Support to Order Enquiry.');

            // [2] Record them
            Test.startTest();
                AIExecutionStepRecorder.recordExecutionSteps(reply.Id, trace, 'p', 'm');
            Test.stopTest();

            // [3] Check the types and the wording are saved as written
            List<AIExecutionStepRecorder.TraceStep> saved = readTrace(reply.Id);

            Assert.areEqual(AIAssistApplicationConstants.STEP_TYPE_PROMPT_ASSEMBLY, saved[0].stepType, 'The first step is the prompt.');
            Assert.areEqual('Built the prompt for agent Support using prompt template General Support.', saved[0].stepDetail, 'Its wording.');
            Assert.areEqual(AIAssistApplicationConstants.STEP_TYPE_TEMPLATE_MATCH, saved[1].stepType, 'The second is the template match.');
            Assert.areEqual(1, saved[1].ms, 'And its time.');
        }
    }
}
