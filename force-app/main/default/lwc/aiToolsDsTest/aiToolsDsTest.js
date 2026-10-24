/*
Component Name: aiToolsDsTest

=================================================================
=================================================================

Description: Step 4 of the data source wizard: run the data source for a record, as the admin or as another user, and see what comes back.

Step 1: Show the record, the inputs the agent fills in, and who to run as
Step 2: Run the data source with Apex and show whether it passed, ran partly or failed
Step 3: Show the rows, the fields a user cannot see and what the agent receives
Step 4: Tell the wizard the result and the values that were tested

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import runTest from "@salesforce/apex/AIToolsController.runTest";
import findUsers from "@salesforce/apex/AIToolsController.findUsers";
import { BINDING_BOUND, USER_SEARCH_MIN_LENGTH, USER_SEARCH_DELAY_MS, CONTROL_CHECKBOX, NO_TEXT, LABELS } from "./aiToolsDsTestSettings";
import { buildInputControls, buildResultView, formatErrorMessage } from "./aiToolsDsTestHelper";

// The Test step.
export default class AiToolsDsTest extends LightningElement {

  // The draft of the wizard. Read only: changes are sent up in the draftchange event.
  @api draft;

  // The data source as it is now, which Apex runs.
  @api detail;

  // The last result, kept by the wizard so it is still there after a trip to another step.
  @api result = null;

  // Values the template reads
  labels = LABELS;

  // State of the step
  isRunning = false;
  errorMessage = NO_TEXT;
  userSearchText = NO_TEXT;
  isUserTyping = false;
  userOptions = [];
  userTimer = null;

  disconnectedCallback() {

    // [1] Stop a search that has not started
    clearTimeout(this.userTimer);
  }

  get isBound() {

    // [1] A bound data source needs a record
    const isBound = this.draft.bindingType === BINDING_BOUND;

    return isBound;
  }

  get hasRecordObject() {

    // [1] The record picker needs to know the object of the record
    const hasRecordObject = Boolean(this.draft.recordObjectApiName);

    return hasRecordObject;
  }

  get hasNoRecordObject() {

    // [1] Without an object, the admin pastes a record Id
    const hasNoRecordObject = !this.hasRecordObject;

    return hasNoRecordObject;
  }

  get inputControls() {

    // [1] Hand the work to the helper
    const inputControls = buildInputControls(this.draft.inputs, this.draft.testInputValues);

    return inputControls;
  }

  get hasInputControls() {

    // [1] There is at least one input to fill in
    const hasInputControls = this.inputControls.length > 0;

    return hasInputControls;
  }

  get runAsDisplay() {

    // [1] Show what is being typed, or the chosen user
    const runAsDisplay = this.isUserTyping ? this.userSearchText : this.draft.testRunAsUserName;

    return runAsDisplay;
  }

  get showUserList() {

    // [1] The list is open while the admin types enough to search
    const showUserList = this.isUserTyping && this.userOptions.length > 0;

    return showUserList;
  }

  get resultView() {

    // [1] Hand the work to the helper
    const resultView = buildResultView(this.result);

    return resultView;
  }

  get hasError() {

    // [1] Show the box only when there is a message
    const hasError = Boolean(this.errorMessage);

    return hasError;
  }

  get isRunDisabled() {

    // [1] Wait while a test runs
    const isRunDisabled = this.isRunning;

    return isRunDisabled;
  }

  // Event handlers
  handleRecordPick(event) {

    // [1] Keep the record the picker chose
    this.sendChange({ testRecordId: event.detail.recordId || NO_TEXT });
  }

  handleRecordInput(event) {

    // [1] Keep the Id that was typed or pasted
    this.sendChange({ testRecordId: event.target.value.trim() });
  }

  handleInputChange(event) {

    // [1] Keep the value, a true or false for a checkbox
    const isCheckbox = event.target.dataset.control === CONTROL_CHECKBOX;
    const value = isCheckbox ? event.target.checked : event.target.value;
    this.sendChange({ testInputValues: { ...this.draft.testInputValues, [event.target.dataset.name]: value } });
  }

  handleUserInput(event) {

    // [1] Keep what is being typed, and search once there is enough to search for
    this.userSearchText = event.detail.value;
    this.isUserTyping = true;
    clearTimeout(this.userTimer);

    if (this.userSearchText.trim().length < USER_SEARCH_MIN_LENGTH) {

      this.userOptions = [];
      return;
    }

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.userTimer = setTimeout(() => this.searchUsers(this.userSearchText), USER_SEARCH_DELAY_MS);
  }

  handleUserBlur() {

    // [1] Stop typing, so the chosen user is shown again
    this.isUserTyping = false;
  }

  handleUserPick(event) {

    // [1] Run as the user that was picked
    const dataset = event.currentTarget.dataset;
    this.isUserTyping = false;
    this.userOptions = [];
    this.sendChange({ testRunAsUserId: dataset.userId, testRunAsUserName: dataset.userName });
  }

  handleUseMyself() {

    // [1] Run as the person testing
    this.sendChange({ testRunAsUserId: NO_TEXT, testRunAsUserName: NO_TEXT });
  }

  async handleRunTest() {

    // [1] A bound data source needs a record to run against
    this.errorMessage = NO_TEXT;

    if (this.isBound && !this.draft.testRecordId) {

      this.errorMessage = LABELS.needsRecord;
      return;
    }

    this.isRunning = true;

    try {

      // [2] Run it with the record, the inputs and the user chosen
      const inputValues = JSON.parse(JSON.stringify(this.draft.testInputValues));
      const request = { recordId: this.draft.testRecordId || null, inputValues, runAsUserId: this.draft.testRunAsUserId || null };
      const dataSourceDetail = JSON.parse(JSON.stringify(this.detail));
      const result = await runTest({ dataSourceDetail, testRequest: request });

      // [3] Tell the wizard, which keeps the result
      this.dispatchEvent(new CustomEvent("testresult", { detail: { result } }));

    } catch (error) {

      // [4] Show the reason
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isRunning = false;
    }
  }

  // Private methods
  async searchUsers(searchText) {

    try {

      // [1] Find the users whose name or username holds the text
      this.userOptions = await findUsers({ searchText });

    } catch (error) {

      // [2] Show the reason
      this.errorMessage = formatErrorMessage(error);
    }
  }

  sendChange(changes) {

    // [1] Send the change up to the wizard
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }
}
