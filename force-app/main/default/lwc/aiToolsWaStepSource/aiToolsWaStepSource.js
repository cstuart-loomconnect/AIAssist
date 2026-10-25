/*
Component Name: aiToolsWaStepSource

=================================================================
=================================================================

Description: Step 2 of the workflow action wizard: the flow or Apex class the action runs.

Step 1: List the active flows, or the classes that implement IAIWorkflowActionExecutor
Step 2: Let the admin pick one, and read the inputs and outputs of what was picked
Step 3: Tell the wizard what was picked

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import getFlows from "@salesforce/apex/AIToolsWorkflowActionController.getFlows";
import getFlowVariables from "@salesforce/apex/AIToolsWorkflowActionController.getFlowVariables";
import getApexClasses from "@salesforce/apex/AIToolsWorkflowActionController.getApexClasses";
import { ACTION_TYPE_APEX, ACTION_TYPE_SCREEN_FLOW, NO_TEXT, LABELS } from "./aiToolsWaStepSourceSettings";
import { buildFlowRows, buildClassRows, buildInputsFromVariables, buildInputsFromSchema, formatErrorMessage } from "./aiToolsWaStepSourceHelper";

// Step 2. It lists what the type allows and reports the pick to the wizard.
export default class AiToolsWaStepSource extends LightningElement {

  // Values passed in by the parent component
  @api draft; // The wizard's draft: actionType and sourceName are read here

  // Values the template reads
  labels = LABELS;

  // State of the step
  flows = [];
  classes = [];
  isBusy = true;
  errorMessage = NO_TEXT;

  // Lifecycle methods
  connectedCallback() {

    // [1] List what the type allows when the step opens
    this.loadOptions();
  }

  get isApex() {

    // [1] An Apex action lists classes
    const isApex = this.draft.actionType === ACTION_TYPE_APEX;

    return isApex;
  }

  get isScreenFlow() {

    // [1] A screen flow lists screen flows
    const isScreenFlow = this.draft.actionType === ACTION_TYPE_SCREEN_FLOW;

    return isScreenFlow;
  }

  get introText() {

    // [1] Say what is listed
    if (this.isApex) return LABELS.introApex;

    return this.isScreenFlow ? LABELS.introScreenFlow : LABELS.introFlow;
  }

  get flowRows() {

    // [1] Hand the work to the helper
    const flowRows = buildFlowRows(this.flows, this.draft.sourceName);

    return flowRows;
  }

  get classRows() {

    // [1] Hand the work to the helper
    const classRows = buildClassRows(this.classes, this.draft.sourceName);

    return classRows;
  }

  get showFlows() {

    // [1] Flows are listed for a flow type once the load is done and there are some
    const showFlows = !this.isApex && !this.isBusy && this.flows.length > 0;

    return showFlows;
  }

  get showClasses() {

    // [1] Classes are listed for an Apex type once the load is done and there are some
    const showClasses = this.isApex && !this.isBusy && this.classes.length > 0;

    return showClasses;
  }

  get showNoFlows() {

    // [1] Say so when there is nothing to pick
    const showNoFlows = !this.isApex && !this.isBusy && this.flows.length === 0;

    return showNoFlows;
  }

  get showNoClasses() {

    // [1] Say so when there is nothing to pick
    const showNoClasses = this.isApex && !this.isBusy && this.classes.length === 0;

    return showNoClasses;
  }

  get showCalloutWarning() {

    // [1] Warn when the picked class says it does something that cannot be undone
    const pickedClass = this.classes.find((apexClass) => apexClass.className === this.draft.sourceName);
    const showCalloutWarning = this.isApex && Boolean(pickedClass && pickedClass.callouts);

    return showCalloutWarning;
  }

  get hasError() {

    // [1] There is an error to show when a call failed
    const hasError = Boolean(this.errorMessage);

    return hasError;
  }

  // Event handlers
  async handleFlowPick(event) {

    // [1] Find the flow that was picked
    const apiName = event.currentTarget.dataset.key;
    const flow = this.flows.find((candidate) => candidate.apiName === apiName);
    this.errorMessage = NO_TEXT;

    try {

      // [2] Read its variables and build the inputs and outputs
      const variables = await getFlowVariables({ flowApiName: apiName });
      const inputs = buildInputsFromVariables(variables, this.isScreenFlow);
      const outputs = variables.filter((variable) => variable.isOutput).map((variable) => ({ name: variable.name, typeLabel: variable.dataType }));

      // [3] Tell the wizard, and name the action after the flow when it has no name yet
      const changes = { sourceName: apiName, sourceLabel: flow.label, flowVersion: flow.versionNumber, inputs, outputs };
      if (!this.draft.actionName) changes.actionName = flow.label.slice(0, 50);
      this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));

    } catch (error) {

      // [4] Show the reason
      this.errorMessage = formatErrorMessage(error);
    }
  }

  handleClassPick(event) {

    // [1] Find the class that was picked
    const className = event.currentTarget.dataset.key;
    const apexClass = this.classes.find((candidate) => candidate.className === className);

    // [2] Build the inputs from what the class says about itself
    const inputs = buildInputsFromSchema(apexClass.inputSchema);
    const changes = { sourceName: className, sourceLabel: className, flowVersion: null, inputs, outputs: [] };
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }

  // Private methods
  async loadOptions() {

    try {

      // [1] List the classes or the flows the type allows
      if (this.isApex) this.classes = await getApexClasses();
      else this.flows = await getFlows({ isScreenFlow: this.isScreenFlow });

    } catch (error) {

      // [2] Show the reason
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isBusy = false;
    }
  }
}
