/*
Component Name: aiPromptTemplatesTryIt

=================================================================
=================================================================

Description: The Try it tab: sends a message to the agent with the saved wording and the edited wording, and keeps saved test messages.

Step 1: Load the agents and the saved test messages
Step 2: Run the message on both wordings and show the two replies side by side
Step 3: Save the message, run a saved message or all of them one after another, and delete a saved message
Step 4: Keep the Better or Worse verdict of a saved message

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getAgentOptions from "@salesforce/apex/AIPromptTemplatesController.getAgentOptions";
import getTestMessages from "@salesforce/apex/AIPromptTemplatesController.getTestMessages";
import saveTestMessage from "@salesforce/apex/AIPromptTemplatesController.saveTestMessage";
import deleteTestMessage from "@salesforce/apex/AIPromptTemplatesController.deleteTestMessage";
import runTryIt from "@salesforce/apex/AIPromptTemplatesController.runTryIt";
import setVerdict from "@salesforce/apex/AIPromptTemplatesController.setVerdict";
import { LABELS, SIDE_SAVED, SIDE_EDITED, TOAST_VARIANT_ERROR } from "./aiPromptTemplatesTryItSettings";
import { buildAgentChoices, findAgentOption, buildResultColumn, buildMessageViews, replaceMessage, findMessageByBody, buildPayload, formatErrorMessage } from "./aiPromptTemplatesTryItHelper";

// The Try it tab.
export default class AiPromptTemplatesTryIt extends LightningElement {

  // The saved template. The saved column and the saved messages belong to it.
  _savedTemplate = null;

  @api
  get savedTemplate() {
    return this._savedTemplate;
  }

  set savedTemplate(value) {

    // [1] Load the saved messages again only when another template is set
    const oldId = this._savedTemplate ? this._savedTemplate.templateId : null;
    const newId = value ? value.templateId : null;
    this._savedTemplate = value;
    if (oldId !== newId) {
      this.clearResults();
      this.loadTestMessages();
    }
  }

  // Values passed in by the parent component
  @api draft = null; // The TemplateDetail the admin is editing

  // Values the template reads
  labels = LABELS;

  // State of the tab
  agentOptions = [];
  testMessages = [];
  messageBody = "";
  agentId = "";
  recordId = null;
  savedRun = null;
  editedRun = null;
  currentMessage = null;
  isRunning = false;
  busyMessageId = null;

  // Lifecycle methods
  connectedCallback() {

    // [1] Load the agents the admin can run a message as
    this.loadAgentOptions();
  }

  get isSaved() {

    // [1] A saved template has an id
    const isSaved = Boolean(this._savedTemplate && this._savedTemplate.templateId);

    return isSaved;
  }

  get agentChoices() {

    // [1] Hand the work to the helper
    const agentChoices = buildAgentChoices(this.agentOptions);

    return agentChoices;
  }

  get objectApiName() {

    // [1] The object of the agent picked, blank when it has none
    const agentOption = findAgentOption(this.agentOptions, this.agentId);
    const objectApiName = agentOption && agentOption.objectApiName ? agentOption.objectApiName : "";

    return objectApiName;
  }

  get showRecordPicker() {

    // [1] The record picker needs an object
    const showRecordPicker = this.objectApiName !== "";

    return showRecordPicker;
  }

  get hasMessageText() {

    // [1] A message needs some text
    const hasMessageText = this.messageBody.trim() !== "";

    return hasMessageText;
  }

  get isRunDisabled() {

    // [1] A run needs a message and an agent, and nothing else running
    const isRunDisabled = !this.hasMessageText || !this.agentId || this.isRunning;

    return isRunDisabled;
  }

  get canSaveMessage() {

    // [1] Only a saved template keeps messages, and the same text is saved once
    const isAlreadySaved = findMessageByBody(this.testMessages, this.messageBody) !== null;
    const canSaveMessage = this.isSaved && this.hasMessageText && !isAlreadySaved && !this.isRunning;

    return canSaveMessage;
  }

  get savedTitle() {

    // [1] Say which version the saved column ran
    const version = this._savedTemplate ? this._savedTemplate.version : "";
    const suffix = this._savedTemplate && this._savedTemplate.isActive ? LABELS.savedTitleSuffix : LABELS.savedTitleInactive;
    const savedTitle = LABELS.savedTitlePrefix + version + suffix;

    return savedTitle;
  }

  get savedColumn() {

    // [1] Hand the work to the helper
    const savedColumn = this.isSaved ? buildResultColumn(SIDE_SAVED, this.savedTitle, this.savedRun, this.currentMessage) : null;

    return savedColumn;
  }

  get editedColumn() {

    // [1] Hand the work to the helper
    const editedColumn = buildResultColumn(SIDE_EDITED, LABELS.editedTitle, this.editedRun, this.currentMessage);

    return editedColumn;
  }

  get resultColumns() {

    // [1] The saved column first, then the edited one, leaving out a side that did not run
    const resultColumns = [];
    if (this.savedColumn) resultColumns.push(this.savedColumn);
    if (this.editedColumn) resultColumns.push(this.editedColumn);

    return resultColumns;
  }

  get isSaveDisabled() {

    // [1] The opposite of being able to save
    const isSaveDisabled = !this.canSaveMessage;

    return isSaveDisabled;
  }

  get hasResults() {

    // [1] Show the results once something ran
    const hasResults = this.savedRun !== null || this.editedRun !== null;

    return hasResults;
  }

  get showVerdictHint() {

    // [1] A result with no saved message cannot be marked
    const showVerdictHint = this.hasResults && this.currentMessage === null;

    return showVerdictHint;
  }

  get messageViews() {

    // [1] Hand the work to the helper
    const messageViews = buildMessageViews(this.testMessages, this.busyMessageId, this.isRunning);

    return messageViews;
  }

  get hasMessages() {

    // [1] The list shows when at least one message is saved
    const hasMessages = this.testMessages.length > 0;

    return hasMessages;
  }

  get runAllLabel() {

    // [1] Say how many messages will run
    const runAllLabel = LABELS.runAllPrefix + this.testMessages.length + LABELS.runAllSuffix;

    return runAllLabel;
  }

  // Event handlers
  handleMessageChange(event) {

    // [1] Keep what the admin typed
    this.messageBody = event.target.value;
  }

  handleAgentChange(event) {

    // [1] Keep the agent, and forget the record, which belongs to the old agent's object
    this.agentId = event.detail.value;
    this.recordId = null;
  }

  handleRecordChange(event) {

    // [1] Keep the record the admin picked
    this.recordId = event.detail.recordId || null;
  }

  async handleRunBoth() {

    // [1] A message that is saved keeps its verdicts, so pass its id
    const savedMessage = findMessageByBody(this.testMessages, this.messageBody);
    const testMessageId = savedMessage ? savedMessage.testMessageId : null;

    // [2] Run it
    await this.executeRun(this.messageBody, testMessageId, savedMessage);
  }

  async handleSaveMessage() {

    this.isRunning = true;

    try {

      // [1] Save the message and add it to the list
      const testMessage = await saveTestMessage({ templateId: this._savedTemplate.templateId, messageBody: this.messageBody.trim() });
      this.testMessages = [...this.testMessages, testMessage];

    } catch (error) {

      // [2] Show the reason
      this.showToast(formatErrorMessage(error));

    } finally {

      this.isRunning = false;
    }
  }

  async handleRunMessage(event) {

    // [1] Find the saved message and put its text in the box
    const testMessageId = event.currentTarget.dataset.id;
    const testMessage = this.testMessages.find((item) => item.testMessageId === testMessageId);
    if (!testMessage) return;
    this.messageBody = testMessage.messageBody;

    // [2] Run it
    this.busyMessageId = testMessageId;
    await this.executeRun(testMessage.messageBody, testMessageId, testMessage);
    this.busyMessageId = null;
  }

  async handleRunAll() {

    // [1] Run the saved messages one after another, never together
    const messagesToRun = [...this.testMessages];

    for (const testMessage of messagesToRun) {
      this.messageBody = testMessage.messageBody;
      this.busyMessageId = testMessage.testMessageId;
      // eslint-disable-next-line no-await-in-loop
      const result = await this.executeRun(testMessage.messageBody, testMessage.testMessageId, testMessage);

      // [2] Stop at the first failure to call Apex
      if (result === null) break;
    }

    this.busyMessageId = null;
  }

  async handleDeleteMessage(event) {

    // [1] Delete the saved message and take it off the list
    const testMessageId = event.currentTarget.dataset.id;
    this.isRunning = true;

    try {
      await deleteTestMessage({ testMessageId });
      this.testMessages = this.testMessages.filter((item) => item.testMessageId !== testMessageId);

      // [2] Forget the results when they were from that message
      const isCurrent = this.currentMessage && this.currentMessage.testMessageId === testMessageId;
      if (isCurrent) this.currentMessage = null;

    } catch (error) {
      this.showToast(formatErrorMessage(error));

    } finally {
      this.isRunning = false;
    }
  }

  async handleVerdict(event) {

    // [1] Read which side and which verdict were clicked
    const side = event.currentTarget.dataset.side;
    const verdict = event.currentTarget.dataset.verdict;
    if (!this.currentMessage) return;

    try {

      // [2] Save the verdict and show the new state
      const testMessage = await setVerdict({ testMessageId: this.currentMessage.testMessageId, side, verdict });
      this.currentMessage = testMessage;
      this.testMessages = replaceMessage(this.testMessages, testMessage);

    } catch (error) {

      // [3] Show the reason
      this.showToast(formatErrorMessage(error));
    }
  }

  // Private methods
  async executeRun(messageBody, testMessageId, savedMessage) {

    this.isRunning = true;

    try {

      // [1] Run the message on the saved and the edited wording
      const result = await runTryIt({ templateDetail: buildPayload(this.draft), messageBody, agentId: this.agentId, recordId: this.recordId, testMessageId });

      // [2] Show both replies
      this.savedRun = result.savedRun || null;
      this.editedRun = result.editedRun || null;
      this.currentMessage = result.testMessage || savedMessage || null;

      // [3] Update the row of the saved message that ran
      if (result.testMessage) this.testMessages = replaceMessage(this.testMessages, result.testMessage);

      return result;

    } catch (error) {

      // [4] Show the reason
      this.showToast(formatErrorMessage(error));

      return null;

    } finally {

      this.isRunning = false;
    }
  }

  clearResults() {

    // [1] Forget the replies of the template that was open before
    this.savedRun = null;
    this.editedRun = null;
    this.currentMessage = null;
    this.testMessages = [];
  }

  async loadAgentOptions() {

    try {

      // [1] Read the agents and pick the first one
      this.agentOptions = await getAgentOptions();
      const hasAgents = this.agentOptions.length > 0;
      if (hasAgents && !this.agentId) this.agentId = this.agentOptions[0].agentId;

    } catch (error) {

      // [2] Show the reason
      this.showToast(formatErrorMessage(error));
    }
  }

  async loadTestMessages() {

    // [1] A template that is not saved has no messages
    if (!this.isSaved) return;
    const templateId = this._savedTemplate.templateId;

    try {

      // [2] Read the saved messages
      const testMessages = await getTestMessages({ templateId });
      const isStillOpen = this.isSaved && this._savedTemplate.templateId === templateId;
      if (isStillOpen) this.testMessages = testMessages;

    } catch (error) {

      // [3] Show the reason
      this.showToast(formatErrorMessage(error));
    }
  }

  showToast(message) {

    // [1] Show the message at the top of the page
    const toastEvent = new ShowToastEvent({ message, variant: TOAST_VARIANT_ERROR });
    this.dispatchEvent(toastEvent);
  }
}
