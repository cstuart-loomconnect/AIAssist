/*
Component Name: aiToolsSkStepBasics

=================================================================
=================================================================

Description: Step 1 of the skill wizard: the name, the API name, the When To Use It text the model picks the skill by, the output and whether it is on.

Step 1: Show the basics of the draft
Step 2: Make the API name from the name until the admin edits it
Step 3: Report every change to the wizard

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { SKILL_NAME_MAX_LENGTH, API_NAME_MAX_LENGTH, DESCRIPTION_MAX_LENGTH, OUTPUT_OPTIONS, OUTPUT_RECORD_CHANGE, LABELS } from "./aiToolsSkStepBasicsSettings";
import { buildDeveloperName, buildCounterView } from "./aiToolsSkStepBasicsHelper";

// Step 1. It shows the basics of the draft and reports every change to the wizard.
export default class AiToolsSkStepBasics extends LightningElement {

  // Values passed in by the parent component
  @api draft; // The wizard's draft: the names, the description, the output and isActive are read here

  // Values the template reads
  labels = LABELS;
  nameMaxLength = SKILL_NAME_MAX_LENGTH;
  apiNameMaxLength = API_NAME_MAX_LENGTH;
  descriptionMaxLength = DESCRIPTION_MAX_LENGTH;
  outputOptions = OUTPUT_OPTIONS;

  get counterView() {

    // [1] Hand the work to the helper
    const counterView = buildCounterView(this.draft.description);

    return counterView;
  }

  get isRecordChange() {

    // [1] Apex makes a skill with a write action a Record change skill
    const isRecordChange = this.draft.outputType === OUTPUT_RECORD_CHANGE;

    return isRecordChange;
  }

  get isApiNameLocked() {

    // [1] An agent picks the skill by its API name, so it is locked while an agent has it
    const isApiNameLocked = this.draft.agentCount > 0;

    return isApiNameLocked;
  }

  // Event handlers
  handleNameChange(event) {

    // [1] Keep the name, and make the API name from it while the skill is new and the admin has not edited the API name
    const skillName = event.target.value;
    const changes = { skillName };
    if (!this.draft.skillId && !this.draft.isDeveloperNameEdited) changes.developerName = buildDeveloperName(skillName);
    this.reportChanges(changes);
  }

  handleApiNameChange(event) {

    // [1] Keep the API name the admin typed, and stop making it from the name
    this.reportChanges({ developerName: event.target.value, isDeveloperNameEdited: true });
  }

  handleDescriptionChange(event) {

    // [1] Keep the When To Use It text
    this.reportChanges({ description: event.target.value });
  }

  handleOutputChange(event) {

    // [1] Keep the output
    this.reportChanges({ outputType: event.detail.value });
  }

  handleActiveChange(event) {

    // [1] Keep whether the skill is on
    this.reportChanges({ isActive: event.target.checked });
  }

  // Private methods
  reportChanges(changes) {

    // [1] Tell the wizard
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }
}
