/*
Component Name: aiToolsDsQueryBuilder

=================================================================
=================================================================

Description: The visual query builder of the Query step: choose the object, tick the fields, add filters and pick the order.

Step 1: Show the object, the max rows, the fields, the filters and the order
Step 2: Change a copy of the builder when the admin changes something
Step 3: Tell the Query step the new builder, or the new max rows

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { NO_TEXT, LABELS } from "./aiToolsDsQueryBuilderSettings";
import { findObjectLabel, findObjectMatches, buildFieldViews, buildInputName, buildNewFilter, buildFilterViews, buildOrderOptions } from "./aiToolsDsQueryBuilderHelper";

// The visual query builder.
export default class AiToolsDsQueryBuilder extends LightningElement {

  // The builder model: { objectApiName, selectedFields: [apiName], filters: [{ key, fieldApiName, fieldType, operator, source, fixedValue, inputName }], orderValue: "Field|ASC" }
  @api builder;

  // The objects the admin can pick: [{ apiName, label }]
  @api objectOptions = [];

  // The fields the admin can read on the chosen object: [{ apiName, label, dataType, referenceTo }]
  @api fieldOptions = [];

  // The most rows the data source returns, written as the LIMIT.
  @api maxRows = 20;

  // True when the data source is bound to the open record, so a filter may take its value from it.
  @api isBound = false;

  // Values the template reads
  labels = LABELS;

  // State of the builder
  objectSearchText = NO_TEXT;
  isObjectTyping = false;
  fieldSearchText = NO_TEXT;

  get objectDisplay() {

    // [1] Show what is being typed, or the chosen object
    const chosenLabel = findObjectLabel(this.objectOptions, this.builder.objectApiName);
    const objectDisplay = this.isObjectTyping ? this.objectSearchText : chosenLabel;

    return objectDisplay;
  }

  get objectMatches() {

    // [1] Hand the work to the helper
    const objectMatches = this.isObjectTyping ? findObjectMatches(this.objectOptions, this.objectSearchText) : [];

    return objectMatches;
  }

  get showObjectList() {

    // [1] The list is open while the admin types
    const showObjectList = this.isObjectTyping && this.objectSearchText.trim().length > 0;

    return showObjectList;
  }

  get hasObjectMatches() {

    // [1] There is at least one match
    const hasObjectMatches = this.objectMatches.length > 0;

    return hasObjectMatches;
  }

  get fieldViews() {

    // [1] Hand the work to the helper
    const fieldViews = buildFieldViews(this.fieldOptions, this.builder.selectedFields, this.fieldSearchText);

    return fieldViews;
  }

  get hasFieldViews() {

    // [1] There is at least one field to show
    const hasFieldViews = this.fieldViews.length > 0;

    return hasFieldViews;
  }

  get hasObject() {

    // [1] An object is chosen
    const hasObject = Boolean(this.builder.objectApiName);

    return hasObject;
  }

  get isObjectMissing() {

    // [1] The buttons wait until an object is chosen
    const isObjectMissing = !this.hasObject;

    return isObjectMissing;
  }

  get fieldsCountText() {

    // [1] Write how many fields are ticked
    const fieldsCountText = this.builder.selectedFields.length + LABELS.fieldsCountMiddle + this.fieldOptions.length + LABELS.fieldsNote;

    return fieldsCountText;
  }

  get filterViews() {

    // [1] Hand the work to the helper
    const filterViews = buildFilterViews(this.builder.filters, this.fieldOptions, this.isBound);

    return filterViews;
  }

  get hasFilters() {

    // [1] There is at least one filter
    const hasFilters = this.builder.filters.length > 0;

    return hasFilters;
  }

  get orderOptions() {

    // [1] Hand the work to the helper
    const orderOptions = buildOrderOptions(this.fieldOptions, this.builder.orderValue);

    return orderOptions;
  }

  // Event handlers
  handleObjectInput(event) {

    // [1] Keep what is being typed
    this.objectSearchText = event.detail.value;
    this.isObjectTyping = true;
  }

  handleObjectBlur() {

    // [1] Stop typing, so the chosen object is shown again
    this.isObjectTyping = false;
  }

  handleObjectPick(event) {

    // [1] Choose the object, and start the fields, filters and order again, because they belong to the old object
    const objectApiName = event.currentTarget.dataset.apiName;
    this.isObjectTyping = false;
    this.objectSearchText = NO_TEXT;
    this.fieldSearchText = NO_TEXT;
    this.sendBuilder({ objectApiName, selectedFields: [], filters: [], orderValue: NO_TEXT });
  }

  handleMaxRowsInput(event) {

    // [1] Tell the Query step the new number
    this.dispatchEvent(new CustomEvent("maxrowschange", { detail: { maxRows: event.target.value } }));
  }

  handleFieldSearch(event) {

    // [1] Keep what was typed
    this.fieldSearchText = event.target.value;
  }

  handleFieldToggle(event) {

    // [1] Add or take out the field
    const fieldApiName = event.target.dataset.apiName;
    const others = this.builder.selectedFields.filter((name) => name !== fieldApiName);
    const selectedFields = event.target.checked ? [...others, fieldApiName] : others;
    this.sendBuilder({ ...this.builder, selectedFields });
  }

  handleAddFilter() {

    // [1] Add a filter on the first field
    const filters = [...this.builder.filters, buildNewFilter(this.fieldOptions, this.isBound)];
    this.sendBuilder({ ...this.builder, filters });
  }

  handleFilterField(event) {

    // [1] Change the field, take its type, and name the agent input after it
    const field = this.fieldOptions.find((option) => option.apiName === event.target.value);
    const fieldType = field ? field.dataType : NO_TEXT;
    this.changeFilter(event.target.dataset.key, { fieldApiName: event.target.value, fieldType, inputName: buildInputName(event.target.value) });
  }

  handleFilterOperator(event) {

    // [1] Change the comparison
    this.changeFilter(event.target.dataset.key, { operator: event.target.value });
  }

  handleFilterSource(event) {

    // [1] Change where the value comes from
    this.changeFilter(event.target.dataset.key, { source: event.target.value });
  }

  handleFilterFixed(event) {

    // [1] Keep the fixed value, from a text box or a true or false list
    this.changeFilter(event.target.dataset.key, { fixedValue: event.target.value });
  }

  handleFilterInputName(event) {

    // [1] Keep the name of the agent input, which must be a plain name because it is a bind
    const typedName = event.target.value.replace(/[^A-Za-z0-9_]/g, NO_TEXT);
    this.changeFilter(event.target.dataset.key, { inputName: typedName || buildInputName(NO_TEXT) });
  }

  handleRemoveFilter(event) {

    // [1] Take the filter out
    const key = event.currentTarget.dataset.key;
    const filters = this.builder.filters.filter((filter) => filter.key !== key);
    this.sendBuilder({ ...this.builder, filters });
  }

  handleOrderChange(event) {

    // [1] Keep the field and direction
    this.sendBuilder({ ...this.builder, orderValue: event.target.value });
  }

  // Private methods
  changeFilter(key, changes) {

    // [1] Change one filter and keep the others as they are
    const filters = this.builder.filters.map((filter) => (filter.key === key ? { ...filter, ...changes } : filter));
    this.sendBuilder({ ...this.builder, filters });
  }

  sendBuilder(builder) {

    // [1] Tell the Query step the new builder
    this.dispatchEvent(new CustomEvent("builderchange", { detail: { builder } }));
  }
}
