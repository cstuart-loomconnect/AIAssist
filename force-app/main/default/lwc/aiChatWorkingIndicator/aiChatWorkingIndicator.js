/*
Component Name: aiChatWorkingIndicator

=================================================================
=================================================================

Description: Shows the user that a reply is being worked on, as a step card or a lighter typing indicator.

Step 1: The parent (aiAssistChat) decides the mode and passes in the label, the clock and the steps
Step 2: The step card lists each step with an icon and styling for its state
Step 3: The typing indicator shows animated dots with a short label

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, MODE_STEPS, DEFAULT_MODE, STEP_STATE_DONE, STEP_STATE_ACTIVE, STEP_LABEL_CLASSES } from "./aiChatWorkingIndicatorSettings";

// Shown while a reply is being generated. aiAssistChat decides which look to show: the step card when AIAssistUISettings__c.ShouldShowExecutionTrace__c is on, otherwise (or while a message is held waiting for a free place) the typing indicator.
export default class AiChatWorkingIndicator extends LightningElement {

  // Values passed in by the parent component
  @api label; // Text beside the typing dots
  @api elapsedLabel; // The clock on the step card, for example "0:04"
  @api mode = DEFAULT_MODE; // 'steps' or 'typing'
  @api steps = []; // [{ label, state: 'done' | 'active' | 'pending' }]

  // Values the template reads
  labels = LABELS;

  // True when the step card should show, false when the typing indicator should.
  get isSteps() {

    // [1] Compare the mode the parent passed in with the steps mode
    const currentMode = this.mode;
    const isStepsMode = currentMode === MODE_STEPS;

    return isStepsMode;
  }

  // The steps turned into what the template needs.
  get stepViews() {

    // [1] The parent may not have set any steps yet, so start from an empty list
    const stepList = this.steps || [];
    const stepViews = [];

    // [2] Build one view for each step
    stepList.forEach((step, index) => {

      const stepState = step.state;
      const isDone = stepState === STEP_STATE_DONE;
      const isActive = stepState === STEP_STATE_ACTIVE;

      // The position is part of the key so two steps with the same label stay unique
      const key = `${index}-${step.label}`;
      const labelClass = STEP_LABEL_CLASSES[stepState];

      stepViews.push({ key, label: step.label, isDone, isActive, className: labelClass });
    });

    // [3] Give the views back to the template
    return stepViews;
  }
}
