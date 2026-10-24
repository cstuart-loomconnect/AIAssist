/*
Component Name: aiToolsWaWizard

=================================================================
=================================================================

Description: The wizard that creates and changes a workflow action in six steps.

Step 1: Load the action to change, or the draft of a new one kept in the browser
Step 2: Show the step the admin is on, and keep what each step reports in one draft
Step 3: Keep the draft of a new action in the browser as it changes
Step 4: Save the action, asking first when agents already use it, and tell the panel when the wizard closes

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import LightningConfirm from "lightning/confirm";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getAction from "@salesforce/apex/AIToolsWorkflowActionController.getAction";
import getFlowVariables from "@salesforce/apex/AIToolsWorkflowActionController.getFlowVariables";
import saveAction from "@salesforce/apex/AIToolsWorkflowActionController.saveAction";
import { STEP_TYPE, STEP_SOURCE, STEP_INPUTS, STEP_CONFIRMATION, STEP_TEST, STEP_DETAILS, ACTION_TYPE_APEX, NEW_DRAFT, TEST_STATUS_NONE, TEST_INVALIDATING_KEYS, PILL_DRAFT_CLASS, PILL_TYPE_CLASS, OLD_DRAFT_STORAGE_KEY, TOAST_VARIANT_SUCCESS, TOAST_VARIANT_ERROR, CONFIRM_VARIANT, NO_TEXT, LABELS } from "./aiToolsWaWizardSettings";
import { buildActionDetail, buildDraftFromDetail, buildStepViews, getTypePillLabel, isStepValid, formatErrorMessage } from "./aiToolsWaWizardHelper";

// The wizard. It holds one draft, and each step shows part of it and reports changes to it.
export default class AiToolsWaWizard extends LightningElement {

  // Values passed in by the parent component
  @api actionId = null; // The action to change, or blank to start a new one

  // Values the template reads
  labels = LABELS;

  // State of the wizard
  draft = { ...NEW_DRAFT, inputs: [], outputs: [] };
  step = STEP_TYPE;
  maxStep = STEP_TYPE;
  isLoading = false;
  isSaving = false;
  isDirty = false;
  errorMessage = NO_TEXT;

  // Lifecycle methods
  connectedCallback() {

    // [1] Change the saved action, or start a new one
    if (this.actionId) this.loadAction();

    // [2] Remove a draft that an earlier version kept in the browser, because drafts now live only on the page
    this.forgetOldBrowserDraft();
  }

  forgetOldBrowserDraft() {

    // [1] A browser that refuses is ignored
    try {

      window.localStorage.removeItem(OLD_DRAFT_STORAGE_KEY);

    } catch {

      // Nothing was kept, so there is nothing to remove.
    }
  }

  get isNewAction() {

    // [1] A new action has no id yet
    const isNewAction = !this.draft.actionId;

    return isNewAction;
  }

  get isStepType() {

    return this.step === STEP_TYPE;
  }

  get isStepSource() {

    return this.step === STEP_SOURCE;
  }

  get isStepInputs() {

    return this.step === STEP_INPUTS;
  }

  get isStepConfirmation() {

    return this.step === STEP_CONFIRMATION;
  }

  get isStepTest() {

    return this.step === STEP_TEST;
  }

  get isStepDetails() {

    return this.step === STEP_DETAILS;
  }

  get stepViews() {

    // [1] Hand the work to the helper
    const stepViews = buildStepViews(this.draft, this.step, this.maxStep);

    return stepViews;
  }

  get titleText() {

    // [1] The action's name when it has one, otherwise what it runs, otherwise a fixed title
    const titleText = this.draft.actionName || this.draft.sourceLabel || LABELS.newTitle;

    return titleText;
  }

  get pillLabel() {

    // [1] A new action on the first step is a draft; after that the pill says what it runs
    const isDraftPill = this.isNewAction && this.step === STEP_TYPE;
    const pillLabel = isDraftPill ? LABELS.draftPill : getTypePillLabel(this.draft.actionType);

    return pillLabel;
  }

  get pillClass() {

    // [1] The draft pill is orange and the type pill is blue
    const isDraftPill = this.isNewAction && this.step === STEP_TYPE;
    const pillClass = isDraftPill ? PILL_DRAFT_CLASS : PILL_TYPE_CLASS;

    return pillClass;
  }

  get statusText() {

    // [1] A new action is autosaved; a saved one is only saved on Save
    const statusText = this.isNewAction ? LABELS.draftSaved : LABELS.editing;

    return statusText;
  }

  get hasBack() {

    // [1] Every step after the first can go back
    const hasBack = this.step > STEP_TYPE;

    return hasBack;
  }

  get isLastStep() {

    // [1] The details step saves instead of going on
    const isLastStep = this.step === STEP_DETAILS;

    return isLastStep;
  }

  get isNextDisabled() {

    // [1] The next step is not available until this one is complete
    const isNextDisabled = !isStepValid(this.draft, this.step);

    return isNextDisabled;
  }

  get isSaveDisabled() {

    // [1] Saving needs every step complete, and one save at a time
    const isIncomplete = [STEP_SOURCE, STEP_INPUTS, STEP_CONFIRMATION, STEP_DETAILS].some((stepNumber) => !isStepValid(this.draft, stepNumber));
    const isSaveDisabled = isIncomplete || this.isSaving;

    return isSaveDisabled;
  }

  get hasError() {

    // [1] There is an error to show when the last save failed
    const hasError = Boolean(this.errorMessage);

    return hasError;
  }

  get actionDetail() {

    // [1] The action as it is now, for the steps that test it
    const actionDetail = buildActionDetail(this.draft);

    return actionDetail;
  }

  // Event handlers
  handleDraftChange(event) {

    // [1] Take what the step reported
    const changes = event.detail.changes;
    const isTestResult = Object.prototype.hasOwnProperty.call(changes, "lastTestStatus");
    const changesWhatItDoes = TEST_INVALIDATING_KEYS.some((key) => Object.prototype.hasOwnProperty.call(changes, key));

    // [2] Anything that changes what the action does makes the last test out of date
    const testReset = changesWhatItDoes && !isTestResult ? { lastTestStatus: TEST_STATUS_NONE } : {};
    this.draft = { ...this.draft, ...testReset, ...changes };
    this.isDirty = true;
    this.errorMessage = NO_TEXT;

    // [3] Keep a new action's draft in the browser
  }

  handleStepClick(event) {

    // [1] Go to a step the admin has already reached
    const stepNumber = Number(event.currentTarget.dataset.step);
    if (stepNumber <= this.maxStep) this.step = stepNumber;
  }

  handleBack() {

    // [1] Go to the step before
    this.step = this.step - 1;
  }

  handleNext() {

    // [1] Go to the step after, and remember how far the admin has got
    this.step = this.step + 1;
    this.maxStep = Math.max(this.maxStep, this.step);
  }

  async handleCancel() {

    // [1] Ask first when there is something to lose
    if (this.isDirty) {

      const confirmOptions = { message: LABELS.discardMessage, label: LABELS.discardTitle, variant: CONFIRM_VARIANT };
      const isConfirmed = await LightningConfirm.open(confirmOptions);
      if (!isConfirmed) return;
    }

    // [2] Forget the draft and close
    this.closeWizard(false);
  }

  async handleSave() {

    // [1] Ask first when agents already use the action, because the change is live as soon as it is saved
    if (!this.isNewAction && this.draft.agentCount > 0) {

      const countText = this.draft.agentCount + (this.draft.agentCount === 1 ? LABELS.saveMessageOne : LABELS.saveMessageMany);
      const confirmOptions = { message: LABELS.saveMessagePrefix + countText + LABELS.saveMessageSuffix, label: LABELS.saveTitle, variant: CONFIRM_VARIANT };
      const isConfirmed = await LightningConfirm.open(confirmOptions);
      if (!isConfirmed) return;
    }

    this.isSaving = true;
    this.errorMessage = NO_TEXT;

    try {

      // [2] Save the action
      const detail = buildActionDetail(this.draft);
      await saveAction({ actionDetail: detail });

      // [3] Forget the draft, say so and close
      this.showToast(LABELS.saved, TOAST_VARIANT_SUCCESS);
      this.closeWizard(true);

    } catch (error) {

      // [4] Show the reason above the buttons
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isSaving = false;
    }
  }

  // Private methods
  async loadAction() {

    this.isLoading = true;

    try {

      // [1] Read the action, and the variables of its flow
      const detail = await getAction({ actionId: this.actionId });
      const isApex = detail.actionType === ACTION_TYPE_APEX;
      const variables = isApex || !detail.flowApiName ? [] : await getFlowVariables({ flowApiName: detail.flowApiName });

      // [2] Build the draft, and let the admin go to any step
      this.draft = buildDraftFromDetail(detail, variables);
      this.maxStep = STEP_DETAILS;

    } catch (error) {

      // [3] Show the reason
      this.showToast(formatErrorMessage(error), TOAST_VARIANT_ERROR);
      this.closeWizard(false);

    } finally {

      this.isLoading = false;
    }
  }

  closeWizard(hasSaved) {

    // [1] Tell the panel, which goes back to the list
    const closeEvent = new CustomEvent("close", { detail: { saved: hasSaved } });
    this.dispatchEvent(closeEvent);
  }

  showToast(message, variant) {

    // [1] Show the message at the top of the page
    const toastEvent = new ShowToastEvent({ message, variant });
    this.dispatchEvent(toastEvent);
  }
}
