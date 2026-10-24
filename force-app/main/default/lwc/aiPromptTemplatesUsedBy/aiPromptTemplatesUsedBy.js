/*
Component Name: aiPromptTemplatesUsedBy

=================================================================
=================================================================

Description: The Used by tab: the agents that answer with a prompt template.

Step 1: Load the agents when the template is set
Step 2: Show one row per agent with its users, open conversations and status
Step 3: Show a hint when no agent uses the template

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getAgentUses from "@salesforce/apex/AIPromptTemplatesController.getAgentUses";
import { LABELS, TOAST_VARIANT_ERROR } from "./aiPromptTemplatesUsedBySettings";
import { buildAgentViews, formatErrorMessage } from "./aiPromptTemplatesUsedByHelper";

// The Used by tab.
export default class AiPromptTemplatesUsedBy extends LightningElement {

  // The template to show the agents of.
  _templateId = null;

  @api
  get templateId() {
    return this._templateId;
  }

  set templateId(value) {

    // [1] Load the agents again when another template is set
    const isChanged = value !== this._templateId;
    this._templateId = value;
    if (isChanged) this.loadAgents();
  }

  // Values the template reads
  labels = LABELS;

  // State of the tab
  agentUses = [];
  isBusy = false;

  get agentViews() {

    // [1] Hand the work to the helper
    const agentViews = buildAgentViews(this.agentUses);

    return agentViews;
  }

  get hasAgents() {

    // [1] The table shows when at least one agent uses the template
    const hasAgents = this.agentViews.length > 0;

    return hasAgents;
  }

  get showEmpty() {

    // [1] Say so once the load is done and nothing is listed
    const showEmpty = !this.isBusy && !this.hasAgents;

    return showEmpty;
  }

  // Private methods
  async loadAgents() {

    // [1] A template that is not saved has no agents
    if (!this._templateId) {
      this.agentUses = [];
      return;
    }

    this.isBusy = true;

    try {

      // [2] Read the agents
      this.agentUses = await getAgentUses({ templateId: this._templateId });

    } catch (error) {

      // [3] Show the reason
      const toastEvent = new ShowToastEvent({ message: formatErrorMessage(error), variant: TOAST_VARIANT_ERROR });
      this.dispatchEvent(toastEvent);

    } finally {

      this.isBusy = false;
    }
  }
}
