/*
Component Name: aiPiiRegistryFields

=================================================================
=================================================================

Description: The Fields tab of a registered object: every field, whether it is PII, its type, and what masks it.

Step 1: Show the fields, filtered by PII only, all or overridden, and by search text
Step 2: Let the admin switch PII on or off, or change the PII type, which overrides the automatic rules
Step 3: Let the admin hand an overridden field back to the automatic rules

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, FILTER_PII, EVENT_FIELD_OVERRIDE, EVENT_FIELD_RESET, NO_TEXT } from "./aiPiiRegistryFieldsSettings";
import { buildFilterButtons, filterFields, buildFieldRows } from "./aiPiiRegistryFieldsHelper";

// The Fields tab.
export default class AiPiiRegistryFields extends LightningElement {

  // Values passed in by the parent component
  @api fields = []; // FieldView list from AIPiiRegistryController.getRegistryDetail
  @api typeOptions = []; // TypeOption list from AIPiiRegistryController.getRegistryPage
  @api isSaving = false; // True while a change is being saved, so the controls wait

  // Values the template reads
  labels = LABELS;

  // State of the tab
  selectedFilter = FILTER_PII;
  searchText = NO_TEXT;

  get filterButtons() {

    // [1] Hand the work to the helper
    const filterButtons = buildFilterButtons(this.fields, this.selectedFilter);

    return filterButtons;
  }

  get fieldRows() {

    // [1] Keep the fields that match, then build a row for each
    const matchingFields = filterFields(this.fields, this.selectedFilter, this.searchText);
    const fieldRows = buildFieldRows(matchingFields, this.typeOptions);

    return fieldRows;
  }

  get hasFieldRows() {

    // [1] The table has at least one row
    const hasFieldRows = this.fieldRows.length > 0;

    return hasFieldRows;
  }

  get hasNoFieldRows() {

    // [1] Say so when nothing matches
    const hasNoFieldRows = !this.hasFieldRows;

    return hasNoFieldRows;
  }

  // Event handlers
  handleFilterClick(event) {

    // [1] Show the fields the filter allows
    this.selectedFilter = event.currentTarget.dataset.filter;
  }

  handleSearchChange(event) {

    // [1] Keep what the admin typed
    this.searchText = event.target.value;
  }

  handlePiiToggle(event) {

    // [1] Put the switch back, because the field only changes once it is saved
    const fieldId = event.target.dataset.fieldId;
    const isPii = event.target.checked;
    event.target.checked = !isPii;

    // [2] Tell the pane to save the choice. A blank type becomes Other
    this.dispatchEvent(new CustomEvent(EVENT_FIELD_OVERRIDE, { detail: { fieldId, isPii, piiFieldType: NO_TEXT } }));
  }

  handleTypeChange(event) {

    // [1] Put the choice back, because the field only changes once it is saved
    const fieldId = event.target.dataset.fieldId;
    const piiFieldType = event.target.value;
    const previousType = event.target.dataset.piiType;
    event.target.value = previousType;

    // [2] Tell the pane to save the new type
    this.dispatchEvent(new CustomEvent(EVENT_FIELD_OVERRIDE, { detail: { fieldId, isPii: true, piiFieldType } }));
  }

  handleReset(event) {

    // [1] Tell the pane to hand the field back to the automatic rules
    const fieldId = event.currentTarget.dataset.fieldId;
    this.dispatchEvent(new CustomEvent(EVENT_FIELD_RESET, { detail: { fieldId } }));
  }
}
