/*
Class Name: AIChatDebugService

=================================================================
=================================================================

Description: What the chat window shows only to a user with debug mode, and the one place real PII values are restored.

Step 1: Build the request trace for a reply: its tokens, model, execution steps and, when recorded, the payloads
Step 2: Find the log reference and, with debug mode, the detail recorded on a failed turn
Step 3: Work out the real value behind each fake value that masking sent to the model
Step 4: Swap the fake values in a reply back to their real values, longest first

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIChatDebugService {

    private class LongestFirst implements Comparator<String> {

        public Integer compare(String first, String second) {

            // [1] Put the longer value first
            return second.length() - first.length();
        }
    }

    // The request trace for a reply: its tokens, model, execution steps and, when the user had debug mode on at the time, the payloads. The caller has already checked debug mode and that the user owns the conversation.
    public static AIChatDataStructure.DebugTrace getDebugTrace(AIConversationMessage__c reply) {

        // [1] Copy the reply's details onto the trace
        AIChatDataStructure.DebugTrace debugTrace = new AIChatDataStructure.DebugTrace();
        debugTrace.conversationId = reply.AIConversation__c;
        debugTrace.conversationName = reply.AIConversation__r.Name;
        debugTrace.replyMessageId = reply.Id;
        debugTrace.replyTokens = reply.TokenCount__c;

        // [2] Find the user message the reply answered, and add its tokens and how long the reply took
        List<AIConversationMessage__c> promptMessages = [SELECT Id, TokenCount__c, CreatedDate FROM AIConversationMessage__c WHERE AIConversation__c = :reply.AIConversation__c AND Sender__c = :AIAssistApplicationConstants.SENDER_USER AND CreatedDate <= :reply.CreatedDate WITH SYSTEM_MODE ORDER BY CreatedDate DESC, Id DESC LIMIT 1];

        if (!promptMessages.isEmpty()) {

            debugTrace.userMessageId = promptMessages[0].Id;
            debugTrace.promptTokens = promptMessages[0].TokenCount__c;
            debugTrace.durationMs = reply.CreatedDate.getTime() - promptMessages[0].CreatedDate.getTime();
        }

        // [3] Add the model configuration the conversation's agent uses
        List<AIConversation__c> conversationAgentModels = [SELECT AIAgent__r.AIModelConfiguration__r.Name, AIAgent__r.AIModelConfiguration__r.AIProvider__c, AIAgent__r.AIModelConfiguration__r.ModelIdentifier__c FROM AIConversation__c WHERE Id = :reply.AIConversation__c WITH SYSTEM_MODE LIMIT 1];

        if (!conversationAgentModels.isEmpty() && conversationAgentModels[0].AIAgent__r != null && conversationAgentModels[0].AIAgent__r.AIModelConfiguration__r != null) {

            AIModelConfiguration__c modelConfiguration = conversationAgentModels[0].AIAgent__r.AIModelConfiguration__r;
            debugTrace.modelConfiguration = modelConfiguration.Name;
            debugTrace.provider = modelConfiguration.AIProvider__c;
            debugTrace.model = modelConfiguration.ModelIdentifier__c;
        }

        // [4] Add each execution step of the reply, and the totals they carry
        for (AIExecutionStepRecorder.TraceStep step : AIExecutionStepRecorder.parseTrace(reply.ExecutionTraceJson__c)) {

            debugTrace.steps.add(AIChatConversationService.buildExecutionStep(step));
            if (step.stepType == AIAssistApplicationConstants.STEP_TYPE_DATA_SOURCE) debugTrace.toolCalls++;
            if (step.status == AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED) debugTrace.isSuccess = false;

            // [5] Take the iteration and attempt figures, which only the last provider call carries
            if (step.iterationsUsed != null) debugTrace.toolCallingIterationsUsed = step.iterationsUsed;
            if (step.iterationsMax != null) debugTrace.toolCallingIterationsMax = step.iterationsMax;
            if (step.attempt != null) debugTrace.attemptNumber = step.attempt;
        }

        // [5] Add the masked-value total and the payloads, which are saved only when the user had debug mode on
        if (reply.PIIValuesMasked__c != null) debugTrace.piiFieldsMasked = reply.PIIValuesMasked__c.intValue();
        if (String.isNotBlank(reply.DebugRequestJson__c)) debugTrace.requestJson = reply.DebugRequestJson__c;
        if (String.isNotBlank(reply.DebugResponseJson__c)) debugTrace.responseJson = reply.DebugResponseJson__c;
        if (String.isNotBlank(reply.DebugSentPreviewText__c)) debugTrace.sentPreviewText = reply.DebugSentPreviewText__c;

        // [6] Return the trace
        return debugTrace;
    }

    // The log reference to quote to an administrator and, with debug mode, the detail recorded on the failed turn's System message.
    public static AIChatDataStructure.FailureDetail getFailureDetail(Id conversationId, Boolean includeDebugDetail) {

        // [1] Find the user's most recent log in the last 15 minutes, to quote as the reference
        AIChatDataStructure.FailureDetail failureDetail = new AIChatDataStructure.FailureDetail();
        Datetime windowStart = System.now().addMinutes(-15);

        List<AIPlatformLog__c> recentLogs = [SELECT Name FROM AIPlatformLog__c WHERE User__c = :UserInfo.getUserId() AND CreatedDate >= :windowStart WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 1];
        failureDetail.reference = recentLogs.isEmpty() ? null : recentLogs[0].Name;

        if (includeDebugDetail) {

            // [2] Find when the latest turn started, because a System message from before the newest user message belongs to an earlier turn and would mislead
            List<AIConversationMessage__c> latestUserMessages = [SELECT CreatedDate FROM AIConversationMessage__c WHERE AIConversation__c = :conversationId AND Sender__c = :AIAssistApplicationConstants.SENDER_USER WITH SYSTEM_MODE ORDER BY CreatedDate DESC, Id DESC LIMIT 1];
            Datetime turnStartedAt = latestUserMessages.isEmpty() ? Datetime.newInstance(1970, 1, 1) : latestUserMessages[0].CreatedDate;

            // [3] Add the detail recorded on that turn's System message, if there is one
            List<AIConversationMessage__c> failedTurns = [SELECT MessageBody__c FROM AIConversationMessage__c WHERE AIConversation__c = :conversationId AND Sender__c = :AIAssistApplicationConstants.SENDER_SYSTEM AND CreatedDate >= :turnStartedAt WITH SYSTEM_MODE ORDER BY CreatedDate DESC, Id DESC LIMIT 1];

            if (!failedTurns.isEmpty()) failureDetail.debugDetail = failedTurns[0].MessageBody__c;
        }

        // [4] Return the detail
        return failureDetail;
    }

    // Fake value to real value from the conversation's mapping. Empty when nothing was masked.
    public static Map<String, String> getRealValueByFakeValue(Id conversationId) {

        // [1] Read the conversation's mapping of real values to fake ones
        Map<String, String> realValueByFakeValue = new Map<String, String>();
        Map<String, String> fakeValueByRealValue = AIPiiMappingService.getMapping(conversationId);

        // [2] Turn it round, so each fake value points to its real value
        for (String realValue : fakeValueByRealValue.keySet()) realValueByFakeValue.put(fakeValueByRealValue.get(realValue), realValue);

        // [3] Return the turned round mapping
        return realValueByFakeValue;
    }

    // Swaps each fake value in a reply back to its real value, longest first so "Morgan Reyes" is replaced whole before "Morgan".
    public static String restorePii(String text, Map<String, String> realValueByFakeValue) {

        // [1] Nothing to restore when there is no text or no mapping
        if (String.isBlank(text) || realValueByFakeValue == null || realValueByFakeValue.isEmpty()) return text;

        // [2] Put the fake values longest first
        List<String> fakeValues = new List<String>(realValueByFakeValue.keySet());
        fakeValues.sort(new LongestFirst());

        // [3] Replace each fake value with its real value
        String restored = text;

        for (String fakeValue : fakeValues) {

            if (String.isNotBlank(fakeValue)) restored = restored.replace(fakeValue, realValueByFakeValue.get(fakeValue));
        }

        // [4] Return the restored text
        return restored;
    }
}
