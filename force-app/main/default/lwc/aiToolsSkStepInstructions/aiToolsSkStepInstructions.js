/*
Component Name: aiToolsSkStepInstructions

=================================================================
=================================================================

Description: Step 3 of the skill wizard: the numbered steps the model follows once it has picked the skill, naming its tools with @.

Step 1: Show the instructions and one chip for each tool in the skill
Step 2: Add a tool's @ name from its chip, or write a first draft from the tools
Step 3: Name any @ name that is not a tool in the skill, because the skill cannot be switched on with one
Step 4: Report every change to the wizard

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { INSTRUCTIONS_MAX_LENGTH, LABELS } from "./aiToolsSkStepInstructionsSettings";
import { getUnknownMentions, buildChipViews, buildStarterInstructions, appendMention } from "./aiToolsSkStepInstructionsHelper";

// Step 3. It shows the instructions and the tools they can name, and reports every change to the wizard.
export default class AiToolsSkStepInstructions extends LightningElement {

  // Values passed in by the parent component
  @api draft; // The wizard's draft: instructions and tools are read here

  // Values the template reads
  labels = LABELS;
  instructionsMaxLength = INSTRUCTIONS_MAX_LENGTH;

  get chipViews() {

    // [1] Hand the work to the helper
    const chipViews = buildChipViews(this.draft.tools, this.draft.instructions);

    return chipViews;
  }

  get unknownText() {

    // [1] Name the @ names that are not tools, or nothing when every name is a tool
    const unknownMentions = getUnknownMentions(this.draft.instructions, this.draft.tools);
    const unknownText = unknownMentions.length === 0 ? "" : LABELS.unknownPrefix + unknownMentions.map((name) => "@" + name).join(", ") + LABELS.unknownSuffix;

    return unknownText;
  }

  get isStartDisabled() {

    // [1] Only an empty box can be filled from the tools, so nothing the admin wrote is lost
    const isStartDisabled = Boolean((this.draft.instructions || "").trim());

    return isStartDisabled;
  }

  // Event handlers
  handleInstructionsChange(event) {

    // [1] Keep the instructions
    this.reportChanges({ instructions: event.target.value });
  }

  handleChipClick(event) {

    // [1] Add the tool's @ name at the end
    this.reportChanges({ instructions: appendMention(this.draft.instructions, event.currentTarget.dataset.name) });
  }

  handleStartFromTools() {

    // [1] Write one numbered step for each tool
    this.reportChanges({ instructions: buildStarterInstructions(this.draft.tools) });
  }

  // Private methods
  reportChanges(changes) {

    // [1] Tell the wizard
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }
}
