/*
Component Name: aiAgentWizardStepReview

=================================================================
=================================================================

Description: Step 8 of the AI Agent Wizard: the summary of the agent, everything the checks found, and a trial message before activating.

Step 1: Say whether the agent is ready to activate, and list what is found
Step 2: Show a summary card for each step, with an Edit link to it
Step 3: Send a trial message through the agent's model, prompt template and persona
Step 4: Tell the tab which step to jump to

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import tryAgent from "@salesforce/apex/AIAgentWizardController.tryAgent";
import { NO_TEXT, LABELS } from "./aiAgentWizardStepReviewSettings";
import { buildBanner, buildFindingViews, buildSummaryCards, formatTrialMeta, formatErrorMessage } from "./aiAgentWizardStepReviewHelper";

// Step 8. It shows the draft and tells the tab which step to jump to.
export default class AiAgentWizardStepReview extends LightningElement {

  // Values passed in by the parent component
  @api draft; // The tab's draft: every step's values are read here
  @api page; // The wizard page: the lists the draft points at are read here
  @api objectOptions = []; // [AIAgentWizardDataStructure.ObjectOption] for the labels of objects
  @api findings = []; // Everything the checks found and the local problems: [AIAgentWizardDataStructure.Finding]
  @api modelTest = null; // The last connection check the tab kept: { modelId, isSuccessful, text }
  @api accessUserCount = null; // The users who would see the agent, from the last check
  @api isChecking = false; // True while the tab checks the draft

  // Values the template reads
  labels = LABELS;

  // State of the trial
  trialMessage = NO_TEXT;
  trialRecordId = null;
  trialReply = NO_TEXT;
  trialMeta = NO_TEXT;
  trialError = NO_TEXT;
  isTrying = false;

  get banner() {

    // [1] Hand the work to the helper
    const banner = buildBanner(this.findings);

    return banner;
  }

  get bannerClass() {

    // [1] Red when blocked, green when ready
    const bannerClass = this.banner.isBlocked ? "aiawre-note aiawre-note_danger" : "aiawre-note aiawre-note_success";

    return bannerClass;
  }

  get findingViews() {

    // [1] Hand the work to the helper
    const findingViews = buildFindingViews(this.findings);

    return findingViews;
  }

  get hasFindings() {

    return this.findingViews.length > 0;
  }

  get summaryCards() {

    // [1] Hand the work to the helper
    const summaryCards = buildSummaryCards(this.draft, this.page, this.objectOptions, this.modelTest);

    return summaryCards;
  }

  get hasModel() {

    // [1] A trial needs a model
    const hasModel = Boolean(this.draft.modelConfigurationId);

    return hasModel;
  }

  get firstObject() {

    // [1] The record picker offers records of the first object
    const objectApiNames = this.draft.objectApiNames || [];
    const firstObject = objectApiNames.length > 0 ? objectApiNames[0] : null;

    return firstObject;
  }

  get hasReply() {

    return Boolean(this.trialReply);
  }

  get hasTrialError() {

    return Boolean(this.trialError);
  }

  get sendLabel() {

    // [1] The button says Sending while the trial runs
    const sendLabel = this.isTrying ? LABELS.sending : LABELS.send;

    return sendLabel;
  }

  get isSendDisabled() {

    // [1] A trial needs a message, and one runs at a time
    const isSendDisabled = this.isTrying || !this.trialMessage.trim();

    return isSendDisabled;
  }

  // Event handlers
  handleEditClick(event) {

    // [1] Tell the tab which step to show
    const step = Number(event.currentTarget.dataset.step);
    this.dispatchEvent(new CustomEvent("gotostep", { detail: { step } }));
  }

  handleMessageInput(event) {

    // [1] Keep the message
    this.trialMessage = event.target.value;
  }

  handleRecordChange(event) {

    // [1] Keep the record the trial runs on
    this.trialRecordId = event.detail.recordId || null;
  }

  async handleSend() {

    this.isTrying = true;
    this.trialError = NO_TEXT;
    this.trialReply = NO_TEXT;
    this.trialMeta = NO_TEXT;

    try {

      // [1] Ask Apex to run the message through the agent's model, prompt template and persona
      const result = await tryAgent({ draftJson: JSON.stringify(this.draft), message: this.trialMessage, recordId: this.trialRecordId });

      // [2] Show the reply, or why it failed
      if (result.isSuccessful) {

        this.trialReply = result.replyText;
        this.trialMeta = formatTrialMeta(result);

      } else {

        this.trialError = LABELS.trialFailed + (result.errorMessage || NO_TEXT);
      }

    } catch (error) {

      // [3] Show the reason
      this.trialError = formatErrorMessage(error);

    } finally {

      this.isTrying = false;
    }
  }
}
