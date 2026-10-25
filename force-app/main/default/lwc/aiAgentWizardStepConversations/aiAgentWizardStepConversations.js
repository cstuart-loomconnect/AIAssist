/*
Component Name: aiAgentWizardStepConversations

=================================================================
=================================================================

Description: Step 5 of the AI Agent Wizard: when a conversation loads, who can see it, and how long it is kept.

Step 1: Show the way conversations are loaded, with the toggles that depend on it
Step 2: Show who can see conversations, with a warning for Global
Step 3: Show the idle time and the retention fields, with the problems the tab found
Step 4: Tell the tab what changed

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LOAD_MANUAL, VISIBILITY_GLOBAL, FIELD_IDLE, FIELD_RETENTION, RETENTION_CHOICES, NO_TEXT, LABELS } from "./aiAgentWizardStepConversationsSettings";
import { buildLoadCards, buildVisibilityButtons, buildResumeToggle, buildSingleHint, buildFormElementClass, parseNumberOrNull } from "./aiAgentWizardStepConversationsHelper";

// Step 5. It shows the draft and reports every change to the tab.
export default class AiAgentWizardStepConversations extends LightningElement {

  // Values passed in by the parent component
  @api draft; // The tab's draft: the conversation fields are read here
  @api objectOptions = []; // [AIAgentWizardDataStructure.ObjectOption] for the name of the first object
  @api fieldErrors = {}; // The problems to show, keyed by field name: { idleTimeoutMinutes, conversationRetentionDays }

  // Values the template reads
  labels = LABELS;
  retentionChoices = RETENTION_CHOICES;

  get loadCards() {

    // [1] Hand the work to the helper
    const loadCards = buildLoadCards(this.draft.conversationLoadTrigger);

    return loadCards;
  }

  get resumeToggle() {

    // [1] Hand the work to the helper
    const resumeToggle = buildResumeToggle(this.draft.conversationLoadTrigger, this.draft.allowConversationResume);

    return resumeToggle;
  }

  get singleHint() {

    // [1] The hint names the first object the agent appears on
    const firstApiName = this.draft.objectApiNames && this.draft.objectApiNames.length > 0 ? this.draft.objectApiNames[0] : NO_TEXT;
    const firstObject = this.objectOptions.find((option) => option.apiName === firstApiName);
    const objectLabel = firstObject ? firstObject.label : firstApiName;
    const singleHint = buildSingleHint(this.draft.singleActiveConversationPerRecord, objectLabel);

    return singleHint;
  }

  get visibilityButtons() {

    // [1] Hand the work to the helper
    const visibilityButtons = buildVisibilityButtons(this.draft.conversationVisibility);

    return visibilityButtons;
  }

  get isGlobal() {

    // [1] Global needs a warning
    const isGlobal = this.draft.conversationVisibility === VISIBILITY_GLOBAL;

    return isGlobal;
  }

  get idleError() {

    return this.fieldErrors[FIELD_IDLE] || NO_TEXT;
  }

  get retentionError() {

    return this.fieldErrors[FIELD_RETENTION] || NO_TEXT;
  }

  get idleClass() {

    return buildFormElementClass(this.idleError);
  }

  get retentionClass() {

    return buildFormElementClass(this.retentionError);
  }

  get retentionFromChoices() {

    // [1] Mark the one that is chosen
    const retentionFromChoices = this.retentionChoices.map((choice) => ({ ...choice, isSelected: choice.value === this.draft.retentionTrigger }));

    return retentionFromChoices;
  }

  // Event handlers
  handleLoadClick(event) {

    // [1] Keep the way of loading, and switch off what Manual only cannot use
    const conversationLoadTrigger = event.currentTarget.dataset.value;
    const changes = { conversationLoadTrigger };
    if (conversationLoadTrigger === LOAD_MANUAL) changes.allowConversationResume = false;
    this.reportChanges(changes);
  }

  handleResumeChange(event) {

    // [1] Keep whether users can resume
    this.reportChanges({ allowConversationResume: event.target.checked });
  }

  handleSingleChange(event) {

    // [1] Keep whether one conversation per record is allowed
    this.reportChanges({ singleActiveConversationPerRecord: event.target.checked });
  }

  handleVisibilityClick(event) {

    // [1] Keep who can see conversations
    this.reportChanges({ conversationVisibility: event.currentTarget.dataset.value });
  }

  handleIdleInput(event) {

    // [1] Keep the idle time
    this.reportChanges({ idleTimeoutMinutes: parseNumberOrNull(event.target.value) });
  }

  handleRetentionInput(event) {

    // [1] Keep the days conversations are kept
    this.reportChanges({ conversationRetentionDays: parseNumberOrNull(event.target.value) });
  }

  handleRetentionFromChange(event) {

    // [1] Keep what the days are counted from
    this.reportChanges({ retentionTrigger: event.target.value });
  }

  // Private methods
  reportChanges(changes) {

    // [1] Tell the tab
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }
}
