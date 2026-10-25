/*
Component Name: aiAgentWizard

=================================================================
=================================================================

Description: The AI Agent Wizard tab: list the agents, start a new agent or change one, work through eight steps, check the draft with Apex and save it.

Step 1: Show the list of agents, or load the agent to change when the tab was opened with one
Step 2: Show the list, the start screen, the steps or the done screen, and keep what each step reports in one draft
Step 3: Ask Apex to check the draft when a step is entered or the name settles, and show what it found on the step it belongs to
Step 4: Save the agent as a draft or activate it, and show what was created

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, wire } from "lwc";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import LightningConfirm from "lightning/confirm";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getWizardPage from "@salesforce/apex/AIAgentWizardController.getWizardPage";
import getCopyDraft from "@salesforce/apex/AIAgentWizardController.getCopyDraft";
import checkDraft from "@salesforce/apex/AIAgentWizardController.checkDraft";
import saveAgent from "@salesforce/apex/AIAgentWizardController.saveAgent";
import { SCREEN_LIST, SCREEN_START, SCREEN_WIZARD, SCREEN_DONE, STEP_BASICS, STEP_MODEL, STEP_SKILLS, STEP_DATA_SOURCES, STEP_ACTIONS, STEP_CONVERSATIONS, STEP_LIMITS, STEP_ACCESS, STEP_REVIEW, FIRST_CHECKED_STEP, STEP_NAMES, STEPS_WITH_REQUIRED_FIELDS, BLANK_DRAFT, CHECK_DELAY_MILLISECONDS, AGENT_ID_STATE_KEY, SETTINGS_TAB_API_NAME, TOAST_VARIANT_ERROR, CONFIRM_VARIANT, NO_TEXT, LABELS } from "./aiAgentWizardSettings";
import { buildFieldErrors, buildFieldErrorMap, getStepFindings, buildReviewFindings, buildStepViews, formatLastChanged, formatErrorMessage, toApexDraft } from "./aiAgentWizardHelper";

// The tab. It holds one draft, and each step shows part of it and reports changes to it.
export default class AiAgentWizard extends NavigationMixin(LightningElement) {

  // Values the template reads
  labels = LABELS;

  // State of the tab
  screen = SCREEN_LIST;
  page = null;
  draft = { ...BLANK_DRAFT };
  check = null;
  step = STEP_BASICS;
  maxStep = STEP_BASICS;
  objectOptions = [];
  modelTest = null;
  saveResult = null;
  agentId = null;
  isLoading = true;
  isChecking = false;
  isSaving = false;
  isDirty = false;
  showErrors = false;
  errorMessage = NO_TEXT;
  isPageRead = false;
  checkTimer = null;
  checkRunId = 0;

  // The tab URL names the agent to change, in its state. The page is read once the URL is known.
  @wire(CurrentPageReference)
  handlePageReference(pageReference) {

    // [1] Read the page once, with the agent named in the URL when there is one
    if (this.isPageRead) return;
    this.isPageRead = true;
    const state = pageReference && pageReference.state;
    this.agentId = state && state[AGENT_ID_STATE_KEY] ? state[AGENT_ID_STATE_KEY] : null;

    // [2] Show the list of agents when the URL names none
    if (this.agentId) this.loadPage();
    else this.isLoading = false;
  }

  // Lifecycle methods
  disconnectedCallback() {

    // [1] Stop a check that is waiting
    clearTimeout(this.checkTimer);
  }

  get isScreenList() {

    // [1] The list waits until the tab is sure it was not opened with an agent
    const isScreenList = this.screen === SCREEN_LIST && !this.isLoading;

    return isScreenList;
  }

  get showBackLink() {

    // [1] The start screen and the steps can go back to the list
    const showBackLink = this.screen === SCREEN_START || this.screen === SCREEN_WIZARD;

    return showBackLink;
  }

  get isScreenStart() {

    return this.screen === SCREEN_START;
  }

  get isScreenWizard() {

    return this.screen === SCREEN_WIZARD;
  }

  get isScreenDone() {

    return this.screen === SCREEN_DONE;
  }

  get isStepBasics() {

    return this.step === STEP_BASICS;
  }

  get isStepModel() {

    return this.step === STEP_MODEL;
  }

  get isStepDataSources() {

    return this.step === STEP_DATA_SOURCES;
  }

  get isStepSkills() {

    return this.step === STEP_SKILLS;
  }

  get isStepActions() {

    return this.step === STEP_ACTIONS;
  }

  get isStepConversations() {

    return this.step === STEP_CONVERSATIONS;
  }

  get isStepLimits() {

    return this.step === STEP_LIMITS;
  }

  get isStepAccess() {

    return this.step === STEP_ACCESS;
  }

  get isStepReview() {

    return this.step === STEP_REVIEW;
  }

  get isEditing() {

    // [1] A saved agent has an id
    const isEditing = Boolean(this.draft.agentId);

    return isEditing;
  }

  get isEditingLive() {

    // [1] A saved agent that is active is live for its users
    const isEditingLive = this.isEditing && Boolean(this.draft.isActive);

    return isEditingLive;
  }

  get subtitleText() {

    // [1] Say which agent is being changed, or what the wizard is for
    const subtitleText = this.isEditing ? LABELS.subtitleEditing + this.draft.agentName : LABELS.subtitleNew;

    return subtitleText;
  }

  get stepTitle() {

    // [1] The panel is titled with the step the admin is on
    const stepName = STEP_NAMES.find((candidate) => candidate.number === this.step);
    const stepTitle = stepName ? stepName.title : NO_TEXT;

    return stepTitle;
  }

  get statusText() {

    // [1] A new agent is not saved until the end; a saved one says when it changed
    if (!this.isEditing) return LABELS.statusNew;
    const dateText = formatLastChanged(this.draft.lastModifiedDate);
    const statusText = (this.draft.isActive ? LABELS.statusActive : LABELS.statusDraft) + dateText;

    return statusText;
  }

  get liveBannerAfter() {

    // [1] The text after the number of users
    const liveBannerAfter = (this.draft.userCount || 0) + LABELS.editingLiveAfter;

    return liveBannerAfter;
  }

  get fieldErrors() {

    // [1] Every problem the admin has to fix, with the live ones always shown
    const fieldErrors = buildFieldErrors(this.draft, this.check, this.showErrors);

    return fieldErrors;
  }

  get allFieldErrors() {

    // [1] Every problem, shown or not, for the stepper and the Review step
    const allFieldErrors = buildFieldErrors(this.draft, this.check, true);

    return allFieldErrors;
  }

  get stepFieldErrors() {

    // [1] The messages of the step the admin is on, keyed by field
    const stepFieldErrors = buildFieldErrorMap(this.fieldErrors, this.step);

    return stepFieldErrors;
  }

  get findings() {

    // [1] What the Apex checks found, or nothing before they ran
    const findings = this.check && this.check.findings ? this.check.findings : [];

    return findings;
  }

  get stepFindings() {

    // [1] The findings of the step the admin is on
    const stepFindings = getStepFindings(this.findings, this.step);

    return stepFindings;
  }

  get reviewFindings() {

    // [1] Everything that stops or warns, for the Review step
    const reviewFindings = buildReviewFindings(this.findings, this.allFieldErrors);

    return reviewFindings;
  }

  get stepViews() {

    // [1] Hand the work to the helper, counting a problem only on steps the admin has reached
    const problemErrors = this.allFieldErrors.filter((error) => error.step !== this.step || this.showErrors);
    const stepViews = buildStepViews(this.step, this.maxStep, this.findings, problemErrors);

    return stepViews;
  }

  get accessUserCount() {

    // [1] The users who would see the agent, as the last check counted them
    const accessUserCount = this.check && this.check.accessUserCount !== undefined ? this.check.accessUserCount : null;

    return accessUserCount;
  }

  get hasBack() {

    // [1] Every step after the first can go back
    const hasBack = this.step > STEP_BASICS;

    return hasBack;
  }

  get isReview() {

    // [1] The Review step saves instead of going on
    const isReview = this.step === STEP_REVIEW;

    return isReview;
  }

  get showNext() {

    // [1] Every step before Review goes on
    const showNext = this.step < STEP_REVIEW;

    return showNext;
  }

  get showSaveChanges() {

    // [1] A saved agent can be saved from any step, and a live one is saved from Review too
    const showSaveChanges = this.isEditing && (this.showNext || this.isEditingLive);

    return showSaveChanges;
  }

  get showSaveDraft() {

    // [1] Review saves a draft, unless the agent is live
    const showSaveDraft = this.isReview && !this.isEditingLive;

    return showSaveDraft;
  }

  get showActivate() {

    // [1] Review activates, unless the agent is live and Save changes does it
    const showActivate = this.isReview && !this.isEditingLive;

    return showActivate;
  }

  get nextLabel() {

    // [1] The button says what an empty step means
    const hasNoModel = this.step === STEP_MODEL && this.activeModels.length === 0;
    const hasNoActions = this.step === STEP_ACTIONS && this.draft.workflowActionIds.length === 0;
    if (hasNoModel) return LABELS.nextNoModel;
    if (hasNoActions) return LABELS.nextReadOnly;

    return LABELS.next;
  }

  get nextVariant() {

    // [1] Next is the main button, except when Save changes is
    const nextVariant = this.isEditing ? "brand-outline" : "brand";

    return nextVariant;
  }

  get activeModels() {

    // [1] The models the Model step offers
    const models = this.page && this.page.models ? this.page.models : [];

    return models;
  }

  get isSaveDisabled() {

    // [1] One save at a time
    const isSaveDisabled = this.isSaving;

    return isSaveDisabled;
  }

  get isActivateDisabled() {

    // [1] Activating needs a clean check, and one save at a time
    const hasErrors = this.allFieldErrors.length > 0;
    const canActivate = Boolean(this.check && this.check.canActivate) && !hasErrors;
    const isActivateDisabled = !canActivate || this.isSaving || this.isChecking;

    return isActivateDisabled;
  }

  get saveChangesDisabled() {

    // [1] A live agent can only be saved when it could be activated
    const saveChangesDisabled = this.isEditingLive && this.isReview ? this.isActivateDisabled : this.isSaving;

    return saveChangesDisabled;
  }

  get hasError() {

    // [1] There is an error to show when the last save failed
    const hasError = Boolean(this.errorMessage);

    return hasError;
  }

  // Event handlers
  handleStart(event) {

    // [1] Build the first draft from what the admin chose
    this.startDraft(event.detail);
  }

  handleDraftChange(event) {

    // [1] Take what the step reported
    const changes = event.detail.changes;
    const objects = event.detail.objects || [];
    this.draft = { ...this.draft, ...changes };
    this.isDirty = true;
    this.errorMessage = NO_TEXT;

    // [2] Remember the labels of objects the step found
    if (objects.length > 0) this.objectOptions = [...this.objectOptions, ...objects.filter((object) => !this.objectOptions.some((known) => known.apiName === object.apiName))];

    // [3] Check the draft again once the admin stops changing it
    this.scheduleCheck();
  }

  handleModelTest(event) {

    // [1] Keep the last connection check, so the Review step can show it
    this.modelTest = event.detail;
  }

  handleStepClick(event) {

    // [1] Go to a step the admin has already reached
    const stepNumber = Number(event.currentTarget.dataset.step);
    if (stepNumber <= this.maxStep) this.goToStep(stepNumber);
  }

  handleGoToStep(event) {

    // [1] A step asked to jump to another step
    this.goToStep(event.detail.step);
  }

  handleBack() {

    // [1] Go to the step before
    this.goToStep(this.step - 1);
  }

  async handleNext() {

    // [1] Settle the name check first, so a name that is taken is known
    const hasRequiredFields = STEPS_WITH_REQUIRED_FIELDS.includes(this.step);
    if (this.step === STEP_BASICS) await this.runCheck();

    // [2] Stay when the step has a field to fix
    const stepErrors = buildFieldErrors(this.draft, this.check, true).filter((error) => error.step === this.step);
    if (hasRequiredFields && stepErrors.length > 0) {

      this.showErrors = true;
      return;
    }

    // [3] Go on
    this.goToStep(this.step + 1);
  }

  async handleCancel() {

    // [1] Ask first when there is something to lose
    if (this.isDirty) {

      const confirmOptions = { message: LABELS.discardMessage, label: LABELS.discardTitle, variant: CONFIRM_VARIANT };
      const isConfirmed = await LightningConfirm.open(confirmOptions);
      if (!isConfirmed) return;
    }

    // [2] Go back to the list of agents
    this.goToList();
  }

  handleBackToList() {

    // [1] The link in the header does what Cancel does
    this.handleCancel();
  }

  handleStartCancel() {

    // [1] The start screen has nothing to lose
    this.goToList();
  }

  async handleCreateAgent() {

    // [1] Read what the steps offer, then show the start screen
    this.agentId = null;
    await this.loadPage();
    if (this.page) this.screen = SCREEN_START;
  }

  handleEditAgent(event) {

    // [1] Read what the steps offer and the agent, which opens in the wizard
    this.agentId = event.detail.agentId;
    this.loadPage();
  }

  handleSaveDraft() {

    // [1] Save the agent switched off
    this.save(false);
  }

  handleActivate() {

    // [1] Save the agent switched on
    this.save(true);
  }

  handleSaveChanges() {

    // [1] A live agent stays live, any other agent stays a draft
    this.save(this.isEditingLive);
  }

  handleGoToSettings() {

    // [1] Open the AI Settings tab
    const pageReference = { type: "standard__navItemPage", attributes: { apiName: SETTINGS_TAB_API_NAME } };
    this[NavigationMixin.Navigate](pageReference);
  }

  async handleCreateAnother() {

    // [1] Forget the agent that was saved, read the page again so the lists are up to date, and show the start screen
    this.screen = SCREEN_LIST;
    this.clearWizard();
    await this.loadPage();
    if (this.page) this.screen = SCREEN_START;
  }

  handleDoneBackToList() {

    // [1] The saved agent is in the list now
    this.goToList();
  }

  // Private methods
  async loadPage() {

    this.isLoading = true;

    try {

      // [1] Read everything the steps offer, and the agent to change
      const page = await getWizardPage({ agentId: this.agentId });
      this.page = page;
      this.objectOptions = page.objects || [];

      // [2] Change the agent right away, or show the start screen
      if (this.agentId && page.draft) this.openAgentInWizard(page.draft);

    } catch (error) {

      // [3] Show the reason
      this.showToast(formatErrorMessage(error), TOAST_VARIANT_ERROR);

    } finally {

      this.isLoading = false;
    }
  }

  openAgentInWizard(draft) {

    // [1] A saved agent can be reached at every step
    this.draft = { ...BLANK_DRAFT, ...draft };
    this.screen = SCREEN_WIZARD;
    this.step = STEP_BASICS;
    this.maxStep = STEP_REVIEW;
    this.isDirty = false;
    this.showErrors = false;
    this.modelTest = null;
    this.runCheck();
  }

  async startDraft(choice) {

    this.isLoading = true;

    try {

      // [1] Start from a copy or nothing
      let draft = { ...BLANK_DRAFT };
      if (choice.copyAgentId) draft = { ...BLANK_DRAFT, ...(await getCopyDraft({ agentId: choice.copyAgentId })) };

      // [2] Show the first step
      this.draft = draft;
      this.screen = SCREEN_WIZARD;
      this.step = STEP_BASICS;
      this.maxStep = STEP_BASICS;
      this.isDirty = false;
      this.showErrors = false;
      this.check = null;
      this.modelTest = null;

    } catch (error) {

      // [3] Show the reason
      this.showToast(formatErrorMessage(error), TOAST_VARIANT_ERROR);

    } finally {

      this.isLoading = false;
    }
  }

  goToStep(stepNumber) {

    // [1] Show the step, and remember how far the admin has got
    this.step = stepNumber;
    this.maxStep = Math.max(this.maxStep, stepNumber);
    this.errorMessage = NO_TEXT;

    // [2] Check the whole draft when a step that shows findings is entered
    if (stepNumber >= FIRST_CHECKED_STEP) this.runCheck();
  }

  scheduleCheck() {

    // [1] Wait for a pause in the changes
    clearTimeout(this.checkTimer);

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.checkTimer = setTimeout(() => this.runCheck(), CHECK_DELAY_MILLISECONDS);
  }

  async runCheck() {

    // [1] Note which check this is, so a slow answer to an old check is ignored
    clearTimeout(this.checkTimer);
    this.checkRunId = this.checkRunId + 1;
    const runId = this.checkRunId;
    this.isChecking = true;

    try {

      // [2] Ask Apex what is wrong with the draft
      const check = await checkDraft({ draftJson: JSON.stringify(toApexDraft(this.draft)) });
      if (runId === this.checkRunId) this.check = check;

    } catch (error) {

      // [3] Show the reason
      if (runId === this.checkRunId) this.errorMessage = formatErrorMessage(error);

    } finally {

      if (runId === this.checkRunId) this.isChecking = false;
    }
  }

  async save(shouldActivate) {

    this.isSaving = true;
    this.errorMessage = NO_TEXT;

    try {

      // [1] Save the agent and everything linked to it
      const saveResult = await saveAgent({ draftJson: JSON.stringify(toApexDraft(this.draft)), shouldActivate });

      // [2] Show what was made
      this.saveResult = saveResult;
      this.screen = SCREEN_DONE;
      this.isDirty = false;

    } catch (error) {

      // [3] Show the reason above the buttons
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isSaving = false;
    }
  }

  clearWizard() {

    // [1] Forget the draft and everything read for it
    clearTimeout(this.checkTimer);
    this.agentId = null;
    this.page = null;
    this.draft = { ...BLANK_DRAFT };
    this.check = null;
    this.saveResult = null;
    this.modelTest = null;
    this.isDirty = false;
    this.showErrors = false;
    this.errorMessage = NO_TEXT;
  }

  goToList() {

    // [1] Forget the draft, and show the list, which reads the agents again
    this.screen = SCREEN_LIST;
    this.clearWizard();
  }

  showToast(message, variant) {

    // [1] Show the message at the top of the page
    const toastEvent = new ShowToastEvent({ message, variant });
    this.dispatchEvent(toastEvent);
  }
}
