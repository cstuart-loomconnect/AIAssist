/*
Component Name: aiToolsDsApex

=================================================================
=================================================================

Description: Step 2 of the data source wizard for an Apex data source: pick the class that implements IAIDataSourceExecutor.

Step 1: Load the classes that implement the interface and the inputs each one describes
Step 2: Show them in a table, or an empty message with a way to switch to SOQL
Step 3: Tell the wizard the class that was picked and its inputs

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getApexClassOptions from "@salesforce/apex/AIToolsController.getApexClassOptions";
import { SOURCE_TYPE_SOQL, NO_TEXT, APEX_EXAMPLE, TOAST_VARIANT_SUCCESS, TOAST_VARIANT_ERROR, LABELS } from "./aiToolsDsApexSettings";
import { buildClassViews, formatErrorMessage } from "./aiToolsDsApexHelper";

// The Apex class step.
export default class AiToolsDsApex extends LightningElement {

  // The draft of the wizard. Read only: changes are sent up in the draftchange event.
  @api draft;

  // Values the template reads
  labels = LABELS;

  // State of the step
  classOptions = [];
  isBusy = true;
  errorMessage = NO_TEXT;

  // Lifecycle methods
  connectedCallback() {

    // [1] Load the classes when the step opens
    this.loadClasses();
  }

  get classViews() {

    // [1] Hand the work to the helper
    const classViews = buildClassViews(this.classOptions, this.draft.apexClassName);

    return classViews;
  }

  get hasClasses() {

    // [1] There is at least one class
    const hasClasses = this.classOptions.length > 0;

    return hasClasses;
  }

  get showEmpty() {

    // [1] Say so when the load is done and there is no class
    const showEmpty = !this.isBusy && !this.hasClasses;

    return showEmpty;
  }

  get hasError() {

    // [1] Show the box only when there is a message
    const hasError = Boolean(this.errorMessage);

    return hasError;
  }

  // Event handlers
  handleClassPick(event) {

    // [1] Take the class that was picked, with the inputs it describes, if it describes any
    const className = event.currentTarget.dataset.className;
    const option = this.classOptions.find((item) => item.className === className);
    this.sendChange({ apexClassName: className, apexDeclaredSchema: option.declaredInputSchema || NO_TEXT });
  }

  handleSwitchToSoql() {

    // [1] Make this a SOQL data source, so the step shows the query builder
    this.sendChange({ sourceType: SOURCE_TYPE_SOQL });
  }

  async handleCopyInterface() {

    // [1] Copy the example class, and say whether it worked
    try {

      await navigator.clipboard.writeText(APEX_EXAMPLE);
      this.showToast(LABELS.copied, TOAST_VARIANT_SUCCESS);

    } catch {

      this.showToast(LABELS.copyFailed, TOAST_VARIANT_ERROR);
    }
  }

  // Private methods
  async loadClasses() {

    try {

      // [1] Read the classes
      this.classOptions = await getApexClassOptions();

    } catch (error) {

      // [2] Show the reason
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isBusy = false;
    }
  }

  sendChange(changes) {

    // [1] Send the change up to the wizard
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }

  showToast(message, variant) {

    // [1] Show the message at the top of the page
    const toastEvent = new ShowToastEvent({ message, variant });
    this.dispatchEvent(toastEvent);
  }
}
