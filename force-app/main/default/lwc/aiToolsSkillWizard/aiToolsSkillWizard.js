/*
Component Name: aiToolsSkillWizard

=================================================================
=================================================================

Description: The wizard that builds and changes an AI Skill in four steps, from data sources and workflow actions that already exist.

Step 1: Load the skill to change, and the data sources and workflow actions it can hold
Step 2: Show the step the admin is on, and keep what each step reports in one draft
Step 3: Save the skill, asking first when agents already use it, and tell the panel when the wizard closes

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import LightningConfirm from "lightning/confirm";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getSkill from "@salesforce/apex/AIToolsSkillController.getSkill";
import getToolOptions from "@salesforce/apex/AIToolsSkillController.getToolOptions";
import saveSkill from "@salesforce/apex/AIToolsSkillController.saveSkill";
import { STEP_BASICS, STEP_TOOLS, STEP_INSTRUCTIONS, STEP_TEST, NEW_DRAFT, TEST_STATUS_NONE, TEST_INVALIDATING_KEYS, PILL_DRAFT_CLASS, PILL_TYPE_CLASS, TOAST_VARIANT_SUCCESS, TOAST_VARIANT_ERROR, CONFIRM_VARIANT, NO_TEXT, LABELS } from "./aiToolsSkillWizardSettings";
import { buildSkillDetail, buildDraftFromDetail, buildStepViews, isStepValid, formatErrorMessage } from "./aiToolsSkillWizardHelper";

// The wizard. It holds one draft, and each step shows part of it and reports changes to it.
export default class AiToolsSkillWizard extends LightningElement {

  // Values passed in by the parent component
  @api skillId = null; // The skill to change, or blank to start a new one

  // Values the template reads
  labels = LABELS;

  // State of the wizard
  draft = { ...NEW_DRAFT, tools: [], agentNames: [] };
  toolOptions = [];
  step = STEP_BASICS;
  maxStep = STEP_BASICS;
  isLoading = false;
  isSaving = false;
  isDirty = false;
  errorMessage = NO_TEXT;

  // Lifecycle methods
  connectedCallback() {

    // [1] Load what the wizard needs: the tools to choose from, and the skill to change
    this.loadWizard();
  }

  get isNewSkill() {

    // [1] A new skill has no id yet
    const isNewSkill = !this.draft.skillId;

    return isNewSkill;
  }

  get isStepBasics() {

    return this.step === STEP_BASICS;
  }

  get isStepTools() {

    return this.step === STEP_TOOLS;
  }

  get isStepInstructions() {

    return this.step === STEP_INSTRUCTIONS;
  }

  get isStepTest() {

    return this.step === STEP_TEST;
  }

  get stepViews() {

    // [1] Hand the work to the helper
    const stepViews = buildStepViews(this.draft, this.step, this.maxStep);

    return stepViews;
  }

  get titleText() {

    // [1] The skill's name when it has one, otherwise a fixed title
    const titleText = this.draft.skillName || LABELS.newTitle;

    return titleText;
  }

  get pillLabel() {

    // [1] A new skill is a draft; a saved one says whether it is on
    if (this.isNewSkill) return LABELS.draftPill;

    const pillLabel = this.draft.isActive ? LABELS.activePill : LABELS.inactivePill;

    return pillLabel;
  }

  get pillClass() {

    // [1] The draft pill is orange and the state pill is blue
    const pillClass = this.isNewSkill ? PILL_DRAFT_CLASS : PILL_TYPE_CLASS;

    return pillClass;
  }

  get statusText() {

    // [1] Say whether the skill exists yet
    const statusText = this.isNewSkill ? LABELS.newStatus : LABELS.editing;

    return statusText;
  }

  get hasBack() {

    // [1] Every step after the first can go back
    const hasBack = this.step > STEP_BASICS;

    return hasBack;
  }

  get isLastStep() {

    // [1] The test step saves instead of going on
    const isLastStep = this.step === STEP_TEST;

    return isLastStep;
  }

  get isNextDisabled() {

    // [1] The next step is not available until this one is complete
    const isNextDisabled = !isStepValid(this.draft, this.step);

    return isNextDisabled;
  }

  get isSaveDisabled() {

    // [1] Saving needs every step complete, and one save at a time
    const isIncomplete = [STEP_BASICS, STEP_TOOLS, STEP_INSTRUCTIONS].some((stepNumber) => !isStepValid(this.draft, stepNumber));
    const isSaveDisabled = isIncomplete || this.isSaving;

    return isSaveDisabled;
  }

  get hasError() {

    // [1] There is an error to show when the last save failed
    const hasError = Boolean(this.errorMessage);

    return hasError;
  }

  get skillDetail() {

    // [1] The skill as it is now, for the step that tests it
    const skillDetail = buildSkillDetail(this.draft);

    return skillDetail;
  }

  // Event handlers
  handleDraftChange(event) {

    // [1] Take what the step reported
    const changes = event.detail.changes;
    const isTestResult = Object.prototype.hasOwnProperty.call(changes, "lastTestStatus");
    const changesWhatModelSees = TEST_INVALIDATING_KEYS.some((key) => Object.prototype.hasOwnProperty.call(changes, key));

    // [2] Anything that changes what the model sees makes the last test out of date
    const testReset = changesWhatModelSees && !isTestResult ? { lastTestStatus: TEST_STATUS_NONE, lastTestedOn: null } : {};
    this.draft = { ...this.draft, ...testReset, ...changes };
    this.isDirty = true;
    this.errorMessage = NO_TEXT;
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

    // [1] Ask first when agents already use the skill, because the change is live as soon as it is saved
    if (!this.isNewSkill && this.draft.agentCount > 0) {

      const countText = this.draft.agentCount + (this.draft.agentCount === 1 ? LABELS.saveMessageOne : LABELS.saveMessageMany);
      const confirmOptions = { message: LABELS.saveMessagePrefix + countText + LABELS.saveMessageSuffix, label: LABELS.saveTitle, variant: CONFIRM_VARIANT };
      const isConfirmed = await LightningConfirm.open(confirmOptions);
      if (!isConfirmed) return;
    }

    this.isSaving = true;
    this.errorMessage = NO_TEXT;

    try {

      // [2] Save the skill
      const detail = buildSkillDetail(this.draft);
      await saveSkill({ skillDetail: detail });

      // [3] Say so and close
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
  async loadWizard() {

    this.isLoading = true;

    try {

      // [1] Read the data sources and workflow actions a skill can hold
      this.toolOptions = await getToolOptions();

      // [2] Read the skill to change, and let the admin go to any step
      if (this.skillId) {

        const detail = await getSkill({ skillId: this.skillId });
        this.draft = buildDraftFromDetail(detail);
        this.maxStep = STEP_TEST;
      }

    } catch (error) {

      // [3] Show the reason and go back to the list
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
