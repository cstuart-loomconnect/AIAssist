/*
Component Name: aiPromptTemplatesDetail

=================================================================
=================================================================

Description: The right card of the AI Prompt Templates tab: the template name, its pills, its action buttons and its tabs.

Step 1: Show the name, the pills and the buttons that fit the template
Step 2: Keep the draft the admin is editing, so it is not lost when the tab changes
Step 3: Show the Edit tab, and for a saved template the Try it and Used by tabs
Step 4: Tell the parent about archive, activate, make default and a saved template

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, TAB_EDIT, TAB_TRY_IT, TAB_USED_BY } from "./aiPromptTemplatesDetailSettings";
import { buildPillViews, buildUsedByLabel } from "./aiPromptTemplatesDetailHelper";

// The template detail card.
export default class AiPromptTemplatesDetail extends LightningElement {

  // The saved TemplateDetail, or a blank one with no templateId for a new template.
  _savedTemplate = null;

  @api
  get savedTemplate() {
    return this._savedTemplate;
  }

  set savedTemplate(value) {

    // [1] Go back to the Edit tab when another template opens
    const oldId = this._savedTemplate ? this._savedTemplate.templateId : null;
    const newId = value ? value.templateId : null;
    if (oldId !== newId) this.activeTab = TAB_EDIT;

    // [2] Keep the saved template and start a fresh draft from it
    this._savedTemplate = value;
    this.draft = value ? { ...value } : null;
  }

  // Values the template reads
  labels = LABELS;
  tabEdit = TAB_EDIT;
  tabTryIt = TAB_TRY_IT;
  tabUsedBy = TAB_USED_BY;

  // State of the card
  draft = null;
  activeTab = TAB_EDIT;

  get isSaved() {

    // [1] A saved template has an id
    const isSaved = Boolean(this._savedTemplate && this._savedTemplate.templateId);

    return isSaved;
  }

  get templateName() {

    // [1] A new template has no name yet
    const hasName = this._savedTemplate && this._savedTemplate.templateName;
    const templateName = hasName ? this._savedTemplate.templateName : LABELS.newTemplate;

    return templateName;
  }

  get pillViews() {

    // [1] Hand the work to the helper
    const pillViews = buildPillViews(this._savedTemplate);

    return pillViews;
  }

  get usedByLabel() {

    // [1] Hand the work to the helper
    const usedByLabel = buildUsedByLabel(this._savedTemplate);

    return usedByLabel;
  }

  get templateId() {

    // [1] The id the tabs load their data for
    const templateId = this.isSaved ? this._savedTemplate.templateId : null;

    return templateId;
  }

  get canArchive() {

    // [1] Only a live template that is not the default can be archived
    const canArchive = this.isSaved && this._savedTemplate.isActive && !this._savedTemplate.isDefault;

    return canArchive;
  }

  get canMakeDefault() {

    // [1] Only a live template that is not the default can become the default
    const canMakeDefault = this.isSaved && this._savedTemplate.isActive && !this._savedTemplate.isDefault;

    return canMakeDefault;
  }

  get canActivate() {

    // [1] Only a saved template that is not live can be activated
    const canActivate = this.isSaved && !this._savedTemplate.isActive;

    return canActivate;
  }

  // Event handlers
  handleTabActive(event) {

    // [1] Remember the tab, so the card keeps it when it redraws
    this.activeTab = event.target.value;
  }

  handleDraftChange(event) {

    // [1] Keep the draft the editor sends
    this.draft = event.detail.draft;
  }

  handleDiscard() {

    // [1] Put the saved wording back
    this.draft = this._savedTemplate ? { ...this._savedTemplate } : null;
  }

  handleSaved(event) {

    // [1] Tell the parent about the saved template
    this.dispatchEvent(new CustomEvent("saved", { detail: event.detail }));
  }

  handleArchive() {

    // [1] Tell the parent to start the archive
    this.dispatchEvent(new CustomEvent("archive"));
  }

  handleActivate() {

    // [1] Tell the parent to activate
    this.dispatchEvent(new CustomEvent("activate"));
  }

  handleMakeDefault() {

    // [1] Tell the parent to make this the default
    this.dispatchEvent(new CustomEvent("makedefault"));
  }
}
