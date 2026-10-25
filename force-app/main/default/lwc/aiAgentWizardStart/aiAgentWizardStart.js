/*
Component Name: aiAgentWizardStart

=================================================================
=================================================================

Description: The start screen of the AI Agent Wizard: choose a blank agent or an agent to copy.

Step 1: Show the two ways to begin, and the list that belongs to the one chosen
Step 2: Remember the agent the admin picks to copy
Step 3: Tell the tab how to start when the admin presses Start, or that the admin cancelled

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { MODE_BLANK, MODE_COPY, CARD_CLASS, CARD_SELECTED_CLASS, NO_TEXT, LABELS } from "./aiAgentWizardStartSettings";
import { buildCopyViews } from "./aiAgentWizardStartHelper";

// The start screen. It tells the tab which way the admin chose.
export default class AiAgentWizardStart extends LightningElement {

  // Values passed in by the parent component
  @api copyOptions = []; // [AIAgentWizardDataStructure.CopyOption]
  @api objectOptions = []; // [AIAgentWizardDataStructure.ObjectOption] for the labels of the objects

  // Values the template reads
  labels = LABELS;

  // State of the screen
  mode = MODE_BLANK;
  selectedAgentId = null;

  get blankCardClass() {

    return this.mode === MODE_BLANK ? CARD_SELECTED_CLASS : CARD_CLASS;
  }

  get copyCardClass() {

    return this.mode === MODE_COPY ? CARD_SELECTED_CLASS : CARD_CLASS;
  }

  get isCopyMode() {

    return this.mode === MODE_COPY;
  }

  get copyViews() {

    // [1] Hand the work to the helper
    const copyViews = buildCopyViews(this.copyOptions, this.objectOptions, this.selectedAgentId);

    return copyViews;
  }

  get hasCopyOptions() {

    return this.copyViews.length > 0;
  }

  get isStartDisabled() {

    // [1] A copy needs a pick; a blank agent needs nothing
    const isStartDisabled = this.mode === MODE_COPY && !this.selectedAgentId;

    return isStartDisabled;
  }

  // Event handlers
  handleModeClick(event) {

    // [1] Show the list that belongs to the card
    this.mode = event.currentTarget.dataset.mode;
  }

  handleCopyChange(event) {

    // [1] Keep the agent that was picked
    this.selectedAgentId = event.currentTarget.dataset.key;
  }

  handleStart() {

    // [1] Tell the tab what to start from
    const isCopy = this.mode === MODE_COPY;
    const detail = { mode: this.mode, copyAgentId: isCopy ? this.selectedAgentId : NO_TEXT };
    this.dispatchEvent(new CustomEvent("start", { detail }));
  }

  handleCancel() {

    // [1] Tell the tab to go back to the list of agents
    this.dispatchEvent(new CustomEvent("cancelstart"));
  }
}
