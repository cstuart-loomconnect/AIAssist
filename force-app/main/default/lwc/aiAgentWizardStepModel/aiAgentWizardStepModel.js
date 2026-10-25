/*
Component Name: aiAgentWizardStepModel

=================================================================
=================================================================

Description: Step 2 of the AI Agent Wizard: pick the model configuration and check that it connects.

Step 1: Show the active models and pick one for a new agent
Step 2: Check the connection of the model that is picked
Step 3: Tell the tab what changed, and what the check found
Step 4: Offer to skip the step when there is no model

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import testModel from "@salesforce/apex/AIAgentWizardController.testModel";
import { STATUS_OK_CLASS, STATUS_FAILED_CLASS, STATUS_WAITING_CLASS, NO_TEXT, LABELS } from "./aiAgentWizardStepModelSettings";
import { findMostUsedModel, buildModelViews, formatTestText, formatErrorMessage } from "./aiAgentWizardStepModelHelper";

// Step 2. It shows the models and reports the pick and the connection check to the tab.
export default class AiAgentWizardStepModel extends LightningElement {

  // Values passed in by the parent component
  @api draft; // The tab's draft: modelConfigurationId is read here
  @api models = []; // [AIAgentWizardDataStructure.ModelOption]
  @api modelTest = null; // The last connection check the tab kept: { modelId, isSuccessful, text }

  // Values the template reads
  labels = LABELS;

  // State of the step
  isTesting = false;
  testRunId = 0;

  // Lifecycle methods
  connectedCallback() {

    // [1] A new agent starts with the model most agents use
    const hasPick = Boolean(this.draft.modelConfigurationId);
    const mostUsed = findMostUsedModel(this.models);
    if (!hasPick && mostUsed) this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes: { modelConfigurationId: mostUsed.modelId } } }));

    // [2] Check the connection of the model, unless it was checked already
    const modelId = hasPick ? this.draft.modelConfigurationId : mostUsed ? mostUsed.modelId : null;
    const isChecked = this.modelTest && this.modelTest.modelId === modelId;
    if (modelId && !isChecked) this.runTest(modelId);
  }

  get hasModels() {

    // [1] There is something to pick
    const hasModels = this.models && this.models.length > 0;

    return hasModels;
  }

  get modelViews() {

    // [1] Hand the work to the helper
    const modelViews = buildModelViews(this.models, this.draft.modelConfigurationId);

    return modelViews;
  }

  get isCurrentTest() {

    // [1] The kept check belongs to the model that is picked
    const isCurrentTest = Boolean(this.modelTest) && this.modelTest.modelId === this.draft.modelConfigurationId;

    return isCurrentTest;
  }

  get showTest() {

    // [1] The box shows when a model is picked
    const showTest = Boolean(this.draft.modelConfigurationId);

    return showTest;
  }

  get statusLabel() {

    // [1] Testing, connected, failed or not tested
    if (this.isTesting) return LABELS.testing;
    if (!this.isCurrentTest) return LABELS.notTested;

    return this.modelTest.isSuccessful ? LABELS.connected : LABELS.failed;
  }

  get statusClass() {

    // [1] Green when connected, red when failed
    if (this.isTesting || !this.isCurrentTest) return STATUS_WAITING_CLASS;

    return this.modelTest.isSuccessful ? STATUS_OK_CLASS : STATUS_FAILED_CLASS;
  }

  get statusText() {

    // [1] What the check found
    const statusText = this.isCurrentTest && !this.isTesting ? this.modelTest.text : NO_TEXT;

    return statusText;
  }

  // Event handlers
  handleModelChange(event) {

    // [1] Keep the model that was picked, and check its connection
    const modelId = event.currentTarget.dataset.key;
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes: { modelConfigurationId: modelId } } }));
    this.runTest(modelId);
  }

  handleTestAgain() {

    // [1] Check the connection of the model that is picked
    this.runTest(this.draft.modelConfigurationId);
  }

  handleSkip() {

    // [1] Tell the tab to go on without a model
    this.dispatchEvent(new CustomEvent("next"));
  }

  // Private methods
  async runTest(modelId) {

    // [1] Note which check this is, so a slow answer to an old check is ignored
    this.testRunId = this.testRunId + 1;
    const runId = this.testRunId;
    this.isTesting = true;

    try {

      // [2] Ask Apex to send a test message through the model
      const result = await testModel({ modelId });
      if (runId !== this.testRunId) return;
      const detail = { modelId, isSuccessful: Boolean(result.isSuccessful), text: formatTestText(result) };
      this.dispatchEvent(new CustomEvent("modeltest", { detail }));

    } catch (error) {

      // [3] A refusal counts as a failed check
      if (runId !== this.testRunId) return;
      const detail = { modelId, isSuccessful: false, text: formatErrorMessage(error) };
      this.dispatchEvent(new CustomEvent("modeltest", { detail }));

    } finally {

      if (runId === this.testRunId) this.isTesting = false;
    }
  }
}
