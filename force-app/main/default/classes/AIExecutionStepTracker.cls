/*
Class Name: AIExecutionStepTracker

=================================================================
=================================================================

Description: Holds the in-memory record of one turn: each timed phase, the attempt and iteration counts, and what was sent to the provider.

Step 1: Start timing a phase (a data source read or a provider call)
Step 2: End the phase and keep it as a typed, timed step
Step 3: Add what was masked to the step that sent the data
Step 4: Hand the tracker to AIExecutionStepRecorder, which saves it once the reply exists

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIExecutionStepTracker {
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
    this.captureFullDetail = captureFullDetail == true;
  }

  // Starts timing a phase: a data source read (dataSourceId set) or a provider call (dataSourceId null).
  public void startStep(String liveLabel, Id dataSourceId) {
    // [1] Remember when the phase started and which data source it reads
    phaseStartedAtMillis = System.currentTimeMillis();
    phaseDataSourceId = dataSourceId;
  }

  // Ends the phase started by startStep and returns its step, so a provider call can be completed with what was sent. Null if no phase was started.
  public StepEntry endStep(Boolean isSuccess) {
    // [1] Nothing to end when no phase was started
    if (phaseStartedAtMillis == null)
      return null;

    // [2] Build the step: a data source step when the phase named a source, a provider call otherwise
    StepEntry entry = new StepEntry();
    entry.stepType = phaseDataSourceId != null
      ? AIAssistApplicationConstants.STEP_TYPE_DATA_SOURCE
      : AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL;
    entry.dataSourceId = phaseDataSourceId;
    entry.durationMilliseconds =
      System.currentTimeMillis() - phaseStartedAtMillis;
    entry.isSuccess = isSuccess != false;
    steps.add(entry);

    // [3] Clear the phase so the next one starts fresh
    phaseStartedAtMillis = null;
    phaseDataSourceId = null;

    return entry;
  }

  // Records what was masked before the data went to the provider, against the step that sent it.
  public void addMaskingTallies(
    StepEntry step,
    List<AIPiiPseudonymizationService.MaskingTally> tallies
  ) {
    // [1] Nothing to record without a step or any tallies
    if (step == null || tallies == null || tallies.isEmpty())
      return;

    // [2] Flag the step as masked
    step.piiMaskingApplied = true;

    // [3] Copy each tally onto the step as a masking entry
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
