/*
Component Name: aiAgentWizardPicker

=================================================================
=================================================================

Description: The panel that adds data sources or workflow actions to the agent: a search box, three filters and a list with checkboxes.

Step 1: Show every data source or action, with how it fits the agent
Step 2: Narrow the list with the filter and the search box
Step 3: Remember what the admin ticks
Step 4: Tell the step which ones to add, or that the admin cancelled

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { KIND_DATA_SOURCE, FILTER_FITS, NO_TEXT, LABELS } from "./aiAgentWizardPickerSettings";
import { buildPickerRows, buildFilterButtons, buildShowingText } from "./aiAgentWizardPickerHelper";

// The picker. It lists the options and reports the ones the admin picks.
export default class AiAgentWizardPicker extends LightningElement {

  // Values passed in by the parent component
  @api kind = KIND_DATA_SOURCE; // What the picker lists: "dataSource" or "action"
  @api options = []; // The data sources or workflow actions to offer
  @api addedIds = []; // The ids the agent already has
  @api objectApiNames = []; // The objects the agent appears on
  @api objectOptions = []; // [AIAgentWizardDataStructure.ObjectOption] for the labels of objects

  // Values the template reads
  labels = LABELS;

  // State of the picker
  filter = FILTER_FITS;
  searchText = NO_TEXT;
  selectedIds = [];

  get isDataSource() {

    return this.kind === KIND_DATA_SOURCE;
  }

  get titleText() {

    return this.isDataSource ? LABELS.titleDataSources : LABELS.titleActions;
  }

  get searchPlaceholder() {

    return this.isDataSource ? LABELS.searchDataSources : LABELS.searchActions;
  }

  get showingText() {

    // [1] Hand the work to the helper
    const showingText = buildShowingText(this.kind, this.objectApiNames, this.objectOptions);

    return showingText;
  }

  get filterButtons() {

    // [1] Hand the work to the helper
    const filterButtons = buildFilterButtons(this.filter);

    return filterButtons;
  }

  get rows() {

    // [1] Hand the work to the helper
    const rows = buildPickerRows(this.kind, this.options, this.addedIds, this.objectApiNames, this.objectOptions, this.selectedIds, this.filter, this.searchText);

    return rows;
  }

  get hasRows() {

    return this.rows.length > 0;
  }

  get selectedText() {

    // [1] How many are ticked
    const selectedText = this.selectedIds.length + LABELS.selectedSuffix;

    return selectedText;
  }

  get addLabel() {

    // [1] The button says how many it adds
    const addLabel = this.selectedIds.length > 0 ? LABELS.add + " " + this.selectedIds.length : LABELS.add;

    return addLabel;
  }

  get isAddDisabled() {

    // [1] Nothing is added until something is ticked
    const isAddDisabled = this.selectedIds.length === 0;

    return isAddDisabled;
  }

  // Event handlers
  handleSearchInput(event) {

    // [1] Keep what was typed, and the list follows it
    this.searchText = event.target.value;
  }

  handleFilterClick(event) {

    // [1] Show the filter that was clicked
    this.filter = event.currentTarget.dataset.value;
  }

  handleRowChange(event) {

    // [1] Tick or untick the row
    const id = event.currentTarget.dataset.key;
    const isTicked = event.currentTarget.checked;
    const others = this.selectedIds.filter((selectedId) => selectedId !== id);
    this.selectedIds = isTicked ? [...others, id] : others;
  }

  handleCancel() {

    // [1] Tell the step the admin changed their mind
    this.dispatchEvent(new CustomEvent("cancel"));
  }

  handleAdd() {

    // [1] Tell the step which ones to add
    this.dispatchEvent(new CustomEvent("add", { detail: { ids: this.selectedIds } }));
  }
}
