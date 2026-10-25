/*
Component Name: aiAgentWizardAssigneeDialog

=================================================================
=================================================================

Description: The Add assignment dialog of the AI Agent Wizard: search for users or permission sets and tick the ones to add.

Step 1: Let the admin choose between permission sets and users, and search by name
Step 2: Show each match, and which are already on the agent
Step 3: Tell the step which ones to add, or that the admin cancelled

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import searchAssignees from "@salesforce/apex/AIAgentWizardController.searchAssignees";
import { ASSIGNEE_USER, ASSIGNEE_PERMISSION_SET, SEARCH_MIN_LENGTH, SEARCH_DELAY_MILLISECONDS, NO_TEXT, LABELS } from "./aiAgentWizardAssigneeDialogSettings";
import { buildTypeButtons, buildOptionViews, buildNewAssignments, formatErrorMessage } from "./aiAgentWizardAssigneeDialogHelper";

// The Add assignment dialog.
export default class AiAgentWizardAssigneeDialog extends LightningElement {

  // Values passed in by the parent component
  @api assignments = []; // The assignments the agent already has: [AIAgentWizardDataStructure.AssignmentView]

  // Values the template reads
  labels = LABELS;

  // State of the dialog
  assigneeType = ASSIGNEE_PERMISSION_SET;
  searchText = NO_TEXT;
  matches = [];
  selectedKeys = [];
  isSearching = false;
  hasSearched = false;
  errorMessage = NO_TEXT;
  searchTimer = null;
  searchRunId = 0;

  // Lifecycle methods
  disconnectedCallback() {

    // [1] Stop a search that is waiting
    clearTimeout(this.searchTimer);
  }

  get typeButtons() {

    // [1] Hand the work to the helper
    const typeButtons = buildTypeButtons(this.assigneeType);

    return typeButtons;
  }

  get searchLabel() {

    // [1] The box is named for what it searches
    const searchLabel = this.assigneeType === ASSIGNEE_USER ? LABELS.searchUsers : LABELS.searchPermissionSets;

    return searchLabel;
  }

  get optionViews() {

    // [1] Hand the work to the helper
    const optionViews = buildOptionViews(this.matches, this.assigneeType, this.assignments, this.selectedKeys);

    return optionViews;
  }

  get showOptions() {

    // [1] The list shows once a search has run and found something
    const showOptions = this.hasSearched && this.optionViews.length > 0;

    return showOptions;
  }

  get showNoMatches() {

    // [1] Say so when a search is done and found nothing
    const showNoMatches = this.hasSearched && !this.isSearching && this.optionViews.length === 0;

    return showNoMatches;
  }

  get showTypeMore() {

    // [1] Say how to start before the first search
    const showTypeMore = !this.hasSearched && !this.isSearching;

    return showTypeMore;
  }

  get hasError() {

    return Boolean(this.errorMessage);
  }

  get addLabel() {

    // [1] The button says how many it adds
    const addLabel = this.selectedKeys.length > 0 ? LABELS.add + " " + this.selectedKeys.length : LABELS.add;

    return addLabel;
  }

  get isAddDisabled() {

    // [1] Nothing is added until something is ticked
    const isAddDisabled = this.selectedKeys.length === 0;

    return isAddDisabled;
  }

  // Event handlers
  handleTypeClick(event) {

    // [1] Switch between permission sets and users, and keep the matches of the search
    this.assigneeType = event.currentTarget.dataset.value;
  }

  handleSearchInput(event) {

    // [1] Keep what was typed, and start the list again
    this.searchText = event.target.value;
    this.searchRunId = this.searchRunId + 1;
    this.hasSearched = false;
    this.errorMessage = NO_TEXT;
    clearTimeout(this.searchTimer);

    // [2] Wait for a pause in the typing before searching
    const trimmedText = this.searchText.trim();
    if (trimmedText.length < SEARCH_MIN_LENGTH) return;

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = setTimeout(() => this.runSearch(trimmedText), SEARCH_DELAY_MILLISECONDS);
  }

  handleOptionChange(event) {

    // [1] Tick or untick the row
    const key = event.currentTarget.dataset.key;
    const isTicked = event.currentTarget.checked;
    const others = this.selectedKeys.filter((selectedKey) => selectedKey !== key);
    this.selectedKeys = isTicked ? [...others, key] : others;
  }

  handleCancel() {

    // [1] Tell the step the admin changed their mind
    this.dispatchEvent(new CustomEvent("cancel"));
  }

  handleAdd() {

    // [1] Tell the step which assignments to add
    const assignees = buildNewAssignments(this.matches, this.selectedKeys);
    this.dispatchEvent(new CustomEvent("add", { detail: { assignees } }));
  }

  // Private methods
  async runSearch(trimmedText) {

    // [1] Note which search this is, so a slow answer to an old search is ignored
    this.searchRunId = this.searchRunId + 1;
    const runId = this.searchRunId;
    this.isSearching = true;

    try {

      // [2] Ask Apex for the users and permission sets whose name matches
      const found = await searchAssignees({ term: trimmedText });
      if (runId !== this.searchRunId) return;
      this.matches = found;
      this.hasSearched = true;

    } catch (error) {

      // [3] Show the reason
      if (runId === this.searchRunId) this.errorMessage = formatErrorMessage(error);

    } finally {

      if (runId === this.searchRunId) this.isSearching = false;
    }
  }
}
