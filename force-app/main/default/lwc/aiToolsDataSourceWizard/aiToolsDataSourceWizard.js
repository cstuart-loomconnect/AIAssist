/*
Component Name: aiToolsDataSourceWizard

=================================================================
=================================================================

Description: The wizard that builds, tests and changes one data source: Type, Query or Apex class, Inputs, Test and Details.

Step 1: Load the data source being changed, or the draft of a new one kept in the browser
Step 2: Show one step at a time and keep every change in one draft, autosaving a new one
Step 3: Test the data source and save it, asking first when agents use it
Step 4: Tell the tab when the wizard closes or has saved

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import LightningConfirm from "lightning/confirm";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getDataSourceDetail from "@salesforce/apex/AIToolsController.getDataSourceDetail";
import getAgentUses from "@salesforce/apex/AIToolsController.getAgentUses";
import saveDataSource from "@salesforce/apex/AIToolsController.saveDataSource";
import { STEP_TYPE, STEP_QUERY, STEP_INPUTS, STEP_TEST, STEP_DETAILS, LAST_STEP, SOURCE_TYPE_SOQL, SOURCE_TYPE_APEX, CONFIRM_VARIANT, TOAST_VARIANT_SUCCESS, TOAST_VARIANT_ERROR, NO_TEXT, PILL_DRAFT_CLASS, PILL_TYPE_CLASS, TEST_STATUS_FAILED, DEFINITION_KEYS, OLD_DRAFT_STORAGE_KEY, LABELS } from "./aiToolsDataSourceWizardSettings";
import { buildNewDraft, buildDraftFromDetail, buildDetailFromDraft, buildTestRequest, buildStepViews, isStepValid, addTestHistory, formatTestHistory, applyDraftChanges, formatErrorMessage } from "./aiToolsDataSourceWizardHelper";

// The data source wizard. It holds the draft, and each step shows and changes a part of it.
export default class AiToolsDataSourceWizard extends LightningElement {

  // The Id of the data source to change. Leave blank to build a new one.
  @api editId = null;

  // Values the template reads
  labels = LABELS;

  // State of the wizard
  draft = buildNewDraft();
  step = STEP_TYPE;
  testResult = null;
  agentUses = [];
  isBusy = true;
  isSaving = false;
  isDialogOpen = false;
  isDirty = false;
  errorMessage = NO_TEXT;

  // Lifecycle methods
  connectedCallback() {

    // [1] Load the data source, or the draft
    this.loadDraft();

    // [2] Remove a draft that an earlier version kept in the browser, because drafts now live only on the page
    this.forgetOldBrowserDraft();
  }

  get stepViews() {

    // [1] Hand the work to the helper
    const stepViews = buildStepViews(this.draft, this.step);

    return stepViews;
  }

  get isNew() {

    // [1] A new data source has no id
    const isNew = !this.draft.dataSourceId;

    return isNew;
  }

  get headerName() {

    // [1] The name once it is typed, or a plain name for a new data source
    const headerName = this.draft.sourceName || LABELS.newDataSource;

    return headerName;
  }

  get pillLabel() {

    // [1] A new data source is a draft until the type step is done, then it shows its type
    const isDraftStep = this.isNew && this.step === STEP_TYPE;
    const pillLabel = isDraftStep ? LABELS.draftPill : this.draft.sourceType;

    return pillLabel;
  }

  get pillClass() {

    // [1] The draft pill is orange, the type pill is blue
    const isDraftStep = this.isNew && this.step === STEP_TYPE;
    const pillClass = isDraftStep ? PILL_DRAFT_CLASS : PILL_TYPE_CLASS;

    return pillClass;
  }

  get statusText() {

    // [1] A new data source is a draft until it is saved; a saved one says it is being edited
    const statusText = this.isNew ? LABELS.draftSaved : LABELS.editing;

    return statusText;
  }

  get isTypeStep() {

    return this.step === STEP_TYPE;
  }

  get isSoqlStep() {

    // [1] The second step is the query for SOQL
    const isSoqlStep = this.step === STEP_QUERY && this.draft.sourceType === SOURCE_TYPE_SOQL;

    return isSoqlStep;
  }

  get isApexStep() {

    // [1] The second step is the class for Apex
    const isApexStep = this.step === STEP_QUERY && this.draft.sourceType === SOURCE_TYPE_APEX;

    return isApexStep;
  }

  get isInputsStep() {

    return this.step === STEP_INPUTS;
  }

  get isTestStep() {

    return this.step === STEP_TEST;
  }

  get isDetailsStep() {

    return this.step === STEP_DETAILS;
  }

  get showBack() {

    // [1] Every step after the first can go back
    const showBack = this.step > STEP_TYPE;

    return showBack;
  }

  get isLastStep() {

    return this.step === LAST_STEP;
  }

  get isNextDisabled() {

    // [1] The step must be complete
    const isNextDisabled = !isStepValid(this.step, this.draft);

    return isNextDisabled;
  }

  get isSaveDisabled() {

    // [1] The details must be complete, and a save must not be running
    const isSaveDisabled = this.isSaving || !isStepValid(STEP_DETAILS, this.draft) || !isStepValid(STEP_QUERY, this.draft) || !isStepValid(STEP_INPUTS, this.draft);

    return isSaveDisabled;
  }

  get saveLabel() {

    // [1] A new data source is saved, a changed one has its changes saved
    const saveLabel = this.isNew ? LABELS.save : LABELS.saveChanges;

    return saveLabel;
  }

  get hasError() {

    // [1] Show the box only when there is a message
    const hasError = Boolean(this.errorMessage);

    return hasError;
  }

  get testDetail() {

    // [1] The data source as it is now, for the Test step to run
    const testDetail = buildDetailFromDraft(this.draft);

    return testDetail;
  }

  get testFailureMessage() {

    // [1] The reason the last test failed, so the Details step can show it
    const isFailed = this.testResult && this.testResult.status === TEST_STATUS_FAILED;
    const testFailureMessage = isFailed ? this.testResult.message : NO_TEXT;

    return testFailureMessage;
  }

  get testHistoryParts() {

    // [1] Hand the work to the helper
    const testHistoryParts = formatTestHistory(this.draft.testHistory);

    return testHistoryParts;
  }

  // Event handlers
  handleDraftChange(event) {

    // [1] A result belongs to the data source as it was tested, so a change to the data source throws it away
    const changes = event.detail.changes;
    const changesDefinition = DEFINITION_KEYS.some((key) => changes[key] !== undefined);
    if (changesDefinition) this.testResult = null;

    // [2] Put the change on the draft, keeping the inputs in step, and keep a new draft in the browser
    this.draft = applyDraftChanges(this.draft, changes);
    this.isDirty = true;
    this.errorMessage = NO_TEXT;
  }

  handleTestResult(event) {

    // [1] Keep the result for the Test step, and remember what was tested for the summary
    const result = event.detail.result;
    this.testResult = result;
    const history = addTestHistory(this.draft.testHistory, result.status, result.runAsName);
    this.draft = { ...this.draft, hasTested: true, testHistory: history };
  }

  handleStepClick(event) {

    // [1] Go back to a step that is done
    this.step = Number(event.currentTarget.dataset.step);
  }

  handleNext() {

    // [1] Go to the next step
    this.step = this.step + 1;
  }

  handleBack() {

    // [1] Go to the step before
    this.step = this.step - 1;
  }

  async handleCancel() {

    // [1] Ask first when there is something to lose
    const hasSomethingToLose = this.isNew || this.isDirty;

    if (hasSomethingToLose) {

      const message = this.isNew ? LABELS.discardMessage : LABELS.discardEditMessage;
      const isConfirmed = await LightningConfirm.open({ message, label: LABELS.discardTitle, variant: CONFIRM_VARIANT });
      if (!isConfirmed) return;
    }

    // [2] Throw the draft away and close
    this.dispatchEvent(new CustomEvent("close"));
  }

  async handleSave() {

    // [1] Agents use a saved data source, so tell the admin what a change affects before it is saved
    const hasAgents = this.draft.agentCount > 0;

    if (!this.isNew && hasAgents) {

      await this.openDialog();
      return;
    }

    this.save();
  }

  handleDialogCancel() {

    // [1] Close the dialog and keep editing
    this.isDialogOpen = false;
  }

  handleDialogConfirm() {

    // [1] Save and test, then close the dialog
    this.save();
  }

  // Private methods
  async loadDraft() {

    try {

      if (this.editId) {

        // [1] Read the saved data source
        const detail = await getDataSourceDetail({ dataSourceId: this.editId });
        this.draft = buildDraftFromDetail(detail);

      } else {

        // [2] Start a new data source
        this.draft = buildNewDraft();
      }

    } catch (error) {

      // [3] Show the reason
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isBusy = false;
    }
  }

  async openDialog() {

    try {

      // [1] Read the agents that use the data source and show the dialog
      this.agentUses = await getAgentUses({ dataSourceId: this.draft.dataSourceId });
      this.isDialogOpen = true;

    } catch (error) {

      // [2] Show the reason
      this.errorMessage = formatErrorMessage(error);
    }
  }

  async save() {

    this.isSaving = true;
    this.errorMessage = NO_TEXT;

    try {

      // [1] Test with the values from the Test step when it was run, or when agents depend on the data source
      const detail = buildDetailFromDraft(this.draft);
      const needsTest = this.draft.hasTested || this.draft.agentCount > 0;
      const request = needsTest ? buildTestRequest(this.draft) : null;
      const saveResult = await saveDataSource({ dataSourceDetail: detail, testRequest: request });

      // [2] A change that failed its test is not saved, so show the result on the Test step
      if (!saveResult.isSaved) {

        this.testResult = saveResult.testResult;
        this.errorMessage = saveResult.testResult.message || LABELS.notSavedTest;
        this.isDialogOpen = false;
        this.step = STEP_TEST;
        return;
      }

      // [3] Throw the draft away, tell the admin and tell the tab
        this.showToast(LABELS.saved, TOAST_VARIANT_SUCCESS);
      this.dispatchEvent(new CustomEvent("saved"));

    } catch (error) {

      // [4] Show the reason
      this.errorMessage = formatErrorMessage(error);
      this.isDialogOpen = false;
      this.showToast(this.errorMessage, TOAST_VARIANT_ERROR);

    } finally {

      this.isSaving = false;
    }
  }

  forgetOldBrowserDraft() {

    // [1] A browser that refuses is ignored
    try {

      window.localStorage.removeItem(OLD_DRAFT_STORAGE_KEY);

    } catch {

      // Nothing was kept, so there is nothing to remove.
    }
  }

  showToast(message, variant) {

    // [1] Show the message at the top of the page
    const toastEvent = new ShowToastEvent({ message, variant });
    this.dispatchEvent(toastEvent);
  }
}
