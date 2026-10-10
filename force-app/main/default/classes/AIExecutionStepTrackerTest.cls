/*
Class Name: AIExecutionStepTrackerTest

=================================================================
=================================================================

Description: Testing utility for AIExecutionStepTracker: the in-memory record of the phases of one turn and the evidence of what was sent.

=================================================================
=================================================================
Applicable Classes:

AIExecutionStepTracker: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIExecutionStepTrackerTest {

    // testScenario1: A data source phase and a provider phase are each ended -> each becomes a timed, typed step, in the order they ended.
    // testScenario2: Ending a phase that was never started -> nothing is recorded and null is returned.
    // testScenario3: addMaskingTallies is called with a step, a null step and null tallies -> the step is flagged and each tally is copied as a masking entry, and the null calls add nothing.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent, a data source and a tracker
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, null, true)[0];

            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true)[0];

            AIExecutionStepTracker tracker = new AIExecutionStepTracker(null, null, false, false);

            AIExecutionStepTracker.StepEntry dataSourceStep;
            AIExecutionStepTracker.StepEntry providerStep;

            // [2] End a data source phase and a provider phase
            Test.startTest();
                tracker.startStep('Reading', dataSource.Id);
                dataSourceStep = tracker.endStep(true);
                tracker.startStep('Thinking', null);
                providerStep = tracker.endStep(false);
            Test.stopTest();

            // [3] Check both are recorded as timed, typed steps
            Assert.areEqual(2, tracker.steps.size(), 'Both phases are recorded, whether or not debug mode is on.');
            Assert.areEqual(AIAssistApplicationConstants.STEP_TYPE_DATA_SOURCE, dataSourceStep.stepType, 'A phase with a data source is a data source step.');
            Assert.areEqual(dataSource.Id, dataSourceStep.dataSourceId, 'It names the data source.');

            Assert.areEqual(AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL, providerStep.stepType, 'A phase with none is the provider call.');
            Assert.isFalse(providerStep.isSuccess, 'The failure is recorded.');
            Assert.isTrue(dataSourceStep.durationMilliseconds >= 0, 'Each phase is timed.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a tracker
            AIExecutionStepTracker tracker = new AIExecutionStepTracker(null, null, false, false);
            AIExecutionStepTracker.StepEntry step;

            // [2] End a phase that was never started
            Test.startTest();
                step = tracker.endStep(true);
            Test.stopTest();

            // [3] Check nothing is recorded and null is returned
            Assert.isNull(step, 'No phase, no step.');
            Assert.isTrue(tracker.steps.isEmpty(), 'Nothing is recorded.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a tracker and end one step
            AIExecutionStepTracker tracker = new AIExecutionStepTracker(null, null, false, false);
            tracker.startStep('Thinking', null);
            AIExecutionStepTracker.StepEntry step = tracker.endStep(true);

            // [2] Build a masking tally
            AIPiiPseudonymizationService.MaskingTally tally = new AIPiiPseudonymizationService.MaskingTally();
            tally.sourceObject = 'Contact';
            tally.sourceField = 'Email';
            tally.piiFieldType = AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL;
            tally.complianceGroup = 'GDPR';
            tally.maskingStrategy = AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST;
            tally.valuesMasked = 3;

            // [3] Add the tally to the step, then add with a null step and null tallies
            Test.startTest();
                tracker.addMaskingTallies(step, new List<AIPiiPseudonymizationService.MaskingTally>{ tally });
                tracker.addMaskingTallies(null, new List<AIPiiPseudonymizationService.MaskingTally>{ tally });
                tracker.addMaskingTallies(step, null);
            Test.stopTest();

            // [4] Check the step is flagged and holds one masking entry
            Assert.isTrue(step.piiMaskingApplied, 'The step is flagged as masked.');
            Assert.areEqual(1, step.maskingEntries.size(), 'One entry per tally, and the null calls added nothing.');
            Assert.areEqual('Email', step.maskingEntries[0].sourceField, 'The field.');
            Assert.areEqual(3, step.maskingEntries[0].valuesMasked, 'The count.');
            Assert.areEqual('GDPR', step.maskingEntries[0].complianceGroup, 'The compliance group.');
        }
    }
}
