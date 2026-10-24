/*
Component Name: aiToolsDsQuery

=================================================================
=================================================================

Description: Step 2 of the data source wizard for a SOQL data source: build the query visually or write it, checked as it changes.

Step 1: Load the objects, and the fields of the chosen object
Step 2: Write the query from the visual builder, or take the text typed in the editor
Step 3: Check the query with Apex, show the problems and the binds, and offer the fixes
Step 4: Tell the wizard the query, the binds and whether it has errors

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import getObjectOptions from "@salesforce/apex/AIToolsController.getObjectOptions";
import getFieldOptions from "@salesforce/apex/AIToolsController.getFieldOptions";
import validateSoql from "@salesforce/apex/AIToolsController.validateSoql";
import { QUERY_MODE_VISUAL, QUERY_MODE_WRITE, BINDING_BOUND, PROBLEM_ERROR, MAX_ROWS_LIMIT, DEFAULT_MAX_ROWS, VALIDATE_DELAY_MS, NO_TEXT, LABELS } from "./aiToolsDsQuerySettings";
import { buildEmptyBuilder, buildSoql, buildBindTypes, fillFilterTypes, parseSoql, parseLimit, buildHighlightedParts, buildValidMessage, applyFix, formatErrorMessage } from "./aiToolsDsQueryHelper";

// The Query step for a SOQL data source.
export default class AiToolsDsQuery extends LightningElement {

  // The draft of the wizard. Read only: changes are sent up in the draftchange event.
  @api draft;

  // Values the template reads
  labels = LABELS;

  // State of the step
  objectOptions = [];
  fieldOptions = [];
  validation = null;
  isChecking = false;
  isLoading = true;
  errorMessage = NO_TEXT;
  loadedObject = NO_TEXT;
  checkCounter = 0;
  checkTimer = null;

  // Lifecycle methods
  connectedCallback() {

    // [1] Load what the builder needs and pick the mode
    this.start();
  }

  disconnectedCallback() {

    // [1] Stop a check that has not started
    clearTimeout(this.checkTimer);
  }

  get isVisualMode() {

    // [1] The builder is shown in visual mode
    const isVisualMode = this.draft.queryMode === QUERY_MODE_VISUAL;

    return isVisualMode;
  }

  get isWriteMode() {

    // [1] The editor is shown in write mode
    const isWriteMode = this.draft.queryMode === QUERY_MODE_WRITE;

    return isWriteMode;
  }

  get hasBuilder() {

    // [1] The builder model is set a moment after the step opens, so the builder waits for it
    const hasBuilder = Boolean(this.draft.builder);

    return hasBuilder;
  }

  get isBound() {

    // [1] A bound data source is filled with the open record
    const isBound = this.draft.bindingType === BINDING_BOUND;

    return isBound;
  }

  get problems() {

    // [1] What the last check found, or nothing before the first check
    const problems = this.validation ? this.validation.problems : [];

    return problems;
  }

  get errorCount() {

    // [1] Count the errors, warnings do not count
    const errorCount = this.problems.filter((problem) => problem.severity === PROBLEM_ERROR).length;

    return errorCount;
  }

  get switchNote() {

    // [1] Say why the visual builder cannot be used, if it cannot
    if (this.errorCount > 0) return LABELS.blockedByErrors;
    if (this.isWriteMode && this.isNotSimple) return LABELS.blockedNotSimple;

    return LABELS.switchNote;
  }

  get isNotSimple() {

    // [1] A query that has text but cannot be read back is not simple
    const hasText = Boolean(this.draft.soqlTemplate && this.draft.soqlTemplate.trim());
    const isNotSimple = hasText && parseSoql(this.draft.soqlTemplate) === null;

    return isNotSimple;
  }

  get isVisualDisabled() {

    // [1] The builder cannot show a query with errors or one that is not simple
    const isVisualDisabled = this.isWriteMode && (this.errorCount > 0 || this.isNotSimple);

    return isVisualDisabled;
  }

  get visualButtonClass() {

    // [1] The button is on in visual mode
    const visualButtonClass = this.isVisualMode ? "aiadq-mode aiadq-mode_on" : "aiadq-mode";

    return visualButtonClass;
  }

  get writeButtonClass() {

    // [1] The button is on in write mode
    const writeButtonClass = this.isWriteMode ? "aiadq-mode aiadq-mode_on" : "aiadq-mode";

    return writeButtonClass;
  }

  get generatedParts() {

    // [1] Hand the work to the helper
    const generatedParts = buildHighlightedParts(this.draft.soqlTemplate || NO_TEXT);

    return generatedParts;
  }

  get hasGenerated() {

    // [1] There is a query to show once an object is chosen
    const hasGenerated = Boolean(this.draft.soqlTemplate);

    return hasGenerated;
  }

  get isValid() {

    // [1] Valid once checked with no errors
    const isValid = this.validation !== null && this.errorCount === 0;

    return isValid;
  }

  get hasErrors() {

    // [1] The check found at least one error
    const hasErrors = this.errorCount > 0;

    return hasErrors;
  }

  get validMessage() {

    // [1] Hand the work to the helper
    const validMessage = this.validation ? buildValidMessage(this.validation.binds) : NO_TEXT;

    return validMessage;
  }

  get hasError() {

    // [1] Show the box only when there is a message
    const hasError = Boolean(this.errorMessage);

    return hasError;
  }

  // Event handlers
  handleVisualClick() {

    // [1] Read the query back into the builder, when it can be read
    if (this.isVisualDisabled || this.isVisualMode) return;

    const soql = this.draft.soqlTemplate;
    const builder = soql && soql.trim() ? parseSoql(soql) : buildEmptyBuilder();
    const maxRows = parseLimit(soql) || this.draft.maxRows;

    this.sendChange({ queryMode: QUERY_MODE_VISUAL, builder, maxRows });
    this.loadFields(builder, maxRows);
  }

  handleWriteClick() {

    // [1] Show the editor, with the query the builder wrote
    this.sendChange({ queryMode: QUERY_MODE_WRITE });
  }

  handleMaxRowsChange(event) {

    // [1] The number typed in the write mode box
    this.applyMaxRows(event.target.value);
  }

  handleBuilderMaxRows(event) {

    // [1] The number typed in the builder
    this.applyMaxRows(event.detail.maxRows);
  }

  handleBuilderChange(event) {

    // [1] A new object means new fields, so load them
    const builder = event.detail.builder;
    const hasNewObject = builder.objectApiName !== this.loadedObject;

    if (hasNewObject) this.loadFields(builder, this.draft.maxRows);
    else this.pushBuilder(builder, this.draft.maxRows);
  }

  handleSqlChange(event) {

    // [1] Keep the text typed and check it
    const soqlTemplate = event.detail.soqlTemplate;
    this.sendChange({ soqlTemplate });
    this.validate(soqlTemplate, this.draft.maxRows);
  }

  handleFix(event) {

    // [1] Apply the fix to the text, then check it again
    const soqlTemplate = applyFix(this.draft.soqlTemplate, event.detail);
    this.sendChange({ soqlTemplate });
    this.validate(soqlTemplate, this.draft.maxRows);
  }

  // Private methods
  applyMaxRows(typedValue) {

    // [1] Keep the number between 1 and 200
    const typedNumber = Number(typedValue);
    const maxRows = Math.min(Math.max(Math.trunc(typedNumber) || DEFAULT_MAX_ROWS, 1), MAX_ROWS_LIMIT);
    this.sendChange({ maxRows });

    // [2] The builder writes the LIMIT, so write the query again. The editor keeps its own text
    if (this.isVisualMode) this.pushBuilder(this.draft.builder, maxRows);
    else this.validate(this.draft.soqlTemplate, maxRows);
  }

  async start() {

    try {

      // [1] Load the objects the builder offers, which can take a moment the first time
      this.objectOptions = await getObjectOptions();

    } catch (error) {

      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isLoading = false;
    }

    // [2] Visual mode starts from the saved query when the builder can read it, and from the editor when it cannot
    const soql = this.draft.soqlTemplate;

    if (this.isVisualMode && !this.draft.builder) {

      const builder = soql && soql.trim() ? parseSoql(soql) : buildEmptyBuilder();
      const maxRows = parseLimit(soql) || this.draft.maxRows;

      if (builder === null) {

        this.sendChange({ queryMode: QUERY_MODE_WRITE });
        this.validate(soql, this.draft.maxRows);

      } else {

        this.sendChange({ builder, maxRows });
        await this.loadFields(builder, maxRows);
      }

      return;
    }

    // [3] A builder that was already started loads its fields, and a query that was written is checked
    if (this.isVisualMode) await this.loadFields(this.draft.builder, this.draft.maxRows);
    else this.validate(soql, this.draft.maxRows);
  }

  async loadFields(builder, maxRows) {

    // [1] No object means no fields
    this.loadedObject = builder.objectApiName;

    if (!builder.objectApiName) {

      this.fieldOptions = [];
      this.pushBuilder(builder, maxRows);
      return;
    }

    this.isLoading = true;

    try {

      // [2] Read the fields the user can read, and give each filter the type of its field
      this.fieldOptions = await getFieldOptions({ objectApiName: builder.objectApiName });
      this.pushBuilder(fillFilterTypes(builder, this.fieldOptions), maxRows);

    } catch (error) {

      // [3] Show the reason
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isLoading = false;
    }
  }

  pushBuilder(builder, maxRows) {

    // [1] Write the query from the builder, and tell the wizard the query and the type of each agent bind
    const soqlTemplate = buildSoql(builder, maxRows, this.fieldOptions);
    this.sendChange({ builder, soqlTemplate, queryBindTypes: buildBindTypes(builder), targetObject: builder.objectApiName });

    // [2] Check it
    this.validate(soqlTemplate, maxRows);
  }

  validate(soqlTemplate, maxRows) {

    // [1] A query that is blank has nothing to check, and is not complete
    clearTimeout(this.checkTimer);
    this.checkCounter = this.checkCounter + 1;
    const checkNumber = this.checkCounter;

    if (!soqlTemplate || !soqlTemplate.trim()) {

      this.validation = null;
      this.isChecking = false;
      this.sendChange({ queryErrorCount: null, queryBinds: [], recordObjectApiName: null });
      return;
    }

    // [2] Wait until typing stops, then check
    this.isChecking = true;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.checkTimer = setTimeout(() => this.runCheck(soqlTemplate, maxRows, checkNumber), VALIDATE_DELAY_MS);
  }

  async runCheck(soqlTemplate, maxRows, checkNumber) {

    try {

      // [1] Ask Apex what is wrong with the query
      const validation = await validateSoql({ soql: soqlTemplate, isBound: this.isBound, maxRows });

      // [2] Ignore an answer for a query that has changed since
      if (checkNumber !== this.checkCounter) return;

      this.validation = validation;
      const queryErrorCount = validation.problems.filter((problem) => problem.severity === PROBLEM_ERROR).length;
      this.sendChange({ queryErrorCount, queryBinds: validation.binds, recordObjectApiName: validation.recordObjectApiName || null });

    } catch (error) {

      // [3] Show the reason
      this.errorMessage = formatErrorMessage(error);

    } finally {

      if (checkNumber === this.checkCounter) this.isChecking = false;
    }
  }

  sendChange(changes) {

    // [1] Send the change up to the wizard
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }
}
