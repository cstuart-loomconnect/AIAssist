/*
Component Name: aiToolsDsSaveDialog

=================================================================
=================================================================

Description: The dialog that asks before a change to a data source that agents use is saved.

Step 1: Show the name of the data source and the agents that use it
Step 2: Say the test must pass again before the change goes live
Step 3: Tell the wizard whether the admin cancelled or chose to save and test

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS } from "./aiToolsDsSaveDialogSettings";
import { buildTitle, buildCountText } from "./aiToolsDsSaveDialogHelper";

// The save dialog.
export default class AiToolsDsSaveDialog extends LightningElement {

  // The name of the data source being saved.
  @api sourceName = "";

  // The agents that use it: [{ agentId, agentName }]
  @api agents = [];

  // True while the save and test is running, so the buttons wait.
  @api isSaving = false;

  // Values the template reads
  labels = LABELS;

  get title() {

    // [1] Hand the work to the helper
    const title = buildTitle(this.sourceName);

    return title;
  }

  get countText() {

    // [1] Hand the work to the helper
    const countText = buildCountText(this.agents.length);

    return countText;
  }

  // Event handlers
  handleCancel() {

    // [1] Tell the wizard to close the dialog
    this.dispatchEvent(new CustomEvent("cancel"));
  }

  handleConfirm() {

    // [1] Tell the wizard to save and test
    this.dispatchEvent(new CustomEvent("confirm"));
  }
}
