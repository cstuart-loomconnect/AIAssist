/*
Component Name: aiPromptTemplatesSection

=================================================================
=================================================================

Description: One section card of a prompt template: a title, a hint and a text box that shows a problem.

Step 1: Show the title, the hint and the text box
Step 2: Tell the parent when the text changes or the box gets the cursor
Step 3: Put a merge field into the text at the cursor when the parent asks

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { BOX_CLASS, BOX_PROBLEM_CLASS, TEXT_CLASS, TEXT_PROBLEM_CLASS, TEXT_ROWS } from "./aiPromptTemplatesSectionSettings";
import { buildInsertedText } from "./aiPromptTemplatesSectionHelper";

// One section of the template.
export default class AiPromptTemplatesSection extends LightningElement {

  // Values passed in by the parent component
  @api sectionKey = ""; // The TemplateDetail field the text belongs to, such as systemContext
  @api title = "";
  @api hint = "";
  @api help = ""; // A sentence or two saying what to write in the section
  @api placeholder = ""; // An example shown in the empty text box
  @api value = ""; // The text of the section
  @api message = ""; // The problem to show under the text, blank when there is none

  // Values the template reads
  textRows = TEXT_ROWS;

  get hasProblem() {

    // [1] A message means a problem
    const hasProblem = Boolean(this.message);

    return hasProblem;
  }

  get boxClass() {

    // [1] A problem turns the border red
    const boxClass = this.hasProblem ? BOX_PROBLEM_CLASS : BOX_CLASS;

    return boxClass;
  }

  get textClass() {

    // [1] A problem turns the text area border red
    const textClass = this.hasProblem ? TEXT_PROBLEM_CLASS : TEXT_CLASS;

    return textClass;
  }

  // Lifecycle methods
  renderedCallback() {

    // [1] A native text area ignores the value attribute, so the text is put in by hand whenever it differs from what the parent passed
    const textArea = this.template.querySelector("textarea");
    if (!textArea) return;

    const parentText = this.value || "";
    if (textArea.value !== parentText) textArea.value = parentText;
  }

  // Methods the parent calls
  @api
  insertText(token) {

    // [1] Find the text area and where the cursor is
    const textArea = this.template.querySelector("textarea");
    if (!textArea) return;

    // [2] Put the token in at the cursor
    const result = buildInsertedText(textArea.value, token, textArea.selectionStart, textArea.selectionEnd);
    textArea.value = result.newText;

    // [3] Keep the cursor after the token and give the cursor back to the text box
    textArea.focus();
    textArea.setSelectionRange(result.newCursor, result.newCursor);

    // [4] Tell the parent about the new text
    this.fireChange(result.newText);
  }

  // Event handlers
  handleInput(event) {

    // [1] Tell the parent about the new text
    this.fireChange(event.target.value);
  }

  handleFocus() {

    // [1] Tell the parent this section has the cursor
    this.dispatchEvent(new CustomEvent("sectionfocus", { detail: { key: this.sectionKey } }));
  }

  // Private methods
  fireChange(value) {

    // [1] Tell the parent which section changed and the new text
    this.dispatchEvent(new CustomEvent("sectionchange", { detail: { key: this.sectionKey, value } }));
  }
}
