/*
Component Name: aiPoliciesCheckUser

=================================================================
=================================================================

Description: The Check a user box of the AI Policies tab: finds a user and explains which policy they get and why.

Step 1: Search users as the admin types, after a short pause
Step 2: Ask Apex which policy the chosen user gets and show every policy that was considered
Step 3: Offer to assign the user a policy that was ignored, and tell the tab when the admin accepts
Step 4: Check the user again when the tab asks, after an assignment changed

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import findAssignees from "@salesforce/apex/AIPoliciesController.findAssignees";
import checkUser from "@salesforce/apex/AIPoliciesController.checkUser";
import { ASSIGNEE_TYPE_USER, SEARCH_MIN_LENGTH, SEARCH_DELAY_MILLISECONDS, EVENT_ASSIGN, NO_TEXT, LABELS } from "./aiPoliciesCheckUserSettings";
import { buildResultView, formatErrorMessage } from "./aiPoliciesCheckUserHelper";

// The Check a user box. It searches users, shows the answer for the chosen one and offers a fix.
export default class AiPoliciesCheckUser extends LightningElement {

  // Values the template reads
  labels = LABELS;

  // State of the box
  searchText = NO_TEXT;
  matches = [];
  isSearching = false;
  hasSearched = false;
  chosenUser = null;
  result = null;
  isChecking = false;
  errorMessage = NO_TEXT;
  searchTimer = null;
  searchRunId = 0;

  // Lifecycle methods
  disconnectedCallback() {

    // [1] Stop a search that is waiting
    clearTimeout(this.searchTimer);
  }

  // The answer for the chosen user, built for the template.
  get resultView() {

    // [1] Hand the work to the helper, once there is an answer
    const resultView = this.result ? buildResultView(this.result) : null;

    return resultView;
  }

  get hasResult() {

    // [1] The answer shows once Apex has given one
    const hasResult = Boolean(this.result);

    return hasResult;
  }

  get showMatches() {

    // [1] The list of users shows while the admin is choosing one
    const showMatches = this.hasSearched && !this.chosenUser;

    return showMatches;
  }

  get hasMatches() {

    // [1] The list has at least one user
    const hasMatches = this.matches.length > 0;

    return hasMatches;
  }

  get hasErrorMessage() {

    // [1] A message means there is an error to show
    const hasErrorMessage = Boolean(this.errorMessage);

    return hasErrorMessage;
  }

  // Event handlers
  handleSearchInput(event) {

    // [1] Keep what was typed, and forget the user chosen before
    this.searchText = event.target.value;
    this.chosenUser = null;
    this.result = null;
    this.errorMessage = NO_TEXT;

    // [2] Wait for a pause in the typing before searching
    clearTimeout(this.searchTimer);
    const trimmedText = this.searchText.trim();

    if (trimmedText.length < SEARCH_MIN_LENGTH) {

      this.matches = [];
      this.hasSearched = false;
      return;
    }

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = setTimeout(() => this.runSearch(trimmedText), SEARCH_DELAY_MILLISECONDS);
  }

  handleUserPick(event) {

    // [1] Find the user that was clicked
    const userId = event.currentTarget.dataset.id;
    const pickedUser = this.matches.find((match) => match.assigneeId === userId);
    if (!pickedUser) return;

    // [2] Show their name in the box and check them
    this.chosenUser = pickedUser;
    this.searchText = pickedUser.name;
    this.runCheck();
  }

  handleAssign() {

    // [1] Tell the tab to give this user the policy that was ignored
    const detail = { policyId: this.result.ignoredPolicyId, userId: this.chosenUser.assigneeId };
    this.dispatchEvent(new CustomEvent(EVENT_ASSIGN, { detail }));
  }

  // Checks the chosen user again.
  @api
  refresh() {

    // [1] Nothing to check until a user is chosen
    if (this.chosenUser) this.runCheck();
  }

  // Private methods
  async runSearch(trimmedText) {

    // [1] Note which search this is, so a slow answer to an old search is ignored
    this.searchRunId = this.searchRunId + 1;
    const runId = this.searchRunId;
    this.isSearching = true;

    try {

      // [2] Ask Apex for the users whose name matches
      const found = await findAssignees({ policyId: null, assigneeType: ASSIGNEE_TYPE_USER, searchText: trimmedText });
      if (runId !== this.searchRunId) return;
      this.matches = found;
      this.hasSearched = true;

    } catch (error) {

      // [3] Show the reason
      this.errorMessage = formatErrorMessage(error);

    } finally {

      if (runId === this.searchRunId) this.isSearching = false;
    }
  }

  async runCheck() {

    this.isChecking = true;
    this.errorMessage = NO_TEXT;

    try {

      // [1] Ask Apex which policy the user gets and why
      this.result = await checkUser({ userId: this.chosenUser.assigneeId });

    } catch (error) {

      // [2] Show the reason
      this.result = null;
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isChecking = false;
    }
  }
}
