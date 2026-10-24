/*
Component Name: aiPromptTemplatesEditor

=================================================================
=================================================================

Description: The Edit tab of a prompt template: the fields, the Insert bar, the four sections, the preview and the save buttons.

Step 1: Show the fields and the four sections for the draft the parent passes in
Step 2: Check the draft here at once, ask Apex for the preview and the other checks after a short pause, and show the problems
Step 3: Put a merge field into the section that last had the cursor
Step 4: Save the draft, asking first in the publish dialog when agents use the template or its wording changed
Step 5: Tell the parent about each change, the discard and the saved template

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getMergeFieldOptions from "@salesforce/apex/AIPromptTemplatesController.getMergeFieldOptions";
import getPreview from "@salesforce/apex/AIPromptTemplatesController.getPreview";
import getPublishImpact from "@salesforce/apex/AIPromptTemplatesController.getPublishImpact";
import saveTemplate from "@salesforce/apex/AIPromptTemplatesController.saveTemplate";
import { LABELS, FIELD_TEMPLATE_NAME, FIELD_DEVELOPER_NAME, FIELD_MAX_LENGTH, FIELD_CONTEXT, PREVIEW_DELAY_MS, TOAST_VARIANT_ERROR, DEVELOPER_INPUT_CLASS, DEVELOPER_INPUT_LOCKED_CLASS } from "./aiPromptTemplatesEditorSettings";
import { buildLocalProblems, mergeProblems, buildProblemMap, buildSectionViews, buildFieldClass, isDraftChanged, isPublishDialogNeeded, buildPrimaryLabel, buildFooterText, buildBannerParts, buildDeveloperName, buildPayload, formatErrorMessage } from "./aiPromptTemplatesEditorHelper";

// The Edit tab.
export default class AiPromptTemplatesEditor extends LightningElement {

  // Values passed in by the parent component
  @api savedTemplate = null; // The saved TemplateDetail, or a blank one with no templateId for a new template

  // The draft the admin is editing: a TemplateDetail. The parent keeps it, so it stays when the admin changes tab.
  _draft = null;

  @api
  get draft() {
    return this._draft;
  }

  set draft(value) {

    // [1] Keep the draft and ask for a new preview after a short pause
    this._draft = value;
    this.schedulePreview();
  }

  // Values the template reads
  labels = LABELS;
  fieldTemplateName = FIELD_TEMPLATE_NAME;
  fieldDeveloperName = FIELD_DEVELOPER_NAME;
  fieldMaxLength = FIELD_MAX_LENGTH;

  // State of the editor
  mergeFields = [];
  previewSections = [];
  estimatedTokens = 0;
  serverProblems = [];
  isPreviewLoading = false;
  isSaving = false;
  showPublishDialog = false;
  publishImpact = null;
  lastFocusedKey = FIELD_CONTEXT;
  previewTimer = null;
  previewCounter = 0;

  // Lifecycle methods
  connectedCallback() {

    // [1] Load the merge fields for the Insert bar
    this.loadMergeFields();
  }

  disconnectedCallback() {

    // [1] Stop a preview that has not started yet
    clearTimeout(this.previewTimer);
  }

  get hasDraft() {

    // [1] Nothing shows until the parent passes a draft
    const hasDraft = this._draft !== null && this._draft !== undefined;

    return hasDraft;
  }

  get isSavedTemplate() {

    // [1] A saved template has an id
    const isSavedTemplate = Boolean(this.savedTemplate && this.savedTemplate.templateId);

    return isSavedTemplate;
  }

  get problems() {

    // [1] The checks made here, plus the checks Apex made
    const localProblems = buildLocalProblems(this._draft);
    const problems = mergeProblems(localProblems, this.serverProblems);

    return problems;
  }

  get problemMap() {

    // [1] The message for each field
    const problemMap = buildProblemMap(this.problems);

    return problemMap;
  }

  get problemCount() {

    // [1] How many things are wrong
    const problemCount = this.problems.length;

    return problemCount;
  }

  get hasProblems() {

    // [1] Any problem blocks the save
    const hasProblems = this.problemCount > 0;

    return hasProblems;
  }

  get bannerLead() {

    // [1] Hand the work to the helper
    const bannerParts = buildBannerParts(this.savedTemplate, this._draft, this.problemCount);

    return bannerParts.lead;
  }

  get bannerTail() {

    // [1] Hand the work to the helper
    const bannerParts = buildBannerParts(this.savedTemplate, this._draft, this.problemCount);

    return bannerParts.tail;
  }

  get sectionViews() {

    // [1] Hand the work to the helper
    const sectionViews = buildSectionViews(this._draft, this.problemMap);

    return sectionViews;
  }

  get nameClass() {

    // [1] Red when the name has a problem
    return buildFieldClass(this.problemMap[FIELD_TEMPLATE_NAME]);
  }

  get nameMessage() {

    // [1] The problem under the name
    return this.problemMap[FIELD_TEMPLATE_NAME];
  }

  get developerNameClass() {

    // [1] Red when the API name has a problem
    return buildFieldClass(this.problemMap[FIELD_DEVELOPER_NAME]);
  }

  get developerNameMessage() {

    // [1] The problem under the API name
    return this.problemMap[FIELD_DEVELOPER_NAME];
  }

  get developerInputClass() {

    // [1] The API name looks locked once the template is saved
    const developerInputClass = this.isSavedTemplate ? DEVELOPER_INPUT_LOCKED_CLASS : DEVELOPER_INPUT_CLASS;

    return developerInputClass;
  }

  get maxLengthClass() {

    // [1] Red when the max length has a problem
    return buildFieldClass(this.problemMap[FIELD_MAX_LENGTH]);
  }

  get maxLengthMessage() {

    // [1] The problem under the max length
    return this.problemMap[FIELD_MAX_LENGTH];
  }

  get footerText() {

    // [1] Hand the work to the helper
    const footerText = buildFooterText(this.savedTemplate);

    return footerText;
  }

  get primaryLabel() {

    // [1] Hand the work to the helper
    const primaryLabel = buildPrimaryLabel(this.savedTemplate, this._draft);

    return primaryLabel;
  }

  get isChanged() {

    // [1] Hand the work to the helper
    const isChanged = isDraftChanged(this.savedTemplate, this._draft);

    return isChanged;
  }

  get isDiscardDisabled() {

    // [1] There is nothing to discard until something changes
    const isDiscardDisabled = !this.isChanged || this.isSaving;

    return isDiscardDisabled;
  }

  get isPrimaryDisabled() {

    // [1] Problems block it, and a saved template with no change has nothing to save
    const hasNothingToSave = this.isSavedTemplate && !this.isChanged;
    const isPrimaryDisabled = this.hasProblems || this.isSaving || hasNothingToSave;

    return isPrimaryDisabled;
  }

  get dialogTemplateName() {

    // [1] The name in the dialog title
    const dialogTemplateName = this._draft ? this._draft.templateName : "";

    return dialogTemplateName;
  }

  // Event handlers
  handleFieldInput(event) {

    // [1] Change the field the input belongs to
    const fieldName = event.target.dataset.field;
    this.updateDraft(fieldName, event.target.value);
  }

  handleSectionChange(event) {

    // [1] Change the section the admin typed in
    this.updateDraft(event.detail.key, event.detail.value);
  }

  handleSectionFocus(event) {

    // [1] Remember which section has the cursor, so a chip goes there
    this.lastFocusedKey = event.detail.key;
  }

  handleChipClick(event) {

    // [1] Find the section that last had the cursor
    const token = event.currentTarget.dataset.token;
    const selector = 'c-ai-prompt-templates-section[data-key="' + this.lastFocusedKey + '"]';
    const section = this.template.querySelector(selector);

    // [2] Ask it to put the token in at the cursor
    if (section) section.insertText(token);
  }

  handleDiscard() {

    // [1] Tell the parent to put the saved wording back
    this.serverProblems = [];
    this.dispatchEvent(new CustomEvent("discard"));
  }

  async handleSave() {

    // [1] Never save with a problem on the form
    if (this.hasProblems || this.isSaving) return;

    // [2] Save at once when no question is needed
    const isDialogNeeded = isPublishDialogNeeded(this.savedTemplate, this._draft);
    if (!isDialogNeeded) {
      await this.saveNow();
      return;
    }

    // [3] Otherwise ask Apex what the save would change, then ask the admin
    this.isSaving = true;

    try {
      this.publishImpact = await getPublishImpact({ templateDetail: buildPayload(this._draft) });
      this.showPublishDialog = true;

    } catch (error) {
      this.showToast(formatErrorMessage(error));

    } finally {
      this.isSaving = false;
    }
  }

  handlePublishCancel() {

    // [1] Close the dialog and keep editing
    this.showPublishDialog = false;
  }

  async handlePublishConfirm() {

    // [1] Save, then close the dialog
    await this.saveNow();
  }

  // Private methods
  updateDraft(fieldName, value) {

    // [1] Copy the draft with the one field changed
    const newDraft = { ...this._draft, [fieldName]: value };

    // [2] A new template's API name follows its name until the admin types one
    const isNameChange = fieldName === FIELD_TEMPLATE_NAME;
    const followsName = this._draft[FIELD_DEVELOPER_NAME] === buildDeveloperName(this._draft[FIELD_TEMPLATE_NAME]);
    if (isNameChange && !this.isSavedTemplate && followsName) newDraft[FIELD_DEVELOPER_NAME] = buildDeveloperName(value);

    // [3] Tell the parent, which passes the new draft back
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { draft: newDraft } }));
  }

  schedulePreview() {

    // [1] Wait for the admin to stop typing
    clearTimeout(this.previewTimer);
    if (!this._draft) return;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.previewTimer = setTimeout(() => this.loadPreview(), PREVIEW_DELAY_MS);
  }

  async loadPreview() {

    // [1] Number this request so an older answer never replaces a newer one
    this.previewCounter += 1;
    const requestNumber = this.previewCounter;
    this.isPreviewLoading = true;

    try {

      // [2] Ask Apex for the preview with no agent and no record, so it uses its sample values
      const result = await getPreview({ templateDetail: buildPayload(this._draft), agentId: null, recordId: null });
      if (requestNumber !== this.previewCounter) return;

      // [3] Show the answer and the problems Apex found
      this.previewSections = result.sections || [];
      this.estimatedTokens = result.estimatedTokens || 0;
      this.serverProblems = result.problems || [];

    } catch (error) {
      if (requestNumber === this.previewCounter) this.showToast(formatErrorMessage(error));

    } finally {
      if (requestNumber === this.previewCounter) this.isPreviewLoading = false;
    }
  }

  async loadMergeFields() {

    try {

      // [1] Read the merge fields the Insert bar offers
      const options = await getMergeFieldOptions();
      this.mergeFields = options.map((option) => ({ token: option.token, description: option.description }));

    } catch (error) {

      // [2] Show the reason
      this.showToast(formatErrorMessage(error));
    }
  }

  async saveNow() {

    this.isSaving = true;

    try {

      // [1] Save the draft
      const result = await saveTemplate({ templateDetail: buildPayload(this._draft) });

      if (result.isSaved) {

        // [2] Tell the parent about the saved template
        this.serverProblems = [];
        this.showPublishDialog = false;
        this.dispatchEvent(new CustomEvent("saved", { detail: { detail: result.detail } }));

      } else {

        // [3] Show the problems Apex found on the form
        this.serverProblems = result.problems || [];
        this.showPublishDialog = false;
      }

    } catch (error) {

      // [4] Show the reason
      this.showPublishDialog = false;
      this.showToast(formatErrorMessage(error));

    } finally {

      this.isSaving = false;
    }
  }

  showToast(message) {

    // [1] Show the message at the top of the page
    const toastEvent = new ShowToastEvent({ message, variant: TOAST_VARIANT_ERROR });
    this.dispatchEvent(toastEvent);
  }
}
