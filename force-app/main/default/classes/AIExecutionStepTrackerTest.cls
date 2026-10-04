/*
Class Name: AIExecutionStepTrackerTest

=================================================================
=================================================================

Description: Testing utility for AIExecutionStepTracker: the in-memory record of the phases of one turn and the evidence of what was sent.

=================================================================
=================================================================
Applicable Classes:

AIExecutionStepTracker

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIExecutionStepTrackerTest {
  // testScenario1: A data source phase and a provider phase each become a timed, typed step, in the order they ended.
  // testScenario2: Ending a phase that was never started records nothing and returns null.
  // testScenario3: addMasking flags the step and copies each tally as a masking entry, and ignores a null step or no tallies.
  // testScenario4: Live progress is published only when it is switched on, and debug detail is a flag the tracker simply holds.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    settings.IsEventNotificationEnabled__c = true; // Events are optional and off by default; these tests are about the events.
    upsert settings;
  }

  @IsTest
  static void testScenario1() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(
      1,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      true
    )[0];
    AIExecutionStepTracker tracker = new AIExecutionStepTracker(
      null,
      null,
      false,
      false
    );

    Test.startTest();
    tracker.startStep('Reading', dataSource.Id);
    AIExecutionStepTracker.StepEntry dataSourceStep = tracker.endStep(true);
    tracker.startStep('Thinking', null);
    AIExecutionStepTracker.StepEntry providerStep = tracker.endStep(false);
    Test.stopTest();

    Assert.areEqual(
      2,
      tracker.steps.size(),
      'Both phases are recorded, whether or not debug mode is on.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.STEP_TYPE_DATA_SOURCE,
      dataSourceStep.stepType,
      'A phase with a data source is a data source step.'
    );
    Assert.areEqual(
      dataSource.Id,
      dataSourceStep.dataSourceId,
      'It names the data source.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL,
      providerStep.stepType,
      'A phase with none is the provider call.'
    );
    Assert.isFalse(providerStep.isSuccess, 'The failure is recorded.');
    Assert.isTrue(
      dataSourceStep.durationMilliseconds >= 0,
      'Each phase is timed.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIExecutionStepTracker tracker = new AIExecutionStepTracker(
      null,
      null,
      false,
      false
    );

    Test.startTest();
    AIExecutionStepTracker.StepEntry step = tracker.endStep(true);
    Test.stopTest();

    Assert.isNull(step, 'No phase, no step.');
    Assert.isTrue(tracker.steps.isEmpty(), 'Nothing is recorded.');
  }

  @IsTest
  static void testScenario3() {
    AIExecutionStepTracker tracker = new AIExecutionStepTracker(
      null,
      null,
      false,
      false
    );
    tracker.startStep('Thinking', null);
    AIExecutionStepTracker.StepEntry step = tracker.endStep(true);

    AIPiiPseudonymizationService.MaskingTally tally = new AIPiiPseudonymizationService.MaskingTally();
    tally.sourceObject = 'Contact';
    tally.sourceField = 'Email';
    tally.piiFieldType = AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL;
    tally.complianceGroup = 'GDPR';
    tally.maskingStrategy = AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST;
    tally.valuesMasked = 3;

    Test.startTest();
    tracker.addMaskingTallies(
      step,
      new List<AIPiiPseudonymizationService.MaskingTally>{ tally }
    );
    tracker.addMaskingTallies(
      null,
      new List<AIPiiPseudonymizationService.MaskingTally>{ tally }
    );
    tracker.addMaskingTallies(step, null);
    Test.stopTest();

    Assert.isTrue(step.piiMaskingApplied, 'The step is flagged as masked.');
    Assert.areEqual(
      1,
      step.maskingEntries.size(),
      'One entry per tally, and the null calls added nothing.'
    );
    Assert.areEqual('Email', step.maskingEntries[0].sourceField, 'The field.');
    Assert.areEqual(3, step.maskingEntries[0].valuesMasked, 'The count.');
    Assert.areEqual(
      'GDPR',
      step.maskingEntries[0].complianceGroup,
      'The compliance group.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIConversationMessage__c message = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      null,
      1,
      true
    )[0];
    AIExecutionStepTracker silent = new AIExecutionStepTracker(
      conversation.Id,
      message.Id,
      false,
      false
    );
    AIExecutionStepTracker live = new AIExecutionStepTracker(
      conversation.Id,
      message.Id,
      true,
      true
    );
    Integer publishedBefore = Limits.getPublishImmediateDML();

    Test.startTest();
    silent.startStep('Thinking', null);
    Integer publishedBySilent =
      Limits.getPublishImmediateDML() - publishedBefore;
    live.startStep('Thinking', null);
    Integer publishedByLive = Limits.getPublishImmediateDML() - publishedBefore;
    Test.stopTest();

    Assert.areEqual(
      0,
      publishedBySilent,
      'No progress is published when it is switched off.'
    );
    Assert.areEqual(
      1,
      publishedByLive,
      'One progress event is published when it is on.'
    );
    Assert.isFalse(silent.captureFullDetail, 'Debug detail is off by default.');
    Assert.isTrue(live.captureFullDetail, 'And on when asked.');
  }
}
