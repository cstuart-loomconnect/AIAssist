/*
Component Name: aiToolsSkStepTest

=================================================================
=================================================================

Description: Step 4 of the skill wizard: ask an agent's model one question with the skill offered on its own, and see whether it picks the skill and what each step did.

Step 1: Load the agents the skill can be tested with
Step 2: Ask for the agent, the record when the skill needs one, and the question
Step 3: Run the test on the server and show the banner, the reply and each step
Step 4: Tell the wizard how the test ended, so it is saved with the skill

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import getTestAgents from "@salesforce/apex/AIToolsSkillController.getTestAgents";
import runTest from "@salesforce/apex/AIToolsSkillController.runTest";
import { NO_TEXT, LABELS } from "./aiToolsSkStepTestSettings";
import { getBoundObject, buildAgentOptions, buildBannerView, buildMetaText, buildStepViews, formatErrorMessage } from "./aiToolsSkStepTestHelper";

// Step 4. It runs the skill as it is in the wizard and reports how it ended.
export default class AiToolsSkStepTest extends LightningElement {

  // Values passed in by the parent component
  @api draft; // The wizard's draft: tools is read here
  @api skillDetail; // The skill as the wizard would save it, which the test runs

  // Values the template reads
  labels = LABELS;

  // State of the step
  agentOptions = [];
  agentId = NO_TEXT;
  recordId = NO_TEXT;
  question = NO_TEXT;
  isLoadingAgents = true;
  isRunning = false;
  result = null;
  errorMessage = NO_TEXT;

  // Lifecycle methods
  connectedCallback() {

    // [1] Load the agents to test with
    this.loadAgents();
  }

  get boundObject() {

    // [1] Hand the work to the helper
    const boundObject = getBoundObject(this.draft.tools);

    return boundObject;
  }

  get hasBoundObject() {

    // [1] A skill with a bound data source runs on a record of one object, so the record can be picked
    const hasBoundObject = Boolean(this.boundObject);

    return hasBoundObject;
  }

  get isRunDisabled() {

    // [1] The test needs an agent and a question, and runs once at a time
    const isRunDisabled = this.isRunning || !this.agentId || !this.question.trim();

    return isRunDisabled;
  }

  get hasError() {

    // [1] There is an error to show when the test was refused
    const hasError = Boolean(this.errorMessage);

    return hasError;
  }

  get hasResult() {

    // [1] A test has ended
    const hasResult = Boolean(this.result);

    return hasResult;
  }

  get bannerView() {

    // [1] Hand the work to the helper
    const bannerView = buildBannerView(this.result);

    return bannerView;
  }

  get metaText() {

    // [1] Hand the work to the helper
    const metaText = buildMetaText(this.result);

    return metaText;
  }

  get stepViews() {

    // [1] Hand the work to the helper
    const stepViews = buildStepViews(this.result);

    return stepViews;
  }

  get suggestedText() {

    // [1] Name the action the model suggested, when it suggested one
    const suggestedText = this.result && this.result.suggestedActionName ? LABELS.suggested + this.result.suggestedActionName : NO_TEXT;

    return suggestedText;
  }

  // Event handlers
  handleAgentChange(event) {

    // [1] Keep the agent
    this.agentId = event.detail.value;
  }

  handleRecordChange(event) {

    // [1] Keep the record, from the picker or the Id box
    const pickedId = event.detail && event.detail.recordId !== undefined ? event.detail.recordId : event.target.value;
    this.recordId = pickedId || NO_TEXT;
  }

  handleQuestionChange(event) {

    // [1] Keep the question
    this.question = event.target.value || NO_TEXT;
  }

  async handleRunTest() {

    this.isRunning = true;
    this.errorMessage = NO_TEXT;
    this.result = null;

    try {

      // [1] Run the test on the server
      const testRequest = { agentId: this.agentId, recordId: this.recordId || null, question: this.question };
      this.result = await runTest({ skillDetail: this.skillDetail, testRequest });

      // [2] Tell the wizard how it ended, so it is saved with the skill
      this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes: { lastTestStatus: this.result.status, lastTestedOn: new Date().toISOString() } } }));

    } catch (error) {

      // [3] Show the reason
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isRunning = false;
    }
  }

  // Private methods
  async loadAgents() {

    try {

      // [1] Read the agents and pick the first
      const agents = await getTestAgents();
      this.agentOptions = buildAgentOptions(agents);
      if (this.agentOptions.length > 0) this.agentId = this.agentOptions[0].value;

    } catch (error) {

      // [2] Show the reason
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isLoadingAgents = false;
    }
  }
}
