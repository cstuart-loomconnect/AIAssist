/*
Component Name: aiPromptTemplatesList

=================================================================
=================================================================

Description: The left card of the AI Prompt Templates tab: a New template button, a search box and one row per template.

Step 1: Show the New template button and the search box
Step 2: Show one row per template that matches the search, with its status and use
Step 3: Tell the parent when the admin picks a row or asks for a new template

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, ROW_SELECTED_CLASS } from "./aiPromptTemplatesListSettings";
import { buildRowViews } from "./aiPromptTemplatesListHelper";

// The template list.
export default class AiPromptTemplatesList extends LightningElement {

  // Values passed in by the parent component
  @api rows = []; // [TemplateRow] from AIPromptTemplatesController.getTemplateRows
  @api selectedId = null; // The templateId of the open template, null when none or a new one
  @api isNewSelected = false; // True while a template that is not saved yet is open

  // Values the template reads
  labels = LABELS;
  newRowClass = ROW_SELECTED_CLASS;

  // State of the list
  searchText = "";

  get rowViews() {

    // [1] Hand the work to the helper
    const rowViews = buildRowViews(this.rows, this.searchText, this.selectedId);

    return rowViews;
  }

  get showNoMatches() {

    // [1] Say so when the search hides every row
    const hasRows = this.rows && this.rows.length > 0;
    const showNoMatches = hasRows && this.rowViews.length === 0;

    return showNoMatches;
  }

  // Event handlers
  handleSearchChange(event) {

    // [1] Keep what the admin typed
    this.searchText = event.target.value;
  }

  handleNewTemplate() {

    // [1] Tell the parent to open a blank template
    this.dispatchEvent(new CustomEvent("newtemplate"));
  }

  handleRowClick(event) {

    // [1] Tell the parent which template was picked
    const templateId = event.currentTarget.dataset.id;
    this.dispatchEvent(new CustomEvent("select", { detail: { templateId } }));
  }
}
