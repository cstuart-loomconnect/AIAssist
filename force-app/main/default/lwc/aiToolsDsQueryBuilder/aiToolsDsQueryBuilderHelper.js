/*
Component Name: aiToolsDsQueryBuilder

=================================================================
=================================================================

Description: The extended methods of the visual query builder: match objects, build the field list, the filter rows and the order options.

Step 1: Find the objects that match what was typed
Step 2: Build the field list with the chosen fields ticked
Step 3: Build one row for each filter with the options it needs
Step 4: Build the order by options and a new filter

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { SOURCE_RECORD, SOURCE_FIXED, SOURCE_AGENT, FIELD_TYPE_BOOLEAN, NO_TEXT, ORDER_ASC, ORDER_DESC, ORDER_SEPARATOR, MAX_OBJECT_MATCHES, OPERATOR_OPTIONS, BOOLEAN_OPTIONS, LABELS } from "./aiToolsDsQueryBuilderSettings";

// Finds the label of the chosen object.
export function findObjectLabel(objectOptions, objectApiName) {

  // [1] Show the API name until the objects have loaded
  const objectOption = objectOptions.find((option) => option.apiName === objectApiName);

  return objectOption ? objectOption.label : objectApiName;
}

// Finds the objects whose label or API name holds the text, the first few only.
export function findObjectMatches(objectOptions, searchText) {

  // [1] Nothing to match until something is typed
  const search = (searchText || NO_TEXT).trim().toLowerCase();
  if (!search) return [];

  // [2] Keep the objects that hold the text
  const matches = objectOptions.filter((option) => option.label.toLowerCase().includes(search) || option.apiName.toLowerCase().includes(search));
  const shownMatches = matches.slice(0, MAX_OBJECT_MATCHES).map((option) => ({ apiName: option.apiName, label: option.label }));

  return shownMatches;
}

// Builds the field list: each field with whether it is ticked, keeping the ones that hold the search text.
export function buildFieldViews(fieldOptions, selectedFields, searchText) {

  // [1] Match the search against the label and the API name
  const search = (searchText || NO_TEXT).trim().toLowerCase();
  const matchingFields = fieldOptions.filter((field) => !search || field.label.toLowerCase().includes(search) || field.apiName.toLowerCase().includes(search));

  // [2] Tick the chosen fields
  const fieldViews = matchingFields.map((field) => ({ apiName: field.apiName, label: field.label, dataType: field.dataType, isChecked: selectedFields.includes(field.apiName) }));

  return fieldViews;
}

// Writes the name of the agent input a filter makes, such as closeBefore from CloseDate.
export function buildInputName(fieldApiName) {

  // [1] Take the field name without a custom field ending, with a lower case first letter
  const baseName = (fieldApiName || NO_TEXT).replace(/__c$/i, NO_TEXT).replace(/_/g, NO_TEXT);
  const inputName = baseName.charAt(0).toLowerCase() + baseName.slice(1);

  return inputName || "input";
}

// Builds a filter the admin has just added: the first field, equals, and a value from the open record when there is one.
export function buildNewFilter(fieldOptions, isBound) {

  // [1] Start with the first field, with a key that stays the same while the admin works
  const field = fieldOptions[0];
  const key = Math.random().toString(36).slice(2);
  const fieldApiName = field ? field.apiName : NO_TEXT;
  const source = isBound ? SOURCE_RECORD : SOURCE_AGENT;

  return { key, fieldApiName, fieldType: field ? field.dataType : NO_TEXT, operator: "=", source, fixedValue: NO_TEXT, inputName: buildInputName(fieldApiName) };
}

// Copies a list of choices with the chosen one marked, because a plain drop-down needs to know which one is selected.
export function markSelected(choices, selectedValue) {

  // [1] Mark the choice whose value is the chosen one
  const markedChoices = choices.map((choice) => ({ label: choice.label, value: choice.value, isSelected: choice.value === selectedValue }));

  return markedChoices;
}

// Builds one row for each filter, with the options its controls need.
export function buildFilterViews(filters, fieldOptions, isBound) {

  // [1] The options of the field list, shared by every row
  const fieldChoices = fieldOptions.map((field) => ({ label: field.label, value: field.apiName }));
  const sourceChoices = [];

  if (isBound) sourceChoices.push({ label: LABELS.sourceRecord, value: SOURCE_RECORD });

  sourceChoices.push({ label: LABELS.sourceFixed, value: SOURCE_FIXED });
  sourceChoices.push({ label: LABELS.sourceAgent, value: SOURCE_AGENT });

  // [2] Build each row
  const filterViews = filters.map((filter) => {

    const isFixed = filter.source === SOURCE_FIXED;
    const isBoolean = isFixed && filter.fieldType === FIELD_TYPE_BOOLEAN;

    return { key: filter.key, fixedValue: filter.fixedValue, inputName: filter.inputName, isFixedText: isFixed && !isBoolean, isFixedBoolean: isBoolean, isAgent: filter.source === SOURCE_AGENT, isRecord: filter.source === SOURCE_RECORD, fieldChoices: markSelected(fieldChoices, filter.fieldApiName), operatorChoices: markSelected(OPERATOR_OPTIONS, filter.operator), sourceChoices: markSelected(sourceChoices, filter.source), booleanChoices: markSelected(BOOLEAN_OPTIONS, filter.fixedValue) };
  });

  return filterViews;
}

// Builds the order by options: no order, then each field both ways.
export function buildOrderOptions(fieldOptions, orderValue) {

  // [1] Start with no order
  const orderOptions = [{ label: LABELS.orderNone, value: NO_TEXT }];

  // [2] Add each field ascending and descending
  fieldOptions.forEach((field) => {

    orderOptions.push({ label: field.label + LABELS.ascending, value: field.apiName + ORDER_SEPARATOR + ORDER_ASC });
    orderOptions.push({ label: field.label + LABELS.descending, value: field.apiName + ORDER_SEPARATOR + ORDER_DESC });
  });

  return markSelected(orderOptions, orderValue);
}
