/*
Component Name: aiToolsDsQueryEditor

=================================================================
=================================================================

Description: The SOQL editor of the Query step: a text box for the query and a list of the problems found, each with a fix when there is one.

Step 1: Show the query as text the admin can change
Step 2: Show each problem with its line and a fix button
Step 3: Tell the Query step when the text changes or a fix is chosen

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS } from "./aiToolsDsQueryEditorSettings";
import { buildProblemViews } from "./aiToolsDsQueryEditorHelper";

// The SOQL editor.
export default class AiToolsDsQueryEditor extends LightningElement {

  // The query text.
  @api soqlTemplate = "";

  // The problems the last check found: [{ severity, line, message, fixLabel, fixStart, fixEnd, fixText }]
  @api problems = [];

  // Values the template reads
  labels = LABELS;

  renderedCallback() {

    // [1] A textarea does not take its text from a value attribute, so put the query in it, unless it is already what the box holds
    const textBox = this.refs.text;

    if (textBox && textBox.value !== this.soqlTemplate) textBox.value = this.soqlTemplate || "";
  }

  get problemViews() {

    // [1] Hand the work to the helper
    const problemViews = buildProblemViews(this.problems);

    return problemViews;
  }

  get hasProblems() {

    // [1] There is something to list
    const hasProblems = this.problems.length > 0;

    return hasProblems;
  }

  get problemsTitle() {

    // [1] The heading with the count
    const problemsTitle = LABELS.problems + " (" + this.problems.length + ")";

    return problemsTitle;
  }

  // Event handlers
  handleInput(event) {

    // [1] Tell the Query step what was typed
    this.dispatchEvent(new CustomEvent("sqlchange", { detail: { soqlTemplate: event.target.value } }));
  }

  handleFixClick(event) {

    // [1] Tell the Query step which part of the text to replace, and with what
    const dataset = event.currentTarget.dataset;
    const fix = { start: Number(dataset.start), end: Number(dataset.end), text: dataset.text };
    this.dispatchEvent(new CustomEvent("fix", { detail: fix }));
  }
}
