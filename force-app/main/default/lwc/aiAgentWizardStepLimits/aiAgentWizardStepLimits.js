/*
Component Name: aiAgentWizardStepLimits

=================================================================
=================================================================

Description: Step 6 of the AI Agent Wizard: the limits of a conversation, how tokens are counted and what that adds up to.

Step 1: Show the three limits, with the problems the tab and the Apex checks found
Step 2: Show how tokens are counted
Step 3: Show the estimated use, worked out from the draft, the users and the usage policy
Step 4: Tell the tab what changed

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { FIELD_MESSAGES, FIELD_TOKENS, FIELD_ROUNDS, NO_TEXT, LABELS } from "./aiAgentWizardStepLimitsSettings";
import { buildEstimateRows, buildFindingMessages, formatWords, buildTrackingCards, buildFormElementClass, parseNumberOrNull } from "./aiAgentWizardStepLimitsHelper";

// Step 6. It shows the draft and reports every change to the tab.
export default class AiAgentWizardStepLimits extends LightningElement {

  // Values passed in by the parent component
  @api draft; // The tab's draft: the limits and the token counting method are read here
  @api page; // The wizard page: orgToolCallingCap and policy are read here
  @api accessUserCount = null; // The users who would see the agent, from the last check
  @api findings = []; // The findings of this step: [AIAgentWizardDataStructure.Finding]
  @api fieldErrors = {}; // The problems to show, keyed by field name

  // Values the template reads
  labels = LABELS;

  get findingMessages() {

    // [1] Hand the work to the helper
    const findingMessages = buildFindingMessages(this.findings);

    return findingMessages;
  }

  get hasFindings() {

    return this.findingMessages.hasAny;
  }

  get showEstimate() {

    // [1] The estimate shows while the limits have no warning
    const showEstimate = !this.hasFindings;

    return showEstimate;
  }

  get estimateRows() {

    // [1] Hand the work to the helper
    const estimateRows = buildEstimateRows(this.draft, this.accessUserCount, this.page.policy);

    return estimateRows;
  }

  get messagesError() {

    return this.fieldErrors[FIELD_MESSAGES] || NO_TEXT;
  }

  get tokensError() {

    // [1] A problem with the number comes before a warning about it
    const tokensError = this.fieldErrors[FIELD_TOKENS] || this.findingMessages.tokens;

    return tokensError;
  }

  get roundsError() {

    // [1] A problem with the number comes before a warning about it
    const roundsError = this.fieldErrors[FIELD_ROUNDS] || this.findingMessages.rounds;

    return roundsError;
  }

  get messagesClass() {

    return buildFormElementClass(this.messagesError);
  }

  get tokensClass() {

    return buildFormElementClass(this.tokensError);
  }

  get roundsClass() {

    return buildFormElementClass(this.roundsError);
  }

  get tokensHelp() {

    // [1] How many words the limit is
    const tokensHelp = LABELS.tokensHelpBefore + formatWords(this.draft.maxTokensPerConversation) + LABELS.tokensHelpAfter;

    return tokensHelp;
  }

  get hasOrgCap() {

    // [1] The cap is only mentioned when there is one
    const hasOrgCap = Boolean(this.page.orgToolCallingCap);

    return hasOrgCap;
  }

  get roundsHelp() {

    // [1] The cap the org sets
    const roundsHelp = LABELS.roundsHelpBefore + this.page.orgToolCallingCap + LABELS.roundsHelpAfter;

    return roundsHelp;
  }

  get trackingCards() {

    // [1] Hand the work to the helper
    const trackingCards = buildTrackingCards(this.draft.tokenTrackingMethod);

    return trackingCards;
  }

  // Event handlers
  handleMessagesInput(event) {

    // [1] Keep the most messages
    this.reportChanges({ maxMessagesPerConversation: parseNumberOrNull(event.target.value) });
  }

  handleTokensInput(event) {

    // [1] Keep the most tokens
    this.reportChanges({ maxTokensPerConversation: parseNumberOrNull(event.target.value) });
  }

  handleRoundsInput(event) {

    // [1] Keep the most tool-calling rounds
    this.reportChanges({ maxToolCallingIterations: parseNumberOrNull(event.target.value) });
  }

  handleTrackingClick(event) {

    // [1] Keep how tokens are counted
    this.reportChanges({ tokenTrackingMethod: event.currentTarget.dataset.value });
  }

  // Private methods
  reportChanges(changes) {

    // [1] Tell the tab
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }
}
