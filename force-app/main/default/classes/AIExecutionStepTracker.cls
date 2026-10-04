/*
Class Name: AIExecutionStepTracker

=================================================================
=================================================================

Description: The in-memory record of one turn: each timed phase (a data source read, a provider
call), the iteration and attempt counts, and what was sent to the provider. It never touches the
database; AIExecutionStepRecorder turns it into AIExecutionStep__c and AIPIIMaskingRecord__c
rows once the reply exists.

Every phase is recorded, because the steps are audit evidence of what the AI was given and what
it did, not debugging aids. Only the request and response payloads depend on the user's debug
mode (captureFullDetail), since they hold customer data.

A step carries what the object model asks to be proved: for a provider call, the provider and
model, how many records and fields were sent, the object and field names (never values), and
which fields were masked and how.

If live progress is on, starting a phase also publishes its label for the chat window.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Every phase recorded, not only data sources. Provider and masking evidence added. endPhase returns the step so the caller can complete it.
*/

public inherited sharing class AIExecutionStepTracker {
  // One field that was masked, with how many values.
  public class MaskingEntry {
    public String sourceObject;
    public String sourceField;
    public String piiFieldType;
    public String complianceGroup;
    public String maskingStrategy;
    public Decimal valuesMasked;
    public String outcome;
  }

  public class StepEntry {
    public String stepType;
    public Id dataSourceId;
    public Id workflowActionId;
    public Long durationMilliseconds;
    public Boolean isSuccess = true;
    public String status;
    public String provider;
    public String modelIdentifier;
    public Decimal recordsSentCount;
    public Decimal fieldsSentCount;
    public String objectsSent;
    public String fieldsSent;
    public Boolean piiMaskingApplied = false;
    public String targetObject;
    public String targetRecordId;
    public Boolean requiredConfirmation = false;
    public Id confirmedBy;
    public Datetime confirmedDate;
    public List<MaskingEntry> maskingEntries = new List<MaskingEntry>();
  }

  private final Id conversationId;
  private final Id userMessageId;
  private final Boolean showLiveProgress;

  // True when AIAssistSettings__c.StepCaptureMode__c is Full: gates the request and response payloads and the sent preview.
  public final Boolean captureFullDetail;

  public List<StepEntry> steps = new List<StepEntry>();
  public String sentPreviewText;
  public String lastRequestJson;
  public String lastResponseJson;
  public Integer toolCallingIterationsUsed = 0;
  public Integer toolCallingIterationsMax = 0;
  public Integer attemptNumber = 1;

  private Long phaseStartedAtMillis;
  private Id phaseDataSourceId;

  public AIExecutionStepTracker(
    Id conversationId,
    Id userMessageId,
    Boolean showLiveProgress,
    Boolean captureFullDetail
  ) {
    this.conversationId = conversationId;
    this.userMessageId = userMessageId;
    this.showLiveProgress = showLiveProgress == true;
    this.captureFullDetail = captureFullDetail == true;
  }

  // Starts timing a phase: a data source read (dataSourceId set) or a provider call (dataSourceId null).
  public void startStep(String liveLabel, Id dataSourceId) {
    phaseStartedAtMillis = System.currentTimeMillis();
    phaseDataSourceId = dataSourceId;

    if (showLiveProgress)
      AIAgentProgressPublisher.publishStep(
        conversationId,
        userMessageId,
        liveLabel
      );
  }

  // Ends the phase started by startPhase and returns its step, so a provider call can be completed with what was sent. Null if no phase was started.
  public StepEntry endStep(Boolean isSuccess) {
    if (phaseStartedAtMillis == null)
      return null;

    StepEntry entry = new StepEntry();
    entry.stepType = phaseDataSourceId != null
      ? AIAssistApplicationConstants.STEP_TYPE_DATA_SOURCE
      : AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL;
    entry.dataSourceId = phaseDataSourceId;
    entry.durationMilliseconds =
      System.currentTimeMillis() - phaseStartedAtMillis;
    entry.isSuccess = isSuccess != false;
    steps.add(entry);

    phaseStartedAtMillis = null;
    phaseDataSourceId = null;

    return entry;
  }

  // Records what was masked before the data went to the provider, against the step that sent it.
  public void addMaskingTallies(
    StepEntry step,
    List<AIPiiPseudonymizationService.MaskingTally> tallies
  ) {
    if (step == null || tallies == null || tallies.isEmpty())
      return;

    step.piiMaskingApplied = true;

    for (AIPiiPseudonymizationService.MaskingTally tally : tallies) {
      MaskingEntry entry = new MaskingEntry();
      entry.sourceObject = tally.sourceObject;
      entry.sourceField = tally.sourceField;
      entry.piiFieldType = tally.piiFieldType;
      entry.complianceGroup = tally.complianceGroup;
      entry.maskingStrategy = tally.maskingStrategy;
      entry.valuesMasked = tally.valuesMasked;
      entry.outcome = tally.outcome;
      step.maskingEntries.add(entry);
    }
  }
}
