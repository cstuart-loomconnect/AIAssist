/*
Component Name: aiAgentWizardDone

=================================================================
=================================================================

Description: The done screen of the AI Agent Wizard: says the agent is live or saved as a draft, and what was created.

Step 1: Show the name of the agent, whether it is live and how many users will see it
Step 2: Show what the save created and the model
Step 3: Open the agent record or the list of the first object, or tell the tab to start again or to go back to the list of agents

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { PAGE_TYPE_RECORD, PAGE_TYPE_OBJECT, ACTION_VIEW, ACTION_LIST, NO_TEXT, LABELS } from "./aiAgentWizardDoneSettings";
import { buildCreatedText, formatObjectList, buildTryLabel, getObjectLabel } from "./aiAgentWizardDoneHelper";

// The done screen. It opens pages and tells the tab when the admin wants to start again.
export default class AiAgentWizardDone extends NavigationMixin(LightningElement) {

  // Values passed in by the parent component
  @api saveResult; // What the save did: AIAgentWizardDataStructure.SaveResult
  @api objectOptions = []; // [AIAgentWizardDataStructure.ObjectOption] for the labels of objects

  // Values the template reads
  labels = LABELS;

  get isLive() {

    return Boolean(this.saveResult.isActive);
  }

  get titleText() {

    // [1] The name, then whether it is live
    const titleText = this.saveResult.agentName + (this.isLive ? LABELS.liveSuffix : LABELS.draftSuffix);

    return titleText;
  }

  get detailText() {

    // [1] A live agent says who will see it, and where
    if (!this.isLive) return LABELS.draftText;
    const objectText = formatObjectList(this.saveResult.objectApiNames, this.objectOptions);
    const detailText = (this.saveResult.userCount || 0) + LABELS.liveUsersMiddle + objectText + LABELS.livePagesAfter;

    return detailText;
  }

  get createdLabel() {

    // [1] A new agent is created, a changed agent is saved
    const createdLabel = this.saveResult.isCreated ? LABELS.created : LABELS.saved;

    return createdLabel;
  }

  get createdText() {

    // [1] Hand the work to the helper
    const createdText = buildCreatedText(this.saveResult);

    return createdText;
  }

  get modelText() {

    // [1] A draft may have no model yet
    const modelText = this.saveResult.modelName || LABELS.noModel;

    return modelText;
  }

  get firstObjectApiName() {

    // [1] The first object the agent appears on
    const objectApiNames = this.saveResult.objectApiNames || [];
    const firstObjectApiName = objectApiNames.length > 0 ? objectApiNames[0] : NO_TEXT;

    return firstObjectApiName;
  }

  get showTryIt() {

    // [1] Only a live agent can be tried on a record page
    const showTryIt = this.isLive && Boolean(this.firstObjectApiName);

    return showTryIt;
  }

  get tryLabel() {

    // [1] Hand the work to the helper
    const tryLabel = buildTryLabel(getObjectLabel(this.firstObjectApiName, this.objectOptions));

    return tryLabel;
  }

  // Event handlers
  handleOpenRecord() {

    // [1] Open the record page of the agent
    const pageReference = { type: PAGE_TYPE_RECORD, attributes: { recordId: this.saveResult.agentId, actionName: ACTION_VIEW } };
    this[NavigationMixin.Navigate](pageReference);
  }

  handleTryIt() {

    // [1] Open the list of the first object, where the agent can be used on a record
    const pageReference = { type: PAGE_TYPE_OBJECT, attributes: { objectApiName: this.firstObjectApiName, actionName: ACTION_LIST } };
    this[NavigationMixin.Navigate](pageReference);
  }

  handleCreateAnother() {

    // [1] Tell the tab to start again
    this.dispatchEvent(new CustomEvent("createanother"));
  }

  handleBackToList() {

    // [1] Tell the tab to show the list of agents
    this.dispatchEvent(new CustomEvent("backtolist"));
  }
}
