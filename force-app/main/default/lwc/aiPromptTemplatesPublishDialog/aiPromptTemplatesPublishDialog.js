/*
Component Name: aiPromptTemplatesPublishDialog

=================================================================
=================================================================

Description: The dialog that asks before a change to a template that agents use is saved, and shows who it affects.

Step 1: Show the agents that use the template with their users and open conversations
Step 2: Show what changed and whether the saved messages were tried
Step 3: Tell the parent whether the admin cancelled or confirmed

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS } from "./aiPromptTemplatesPublishDialogSettings";
import { isNewVersion, buildTitle, buildIntro, buildChangedText, buildTestedText, buildAgentViews } from "./aiPromptTemplatesPublishDialogHelper";

// The publish dialog.
export default class AiPromptTemplatesPublishDialog extends LightningElement {

  // Values passed in by the parent component
  @api impact = null; // PublishImpact from AIPromptTemplatesController.getPublishImpact
  @api templateName = "";
  @api isSaving = false; // True while the save runs, so the buttons wait

  // Values the template reads
  labels = LABELS;

  get title() {

    // [1] Hand the work to the helper
    const title = buildTitle(this.impact, this.templateName);

    return title;
  }

  get intro() {

    // [1] Hand the work to the helper
    const intro = buildIntro(this.impact);

    return intro;
  }

  get changedText() {

    // [1] Hand the work to the helper
    const changedText = buildChangedText(this.impact);

    return changedText;
  }

  get testedText() {

    // [1] Hand the work to the helper
    const testedText = buildTestedText(this.impact);

    return testedText;
  }

  get agentViews() {

    // [1] Hand the work to the helper
    const agentViews = buildAgentViews(this.impact);

    return agentViews;
  }

  get hasAgents() {

    // [1] The table shows only when an agent uses the template
    const hasAgents = this.agentViews.length > 0;

    return hasAgents;
  }

  get confirmLabel() {

    // [1] A new version is published, and anything else is just saved
    const confirmLabel = isNewVersion(this.impact) ? LABELS.publish : LABELS.save;

    return confirmLabel;
  }

  // Event handlers
  handleCancel() {

    // [1] Tell the editor to close the dialog
    this.dispatchEvent(new CustomEvent("cancel"));
  }

  handleConfirm() {

    // [1] Tell the editor to save
    this.dispatchEvent(new CustomEvent("confirm"));
  }
}
