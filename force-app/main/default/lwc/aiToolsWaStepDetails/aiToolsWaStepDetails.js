/*
Component Name: aiToolsWaStepDetails

=================================================================
=================================================================

Description: Step 6 of the workflow action wizard: the name, API name and description, a summary and the Active switch.

Step 1: Show the name, the API name, the description and what comes back
Step 2: Make the API name from the name until the admin edits it
Step 3: Show a summary of what the admin built, and the Active switch
Step 4: Tell the wizard what changed

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { ACTION_NAME_MAX_LENGTH, API_NAME_MAX_LENGTH, LABELS } from "./aiToolsWaStepDetailsSettings";
import { buildSummaryRows, buildDeveloperName } from "./aiToolsWaStepDetailsHelper";

// Step 6. It shows the details of the draft and reports every change to the wizard.
export default class AiToolsWaStepDetails extends LightningElement {

  // Values passed in by the parent component
  @api draft; // The wizard's draft: the names, the descriptions, isActive and the choices of the earlier steps are read here

  // Values the template reads
  labels = LABELS;
  nameMaxLength = ACTION_NAME_MAX_LENGTH;
  apiNameMaxLength = API_NAME_MAX_LENGTH;

  // Lifecycle methods
  connectedCallback() {

    // [1] Make the API name from the name when it has none yet
    if (this.draft.actionName && !this.draft.developerName) this.reportChanges({ developerName: buildDeveloperName(this.draft.actionName) });
  }

  get summaryRows() {

    // [1] Hand the work to the helper
    const summaryRows = buildSummaryRows(this.draft);

    return summaryRows;
  }

  // Event handlers
  handleNameChange(event) {

    // [1] Keep the name, and make the API name from it until the admin edits the API name
    const actionName = event.target.value;
    const changes = { actionName };
    if (!this.draft.isDeveloperNameEdited) changes.developerName = buildDeveloperName(actionName);
    this.reportChanges(changes);
  }

  handleApiNameChange(event) {

    // [1] Keep the API name the admin typed, and stop making it from the name
    this.reportChanges({ developerName: event.target.value, isDeveloperNameEdited: true });
  }

  handleDescriptionChange(event) {

    // [1] Keep the description
    this.reportChanges({ description: event.target.value });
  }

  handleOutputDescriptionChange(event) {

    // [1] Keep what comes back
    this.reportChanges({ outputDescription: event.target.value });
  }

  handleActiveChange(event) {

    // [1] Keep whether the action is active
    this.reportChanges({ isActive: event.target.checked });
  }

  // Private methods
  reportChanges(changes) {

    // [1] Tell the wizard
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }
}
