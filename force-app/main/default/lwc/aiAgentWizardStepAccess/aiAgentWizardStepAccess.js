/*
Component Name: aiAgentWizardStepAccess

=================================================================
=================================================================

Description: Step 7 of the AI Agent Wizard: who can use the agent, the people and permission sets assigned to it, and a check of one user.

Step 1: Show the two access modes, and the list of assignments for Assigned users only
Step 2: Add assignments with a dialog, and switch them on and off
Step 3: Check whether one user would have the agent
Step 4: Show how many users will see the agent, and what the Apex checks found
Step 5: Tell the tab what changed

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import searchAssignees from "@salesforce/apex/AIAgentWizardController.searchAssignees";
import checkUser from "@salesforce/apex/AIAgentWizardController.checkUser";
import { ACCESS_ALL, ASSIGNEE_USER, SEARCH_MIN_LENGTH, SEARCH_DELAY_MILLISECONDS, NOTE_SUCCESS_CLASS, NOTE_DANGER_CLASS, NO_TEXT, LABELS } from "./aiAgentWizardStepAccessSettings";
import { buildAccessCards, buildAssignmentViews, getAssignmentKey, buildUserBanner, buildPickerNote, buildFindingViews, formatFindingCount, formatErrorMessage } from "./aiAgentWizardStepAccessHelper";

// Step 7. It shows the draft and reports every change to the tab.
export default class AiAgentWizardStepAccess extends LightningElement {

  // Values passed in by the parent component
  @api draft; // The tab's draft: accessMode, assignments and objectApiNames are read here
  @api page; // The wizard page: assistUserCount is read here
  @api objectOptions = []; // [AIAgentWizardDataStructure.ObjectOption] for the labels of objects
  @api accessUserCount = null; // The users who would see the agent, from the last check
  @api findings = []; // The findings of this step: [AIAgentWizardDataStructure.Finding]

  // Values the template reads
  labels = LABELS;

  // State of the step
  isDialogOpen = false;
  userSearchText = NO_TEXT;
  userMatches = [];
  hasSearched = false;
  isSearching = false;
  isCheckingUser = false;
  userCheck = null;
  errorMessage = NO_TEXT;
  searchTimer = null;
  searchRunId = 0;

  // Lifecycle methods
  disconnectedCallback() {

    // [1] Stop a search that is waiting
    clearTimeout(this.searchTimer);
  }

  get accessCards() {

    // [1] Hand the work to the helper
    const accessCards = buildAccessCards(this.draft.accessMode);

    return accessCards;
  }

  get isAssignedOnly() {

    // [1] The list of assignments belongs to Assigned users only
    const isAssignedOnly = this.draft.accessMode !== ACCESS_ALL;

    return isAssignedOnly;
  }

  get isAllUsers() {

    return this.draft.accessMode === ACCESS_ALL;
  }

  get assignmentViews() {

    // [1] Hand the work to the helper
    const assignmentViews = buildAssignmentViews(this.draft.assignments);

    return assignmentViews;
  }

  get hasNoAssignments() {

    // [1] Nobody is assigned yet
    const hasNoAssignments = this.assignmentViews.length === 0;

    return hasNoAssignments;
  }

  get bannerText() {

    // [1] Hand the work to the helper
    const bannerText = buildUserBanner(this.draft.accessMode, this.accessUserCount, this.page.assistUserCount, this.draft.objectApiNames, this.objectOptions);

    return bannerText;
  }

  get hasBanner() {

    return Boolean(this.bannerText);
  }

  get pickerNote() {

    // [1] Hand the work to the helper
    const pickerNote = buildPickerNote(this.draft.objectApiNames, this.objectOptions);

    return pickerNote;
  }

  get showUserMatches() {

    // [1] The list shows once a search found something
    const showUserMatches = this.hasSearched && this.userMatches.length > 0;

    return showUserMatches;
  }

  get showNoMatches() {

    // [1] Say so when a search is done and found nothing
    const showNoMatches = this.hasSearched && !this.isSearching && this.userMatches.length === 0;

    return showNoMatches;
  }

  get hasUserCheck() {

    return Boolean(this.userCheck);
  }

  get userCheckText() {

    // [1] The name, whether they have access, and why
    const verdict = this.userCheck.hasAccess ? LABELS.hasAccess : LABELS.noAccess;
    const userCheckText = this.userCheck.userName + verdict + " " + (this.userCheck.reason || NO_TEXT);

    return userCheckText;
  }

  get userCheckClass() {

    // [1] Green when they have access, red when not
    const userCheckClass = this.userCheck.hasAccess ? NOTE_SUCCESS_CLASS : NOTE_DANGER_CLASS;

    return userCheckClass;
  }

  get hasError() {

    return Boolean(this.errorMessage);
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
  handleAccessClick(event) {

    // [1] Keep who can use the agent
    this.reportChanges({ accessMode: event.currentTarget.dataset.value });
  }

  handleAddClick() {

    // [1] Open the dialog
    this.isDialogOpen = true;
  }

  handleDialogCancel() {

    // [1] Close the dialog
    this.isDialogOpen = false;
  }

  handleDialogAdd(event) {

    // [1] Add the people and permission sets that were picked
    const assignments = [...(this.draft.assignments || []), ...event.detail.assignees];
    this.reportChanges({ assignments });

    // [2] Close the dialog
    this.isDialogOpen = false;
  }

  handleToggleChange(event) {

    // [1] Switch one assignment on or off
    const key = event.currentTarget.dataset.key;
    const isActive = event.target.checked;
    const assignments = (this.draft.assignments || []).map((assignment) => (getAssignmentKey(assignment) === key ? { ...assignment, isActive } : assignment));
    this.reportChanges({ assignments });
  }

  handleUserSearchInput(event) {

    // [1] Keep what was typed, and start the list again
    this.userSearchText = event.target.value;
    this.searchRunId = this.searchRunId + 1;
    this.hasSearched = false;
    this.userCheck = null;
    this.errorMessage = NO_TEXT;
    clearTimeout(this.searchTimer);

    // [2] Wait for a pause in the typing before searching
    const trimmedText = this.userSearchText.trim();
    if (trimmedText.length < SEARCH_MIN_LENGTH) return;

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = setTimeout(() => this.runUserSearch(trimmedText), SEARCH_DELAY_MILLISECONDS);
  }

  handleUserPick(event) {

    // [1] Check the user that was picked
    const userId = event.currentTarget.dataset.key;
    const picked = this.userMatches.find((match) => match.userId === userId);
    this.userSearchText = picked.label;
    this.userMatches = [];
    this.hasSearched = false;
    this.runUserCheck(userId);
  }

  // Private methods
  async runUserSearch(trimmedText) {

    // [1] Note which search this is, so a slow answer to an old search is ignored
    this.searchRunId = this.searchRunId + 1;
    const runId = this.searchRunId;
    this.isSearching = true;

    try {

      // [2] Ask Apex for the users whose name matches
      const found = await searchAssignees({ term: trimmedText });
      if (runId !== this.searchRunId) return;
      this.userMatches = found.filter((match) => match.assigneeType === ASSIGNEE_USER);
      this.hasSearched = true;

    } catch (error) {

      // [3] Show the reason
      if (runId === this.searchRunId) this.errorMessage = formatErrorMessage(error);

    } finally {

      if (runId === this.searchRunId) this.isSearching = false;
    }
  }

  async runUserCheck(userId) {

    this.isCheckingUser = true;
    this.errorMessage = NO_TEXT;

    try {

      // [1] Ask Apex whether this user would have the agent
      this.userCheck = await checkUser({ draftJson: JSON.stringify(this.draft), userId });

    } catch (error) {

      // [2] Show the reason
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isCheckingUser = false;
    }
  }

  reportChanges(changes) {

    // [1] Tell the tab
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }
}
