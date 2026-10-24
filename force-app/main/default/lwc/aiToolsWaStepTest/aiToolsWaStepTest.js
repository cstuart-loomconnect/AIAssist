/*
Component Name: aiToolsWaStepTest

=================================================================
=================================================================

Description: Step 5 of the workflow action wizard: run the action once, undo it, and see what came back.

Step 1: Show a field for the record and for each input the agent fills in
Step 2: Run the test on the server, rolled back unless the admin switched that off in a sandbox
Step 3: Show how it ended, what it returned and anything it could not undo
Step 4: Tell the wizard how the test ended, so it is saved with the action

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import runTest from "@salesforce/apex/AIToolsWorkflowActionController.runTest";
import { ACTION_TYPE_SCREEN_FLOW, NO_TEXT, LABELS } from "./aiToolsWaStepTestSettings";
import { hasPageInput, buildFieldViews, readFieldValue, buildResultText, getBannerClass, formatErrorMessage } from "./aiToolsWaStepTestHelper";

// Step 5. It runs the action as it is in the wizard and reports how it ended.
export default class AiToolsWaStepTest extends LightningElement {

  // Values passed in by the parent component
  @api draft; // The wizard's draft: inputs, actionType and targetObject are read here
  @api actionDetail; // The action as the wizard would save it, which the test runs

  // Values the template reads
  labels = LABELS;

  // State of the step
  recordId = NO_TEXT;
  inputValues = {};
  shouldRollBack = true;
  isRunning = false;
  result = null;
  errorMessage = NO_TEXT;

  get isScreenFlow() {

    // [1] A screen flow cannot be tested on the server
    const isScreenFlow = this.draft.actionType === ACTION_TYPE_SCREEN_FLOW;

    return isScreenFlow;
  }

  get showRecord() {

    // [1] Ask for a record when the open record fills an input
    const showRecord = hasPageInput(this.draft.inputs);

    return showRecord;
  }

  get hasNoInputs() {

    // [1] Say so when there is no record to pick and no value to type
    const hasNoInputs = !this.showRecord && this.fieldViews.length === 0;

    return hasNoInputs;
  }

  get hasTargetObject() {

    // [1] A record can be picked when the admin said which object it belongs to
    const hasTargetObject = Boolean(this.draft.targetObject);

    return hasTargetObject;
  }

  get fieldViews() {

    // [1] Hand the work to the helper
    const fieldViews = buildFieldViews(this.draft.inputs);

    return fieldViews;
  }

  get hasResult() {

    // [1] There is a result once a test has run
    const hasResult = this.result !== null;

    return hasResult;
  }

  get resultText() {

    // [1] Hand the work to the helper
    const resultText = this.hasResult ? buildResultText(this.result) : NO_TEXT;

    return resultText;
  }

  get bannerClass() {

    // [1] Hand the work to the helper
    const bannerClass = this.hasResult ? getBannerClass(this.result) : NO_TEXT;

    return bannerClass;
  }

  get hasOutputs() {

    // [1] There are outputs to show when the test returned some
    const hasOutputs = this.hasResult && this.result.outputs.length > 0;

    return hasOutputs;
  }

  get hasWarnings() {

    // [1] There are warnings when something could not be undone
    const hasWarnings = this.hasResult && this.result.warnings.length > 0;

    return hasWarnings;
  }

  get hasError() {

    // [1] There is an error to show when the test was refused
    const hasError = Boolean(this.errorMessage);

    return hasError;
  }

  // Event handlers
  handleRecordChange(event) {

    // [1] Keep the record the admin picked or typed
    this.recordId = event.detail && event.detail.recordId !== undefined ? event.detail.recordId : event.target.value;
  }

  handleValueChange(event) {

    // [1] Keep the value typed for one input
    const name = event.currentTarget.dataset.name;
    const fieldType = event.currentTarget.dataset.type;
    this.inputValues = { ...this.inputValues, [name]: readFieldValue(event, fieldType) };
  }

  handleRollBackChange(event) {

    // [1] Keep the admin's choice
    this.shouldRollBack = event.target.checked;
  }

  async handleRunTest() {

    this.isRunning = true;
    this.errorMessage = NO_TEXT;

    try {

      // [1] Run the action as it is in the wizard
      const detail = JSON.parse(JSON.stringify(this.actionDetail));
      const inputValues = JSON.parse(JSON.stringify(this.inputValues));
      const request = { recordId: this.recordId || null, inputValues, shouldRollBack: this.shouldRollBack };
      this.result = await runTest({ actionDetail: detail, testRequest: request });

      // [2] Tell the wizard how it ended
      this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes: { lastTestStatus: this.result.status } } }));

    } catch (error) {

      // [3] Show why it was refused
      this.result = null;
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isRunning = false;
    }
  }
}
