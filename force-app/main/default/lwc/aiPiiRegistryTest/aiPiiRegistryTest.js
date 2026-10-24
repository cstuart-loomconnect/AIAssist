/*
Component Name: aiPiiRegistryTest

=================================================================
=================================================================

Description: The Test masking tab: pick a real record and see what the AI provider would get instead of its PII.

Step 1: Let the admin pick a record of the registered object
Step 2: Run the masking on the record with Apex, which saves and sends nothing
Step 3: Show the real value, the value sent and the rule for each PII field that has a value

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import runMaskingTest from "@salesforce/apex/AIPiiRegistryController.runMaskingTest";
import { LABELS, NO_TEXT } from "./aiPiiRegistryTestSettings";
import { buildResultRows, formatErrorMessage } from "./aiPiiRegistryTestHelper";

// The Test masking tab.
export default class AiPiiRegistryTest extends LightningElement {

  // Values passed in by the parent component
  @api registryId; // The Id of the AIPIIRegistry__c
  @api objectApiName; // The object the registry holds, which the record picker searches

  // Values the template reads
  labels = LABELS;

  // State of the tab
  recordId = null;
  result = null;
  isRunning = false;
  errorMessage = NO_TEXT;

  get testOnLabel() {

    // [1] Name the object in the label of the picker
    const testOnLabel = LABELS.testOnBefore + this.objectApiName;

    return testOnLabel;
  }

  get isRunDisabled() {

    // [1] A test needs a record, and runs one at a time
    const isRunDisabled = !this.recordId || this.isRunning;

    return isRunDisabled;
  }

  get resultRows() {

    // [1] Hand the work to the helper
    const resultRows = buildResultRows(this.result);

    return resultRows;
  }

  get hasResult() {

    // [1] A test has run
    const hasResult = Boolean(this.result);

    return hasResult;
  }

  get hasRows() {

    // [1] The test found at least one value to mask
    const hasRows = this.resultRows.length > 0;

    return hasRows;
  }

  get hasNoRows() {

    // [1] The test ran but found nothing to mask
    const hasNoRows = this.hasResult && !this.hasRows;

    return hasNoRows;
  }

  get hasErrorMessage() {

    // [1] Show the message box only when there is a message
    const hasErrorMessage = Boolean(this.errorMessage);

    return hasErrorMessage;
  }

  // Event handlers
  handleRecordPick(event) {

    // [1] Keep the record, and drop a result that belonged to another one
    this.recordId = event.detail.recordId;
    this.result = null;
    this.errorMessage = NO_TEXT;
  }

  async handleRun() {

    // [1] Run the masking on the record
    this.isRunning = true;
    this.errorMessage = NO_TEXT;

    try {

      this.result = await runMaskingTest({ registryId: this.registryId, recordId: this.recordId });

    } catch (error) {

      // [2] Show the reason
      this.result = null;
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isRunning = false;
    }
  }
}
