/*
Class Name: AIChatDebugService

=================================================================
=================================================================

Description: Everything the chat window shows only to a user with debug mode: the request trace for a reply and the failure detail behind a failed turn. It also restores real values in replies for
display and export, so every place a real PII value is handled lives here.

The caller has already checked that the user has debug mode (or may export) and, through
AIChatConversationService, that the conversation is the signed-in user's own. Reads are in system mode
because the User permission set cannot read execution steps, model configurations, PII mappings or
logs (PII mappings are read only to restore values in the user's own replies, never returned as pairs); each is limited to that conversation, message or user. Request and response payloads are only
present when the user had debug mode on at the time (AIExecutionStepRecorder).

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from the old debug service. Payload fields are the ones the recorder writes.
2.0          Chandler Stuart          getPiiMappings removed: it returned the real-to-fake pairs to any user with debug mode, which contradicts "Nobody sees PII mappings" (security model principle 4).
*/

public with sharing class AIChatDebugService {
  public static AIChatDataStructure.DebugTrace getDebugTrace(
    AIConversationMessage__c reply
  ) {
    AIChatDataStructure.DebugTrace debugTrace = new AIChatDataStructure.DebugTrace();
    debugTrace.conversationId = reply.AIConversation__c;
    debugTrace.conversationName = reply.AIConversation__r.Name;
    debugTrace.replyMessageId = reply.Id;
    debugTrace.replyTokens = reply.TokenCount__c;

    List<AIConversationMessage__c> promptMessages = [
      SELECT Id, TokenCount__c, CreatedDate
      FROM AIConversationMessage__c
      WHERE
        AIConversation__c = :reply.AIConversation__c
        AND Sender__c = :AIAssistApplicationConstants.SENDER_USER
        AND CreatedDate <= :reply.CreatedDate
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC, Id DESC
      LIMIT 1
    ];

    if (!promptMessages.isEmpty()) {
      debugTrace.userMessageId = promptMessages[0].Id;
      debugTrace.promptTokens = promptMessages[0].TokenCount__c;
      debugTrace.durationMs =
        reply.CreatedDate.getTime() - promptMessages[0].CreatedDate.getTime();
    }

    List<AIConversation__c> conversationAgentModels = [
      SELECT
        AIAgent__r.AIModelConfiguration__r.Name,
        AIAgent__r.AIModelConfiguration__r.AIProvider__c,
        AIAgent__r.AIModelConfiguration__r.ModelIdentifier__c
      FROM AIConversation__c
      WHERE Id = :reply.AIConversation__c
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (
      !conversationAgentModels.isEmpty() &&
      conversationAgentModels[0].AIAgent__r != null &&
      conversationAgentModels[0].AIAgent__r.AIModelConfiguration__r != null
    ) {
      AIModelConfiguration__c modelConfiguration = conversationAgentModels[0]
        .AIAgent__r.AIModelConfiguration__r;
      debugTrace.modelConfiguration = modelConfiguration.Name;
      debugTrace.provider = modelConfiguration.AIProvider__c;
      debugTrace.model = modelConfiguration.ModelIdentifier__c;
    }

    for (AIExecutionStep__c step : [
      SELECT
        StepOrder__c,
        Status__c,
        StepType__c,
        StepDetail__c,
        DurationMilliseconds__c,
        AIDataSource__c,
        AIDataSource__r.DeveloperName__c,
        AIWorkflowAction__c,
        AIWorkflowAction__r.ActionName__c,
        ToolCallingIterationsUsed__c,
        ToolCallingIterationsMax__c,
        AttemptNumber__c,
        SentPreviewText__c,
        RequestJson__c,
        ResponseJson__c,
        PIIValuesMasked__c
      FROM AIExecutionStep__c
      WHERE AIConversationMessage__c = :reply.Id
      WITH SYSTEM_MODE
      ORDER BY StepOrder__c
    ]) {
      debugTrace.steps.add(AIChatConversationService.toExecutionStep(step));
      if (step.AIDataSource__c != null)
        debugTrace.toolCalls++;
      if (
        step.Status__c ==
        AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED
      )
        debugTrace.isSuccess = false;
      if (step.PIIValuesMasked__c != null)
        debugTrace.piiFieldsMasked += step.PIIValuesMasked__c.intValue();

      // Every step of a reply carries the same iteration and attempt figures; only the last provider call carries the payloads.
      if (step.ToolCallingIterationsUsed__c != null)
        debugTrace.toolCallingIterationsUsed = step.ToolCallingIterationsUsed__c.intValue();
      if (step.ToolCallingIterationsMax__c != null)
        debugTrace.toolCallingIterationsMax = step.ToolCallingIterationsMax__c.intValue();
      if (step.AttemptNumber__c != null)
        debugTrace.attemptNumber = step.AttemptNumber__c.intValue();
      if (String.isNotBlank(step.RequestJson__c))
        debugTrace.requestJson = step.RequestJson__c;
      if (String.isNotBlank(step.ResponseJson__c))
        debugTrace.responseJson = step.ResponseJson__c;
      if (String.isNotBlank(step.SentPreviewText__c))
        debugTrace.sentPreviewText = step.SentPreviewText__c;
    }

    return debugTrace;
  }

  // The log reference to quote to an administrator and, with debug mode, the detail recorded on the failed turn's System message.
  public static AIChatDataStructure.FailureDetail getFailureDetail(
    Id conversationId,
    Boolean includeDebugDetail
  ) {
    AIChatDataStructure.FailureDetail failureDetail = new AIChatDataStructure.FailureDetail();
    Datetime windowStart = System.now().addMinutes(-15);

    List<AIPlatformLog__c> recentLogs = [
      SELECT Name
      FROM AIPlatformLog__c
      WHERE User__c = :UserInfo.getUserId() AND CreatedDate >= :windowStart
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    failureDetail.reference = recentLogs.isEmpty() ? null : recentLogs[0].Name;

    if (includeDebugDetail) {
      // A System message from before the newest user message belongs to an earlier turn and would mislead.
      List<AIConversationMessage__c> latestUserMessages = [
        SELECT CreatedDate
        FROM AIConversationMessage__c
        WHERE
          AIConversation__c = :conversationId
          AND Sender__c = :AIAssistApplicationConstants.SENDER_USER
        WITH SYSTEM_MODE
        ORDER BY CreatedDate DESC, Id DESC
        LIMIT 1
      ];
      Datetime turnStartedAt = latestUserMessages.isEmpty()
        ? Datetime.newInstance(1970, 1, 1)
        : latestUserMessages[0].CreatedDate;

      List<AIConversationMessage__c> failedTurns = [
        SELECT MessageBody__c
        FROM AIConversationMessage__c
        WHERE
          AIConversation__c = :conversationId
          AND Sender__c = :AIAssistApplicationConstants.SENDER_SYSTEM
          AND CreatedDate >= :turnStartedAt
        WITH SYSTEM_MODE
        ORDER BY CreatedDate DESC, Id DESC
        LIMIT 1
      ];

      if (!failedTurns.isEmpty())
        failureDetail.debugDetail = failedTurns[0].MessageBody__c;
    }

    return failureDetail;
  }

  // Fake value to real value from the conversation's mapping. Empty when nothing was masked.
  public static Map<String, String> getRealValueByFakeValue(Id conversationId) {
    Map<String, String> realValueByFakeValue = new Map<String, String>();
    Map<String, String> fakeValueByRealValue = AIPiiMappingService.getMapping(
      conversationId
    );

    for (String realValue : fakeValueByRealValue.keySet())
      realValueByFakeValue.put(fakeValueByRealValue.get(realValue), realValue);

    return realValueByFakeValue;
  }

  // Swaps each fake value in a reply back to its real value, longest first so "Morgan Reyes" is replaced whole before "Morgan".
  public static String restorePii(
    String text,
    Map<String, String> realValueByFakeValue
  ) {
    if (
      String.isBlank(text) ||
      realValueByFakeValue == null ||
      realValueByFakeValue.isEmpty()
    )
      return text;

    List<String> fakeValues = new List<String>(realValueByFakeValue.keySet());
    fakeValues.sort(new LongestFirst());

    String restored = text;
    for (String fakeValue : fakeValues) {
      if (String.isNotBlank(fakeValue))
        restored = restored.replace(
          fakeValue,
          realValueByFakeValue.get(fakeValue)
        );
    }

    return restored;
  }

  private class LongestFirst implements Comparator<String> {
    public Integer compare(String first, String second) {
      return second.length() - first.length();
    }
  }
}
