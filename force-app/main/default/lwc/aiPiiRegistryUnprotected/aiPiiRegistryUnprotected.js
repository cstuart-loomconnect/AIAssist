/*
Component Name: aiPiiRegistryUnprotected

=================================================================
=================================================================

Description: The warning banner at the top of the AI PII Registry tab: objects agents read that the registry does not cover.

Step 1: Say how many objects have no cover, and that their fields go to the provider unmasked
Step 2: List each object with the data sources that read it and the fields they send
Step 3: Tell the tab which object the admin wants to add

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, EVENT_ADD_OBJECT } from "./aiPiiRegistryUnprotectedSettings";
import { buildHeadline, buildUnprotectedRows } from "./aiPiiRegistryUnprotectedHelper";

// The warning banner.
export default class AiPiiRegistryUnprotected extends LightningElement {

  // Values passed in by the parent component
  @api objects = []; // UnprotectedObject list from AIPiiRegistryController.getRegistryPage

  // Values the template reads
  labels = LABELS;

  get headline() {

    // [1] Hand the work to the helper
    const headline = buildHeadline(this.objects.length);

    return headline;
  }

  get headlineRest() {

    // [1] The sentence after the bold part
    const headlineRest = LABELS.headlineRest;

    return headlineRest;
  }

  get rows() {

    // [1] Hand the work to the helper
    const rows = buildUnprotectedRows(this.objects);

    return rows;
  }

  // Event handlers
  handleAddClick(event) {

    // [1] Tell the tab which object to add
    const objectApiName = event.currentTarget.dataset.name;
    this.dispatchEvent(new CustomEvent(EVENT_ADD_OBJECT, { detail: { objectApiName } }));
  }
}
