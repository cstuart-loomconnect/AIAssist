/*
Component Name: aiPoliciesAssignDialog

=================================================================
=================================================================

Description: The Add assignment dialog: pick a user or permission set to give the policy to.

Step 1: Let the admin choose between users and permission sets and search by name
Step 2: Show each match with the policy it gets today
Step 3: Warn when the pick already has a policy, and what that means
Step 4: Tell the tab whether the admin cancelled or confirmed, with the pick

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import findAssignees from "@salesforce/apex/AIPoliciesController.findAssignees";
import getAssignmentWarning from "@salesforce/apex/AIPoliciesController.getAssignmentWarning";
import {
  ASSIGNEE_TYPE_USER,
  ASSIGNEE_TYPE_PERMISSION_SET,
  SEARCH_MIN_LENGTH,
  SEARCH_DELAY_MILLISECONDS,
  EVENT_CANCEL,
  EVENT_CONFIRM,
  NO_TEXT,
  LABELS
} from "./aiPoliciesAssignDialogSettings";
import {
  buildOptionViews,
  buildTypeButtons,
  formatErrorMessage
} from "./aiPoliciesAssignDialogHelper";

// The Add assignment dialog.
export default class AiPoliciesAssignDialog extends LightningElement {
  // Values passed in by the parent component
  @api policyId; // The policy the assignment is for
  @api policyName = NO_TEXT; // The name of that policy
  @api isSaving = false; // True while the assignment is saved, so the buttons wait
  @api errorMessage = NO_TEXT; // The message from the last failed assignment, or blank

  // Values the template reads
  labels = LABELS;

  // State of the dialog
  assigneeType = ASSIGNEE_TYPE_PERMISSION_SET;
  searchText = NO_TEXT;
  options = [];
  selectedId = null;
  warningMessage = NO_TEXT;
  searchErrorMessage = NO_TEXT;
  isSearching = false;
  hasSearched = false;
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
    const isUser = this.assigneeType === ASSIGNEE_TYPE_USER;
    const searchLabel = isUser
      ? LABELS.searchUsers
      : LABELS.searchPermissionSets;

    return searchLabel;
  }

  get optionViews() {
    // [1] Hand the work to the helper
    const optionViews = buildOptionViews(
      this.options,
      this.assigneeType,
      this.selectedId
    );

    return optionViews;
  }

  get showOptions() {
    // [1] The list shows once a search has run and found something
    const showOptions = this.hasSearched && this.options.length > 0;

    return showOptions;
  }

  get showNoMatches() {
    // [1] Say so when a search is done and found nothing
    const showNoMatches =
      this.hasSearched && !this.isSearching && this.options.length === 0;

    return showNoMatches;
  }

  get hasWarning() {
    // [1] A message means there is a warning to show
    const hasWarning = Boolean(this.warningMessage);

    return hasWarning;
  }

  get shownError() {
    // [1] A problem with the search comes before one from the last assignment
    const shownError = this.searchErrorMessage || this.errorMessage;

    return shownError;
  }

  get hasError() {
    // [1] A message means there is an error to show
    const hasError = Boolean(this.shownError);

    return hasError;
  }

  get confirmLabel() {
    // [1] The button says Assigning while the assignment is saved
    const confirmLabel = this.isSaving ? LABELS.saving : LABELS.assign;

    return confirmLabel;
  }

  get isConfirmDisabled() {
    // [1] Nothing happens twice, and an assignee must be picked first
    const isConfirmDisabled = this.isSaving || !this.selectedId;

    return isConfirmDisabled;
  }

  // Event handlers
  handleTypeClick(event) {
    // [1] Switch between users and permission sets, and start the list again
    this.assigneeType = event.currentTarget.dataset.value;
    this.resetResults();
    if (this.searchText.trim().length >= SEARCH_MIN_LENGTH)
      this.runSearch(this.searchText.trim());
  }

  handleSearchInput(event) {
    // [1] Keep what was typed, and start the list again
    this.searchText = event.target.value;
    this.resetResults();

    // [2] Wait for a pause in the typing before searching
    clearTimeout(this.searchTimer);
    const trimmedText = this.searchText.trim();
    if (trimmedText.length < SEARCH_MIN_LENGTH) return;

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = setTimeout(
      () => this.runSearch(trimmedText),
      SEARCH_DELAY_MILLISECONDS
    );
  }

  handleOptionChange(event) {
    // [1] Keep the assignee that was picked
    this.selectedId = event.target.value;
    this.warningMessage = NO_TEXT;

    // [2] Ask what picking it will do
    this.loadWarning(this.selectedId);
  }

  handleCancel() {
    // [1] Tell the tab the admin changed their mind
    this.dispatchEvent(new CustomEvent(EVENT_CANCEL));
  }

  handleConfirm() {
    // [1] Tell the tab to assign the policy to the pick
    const detail = {
      assigneeType: this.assigneeType,
      assigneeId: this.selectedId
    };
    this.dispatchEvent(new CustomEvent(EVENT_CONFIRM, { detail }));
  }

  // Private methods
  resetResults() {
    // [1] Forget the list, the pick and the warning
    this.options = [];
    this.selectedId = null;
    this.warningMessage = NO_TEXT;
    this.searchErrorMessage = NO_TEXT;
    this.hasSearched = false;
    this.searchRunId = this.searchRunId + 1;
  }

  async runSearch(trimmedText) {
    // [1] Note which search this is, so a slow answer to an old search is ignored
    this.searchRunId = this.searchRunId + 1;
    const runId = this.searchRunId;
    this.isSearching = true;

    try {
      // [2] Ask Apex for the assignees whose name matches
      const found = await findAssignees({
        policyId: this.policyId,
        assigneeType: this.assigneeType,
        searchText: trimmedText
      });
      if (runId !== this.searchRunId) return;
      this.options = found;
      this.hasSearched = true;
    } catch (error) {
      // [3] Show the reason
      if (runId === this.searchRunId)
        this.searchErrorMessage = formatErrorMessage(error);
    } finally {
      if (runId === this.searchRunId) this.isSearching = false;
    }
  }

  async loadWarning(assigneeId) {
    try {
      // [1] Ask Apex what happens when this assignee is added
      const warning = await getAssignmentWarning({
        policyId: this.policyId,
        assigneeType: this.assigneeType,
        assigneeId
      });
      if (assigneeId !== this.selectedId) return;
      this.warningMessage = warning.hasWarning ? warning.message : NO_TEXT;
    } catch (error) {
      // [2] Show the reason
      this.searchErrorMessage = formatErrorMessage(error);
    }
  }
}
