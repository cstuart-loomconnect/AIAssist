/*
Component Name: aiToolsDsDetails

=================================================================
=================================================================

Description: Step 5 of the data source wizard: name the data source, describe it for the agent and review it before it is saved.

Step 1: Show the name, API name and descriptions, writing the API name from the name until it is changed
Step 2: Show a summary of what was built and tested
Step 3: Tell the wizard what was typed and whether the data source is active

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { SOURCE_TYPE_APEX, MAX_NAME_LENGTH, MAX_API_NAME_LENGTH, MAX_DESCRIPTION_LENGTH, LABELS } from "./aiToolsDsDetailsSettings";
import { buildApiName, buildTypeText, buildInputsText, buildTestPills } from "./aiToolsDsDetailsHelper";

// The Details step.
export default class AiToolsDsDetails extends LightningElement {

  // The draft of the wizard. Read only: changes are sent up in the draftchange event.
  @api draft;

  // What was tested so far, such as ["Passed as you", "Partial as Trainee adviser"]
  @api testHistoryParts = [];

  // Why the last test failed, blank when it did not fail.
  @api testFailureMessage = "";

  // Values the template reads
  labels = LABELS;
  maxNameLength = MAX_NAME_LENGTH;
  maxApiNameLength = MAX_API_NAME_LENGTH;
  maxDescriptionLength = MAX_DESCRIPTION_LENGTH;

  get typeText() {

    // [1] Hand the work to the helper
    const typeText = buildTypeText(this.draft);

    return typeText;
  }

  get inputsText() {

    // [1] Hand the work to the helper
    const inputsText = buildInputsText(this.draft.inputs);

    return inputsText;
  }

  get isApex() {

    // [1] An Apex data source has no max rows, and the admin names the object it returns
    const isApex = this.draft.sourceType === SOURCE_TYPE_APEX;

    return isApex;
  }

  get isSoql() {

    // [1] A SOQL data source has max rows
    const isSoql = !this.isApex;

    return isSoql;
  }

  get hasTested() {

    // [1] There is something to show when a test was run
    const hasTested = this.testHistoryParts.length > 0;

    return hasTested;
  }

  get hasTestFailure() {

    // [1] There is a reason to show when the last test failed
    const hasTestFailure = Boolean(this.testFailureMessage);

    return hasTestFailure;
  }

  get testPills() {

    // [1] Hand the work to the helper
    const testPills = buildTestPills(this.testHistoryParts);

    return testPills;
  }

  // Event handlers
  handleNameChange(event) {

    // [1] Write the API name from the name until the admin has changed it
    const sourceName = event.target.value;
    const changes = { sourceName };
    if (!this.draft.isDeveloperNameEdited) changes.developerName = buildApiName(sourceName);

    this.sendChange(changes);
  }

  handleApiNameChange(event) {

    // [1] Once the admin types an API name it is no longer written from the name
    this.sendChange({ developerName: event.target.value, isDeveloperNameEdited: true });
  }

  handleDescriptionChange(event) {

    // [1] Keep what was typed
    this.sendChange({ description: event.target.value });
  }

  handleOutputChange(event) {

    // [1] Keep what was typed
    this.sendChange({ outputDescription: event.target.value });
  }

  handleTargetObjectChange(event) {

    // [1] Keep what was typed
    this.sendChange({ targetObject: event.target.value });
  }

  handleActiveChange(event) {

    // [1] Keep the switch
    this.sendChange({ isActive: event.target.checked });
  }

  // Private methods
  sendChange(changes) {

    // [1] Send the change up to the wizard
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }
}
