/*
Component Name: aiAgentWizardStepItems

=================================================================
=================================================================

Description: Steps 3 and 4 of the AI Agent Wizard: the data sources or the workflow actions the agent has, with a picker to add more.

Step 1: Show what the agent has, with a search box and a Remove button on each row
Step 2: Open the picker to add more, and add what the admin picks
Step 3: Show what the Apex checks found for the step, and fix it with Remove or Open Settings
Step 4: Tell the tab what changed

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { KIND_DATA_SOURCE, FIELD_DATA_SOURCE_IDS, FIELD_ACTION_IDS, NO_TEXT, LABELS } from "./aiAgentWizardStepItemsSettings";
import { buildItemViews, buildSummaryRows, buildFindingViews, formatFindingCount } from "./aiAgentWizardStepItemsHelper";

// Steps 3 and 4. One component shows either list, and reports each change to the tab.
export default class AiAgentWizardStepItems extends LightningElement {

  // Values passed in by the parent component
  @api kind = KIND_DATA_SOURCE; // What the step shows: "dataSource" or "action"
  @api draft; // The tab's draft: dataSourceIds, workflowActionIds and objectApiNames are read here
  @api options = []; // The data sources or the workflow actions the step offers
  @api objectOptions = []; // [AIAgentWizardDataStructure.ObjectOption] for the labels of objects
  @api findings = []; // The findings of this step: [AIAgentWizardDataStructure.Finding]

  // Values the template reads
  labels = LABELS;

  // State of the step
  searchText = NO_TEXT;
  isAdding = false;

  get isDataSource() {

    return this.kind === KIND_DATA_SOURCE;
  }

  get ids() {

    // [1] The ids of the list this step shows
    const ids = this.isDataSource ? this.draft.dataSourceIds : this.draft.workflowActionIds;

    return ids || [];
  }

  get idField() {

    // [1] The draft field of the list this step shows
    const idField = this.isDataSource ? FIELD_DATA_SOURCE_IDS : FIELD_ACTION_IDS;

    return idField;
  }

  get introText() {

    return this.isDataSource ? LABELS.introDataSources : LABELS.introActions;
  }

  get searchPlaceholder() {

    return this.isDataSource ? LABELS.searchDataSources : LABELS.searchActions;
  }

  get addLabel() {

    return this.isDataSource ? LABELS.addDataSource : LABELS.addAction;
  }

  get emptyTitle() {

    return this.isDataSource ? LABELS.emptyDataSourcesTitle : LABELS.emptyActionsTitle;
  }

  get emptyText() {

    return this.isDataSource ? LABELS.emptyDataSourcesText : LABELS.emptyActionsText;
  }

  get pickerNote() {

    return this.isDataSource ? LABELS.noteDataSources : LABELS.noteActions;
  }

  get isEmpty() {

    // [1] Nothing is added yet
    const isEmpty = this.ids.length === 0;

    return isEmpty;
  }

  get showEmptyNote() {

    // [1] Only the actions list has a note for the empty state
    const showEmptyNote = this.isEmpty && !this.isDataSource;

    return showEmptyNote;
  }

  get emptyNote() {

    return LABELS.emptyActionsNote;
  }

  get showList() {

    // [1] The list shows when something is added and the picker is closed
    const showList = !this.isEmpty && !this.isAdding;

    return showList;
  }

  get showEmpty() {

    // [1] The empty state shows when nothing is added and the picker is closed
    const showEmpty = this.isEmpty && !this.isAdding;

    return showEmpty;
  }

  get showSummary() {

    // [1] The summary belongs to the actions list
    const showSummary = this.showList && !this.isDataSource;

    return showSummary;
  }

  get itemViews() {

    // [1] Hand the work to the helper
    const itemViews = buildItemViews(this.kind, this.options, this.ids, this.searchText);

    return itemViews;
  }

  get hasNoMatches() {

    // [1] The search found nothing among what is added
    const hasNoMatches = this.itemViews.length === 0;

    return hasNoMatches;
  }

  get addedHeading() {

    // [1] The heading counts what is added
    const addedHeading = LABELS.addedDirectly + " (" + this.ids.length + ")";

    return addedHeading;
  }

  get summaryRows() {

    // [1] Hand the work to the helper
    const summaryRows = buildSummaryRows(this.options, this.ids, this.objectOptions);

    return summaryRows;
  }

  get findingViews() {

    // [1] Hand the work to the helper
    const findingViews = buildFindingViews(this.findings);

    return findingViews;
  }

  get hasFindings() {

    return this.findingViews.length > 0;
  }

  get findingCountText() {

    // [1] Hand the work to the helper
    const findingCountText = formatFindingCount(this.findingViews.length);

    return findingCountText;
  }

  // Event handlers
  handleSearchInput(event) {

    // [1] Keep what was typed, and the list follows it
    this.searchText = event.target.value;
  }

  handleAddClick() {

    // [1] Open the picker
    this.isAdding = true;
  }

  handlePickerCancel() {

    // [1] Close the picker
    this.isAdding = false;
  }

  handlePickerAdd(event) {

    // [1] Add the ids that were picked, once each
    const pickedIds = event.detail.ids;
    const newIds = pickedIds.filter((id) => !this.ids.includes(id));
    this.reportIds([...this.ids, ...newIds]);

    // [2] Close the picker
    this.isAdding = false;
  }

  handleRemove(event) {

    // [1] Take the item off the agent
    const itemId = event.currentTarget.dataset.key;
    this.reportIds(this.ids.filter((id) => id !== itemId));
  }

  handleSettings() {

    // [1] Tell the tab to open the settings
    this.dispatchEvent(new CustomEvent("gotosettings"));
  }

  // Private methods
  reportIds(ids) {

    // [1] Tell the tab
    const changes = { [this.idField]: ids };
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }
}
