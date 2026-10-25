/*
Component Name: aiPiiRegistryFields

=================================================================
=================================================================

Description: The extended methods of the Fields tab: filter the fields and build the rows and the filter buttons.

Step 1: Count the fields each filter would show
Step 2: Keep the fields the chosen filter and the search text allow
Step 3: Build one row for each field, with its type choices, its group and its masking

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS, FILTER_PII, FILTER_ALL, FILTER_OVERRIDDEN, FILTER_CLASS, FILTER_SELECTED_CLASS, SOURCE_AUTO_CLASS, SOURCE_OVERRIDDEN_CLASS, NO_TEXT } from "./aiPiiRegistryFieldsSettings";

// Builds the three filter buttons, each with how many fields it would show.
export function buildFilterButtons(fields, selectedFilter) {

  // [1] Count the fields each filter shows
  const piiCount = fields.filter((field) => field.isPii).length;
  const overriddenCount = fields.filter((field) => field.isOverridden).length;
  const allCount = fields.length;

  // [2] Build one button for each filter
  const filters = [{ key: FILTER_PII, label: LABELS.filterPiiOnly, count: piiCount }, { key: FILTER_ALL, label: LABELS.filterAll, count: allCount }, { key: FILTER_OVERRIDDEN, label: LABELS.filterOverridden, count: overriddenCount }];
  const buttons = filters.map((filter) => ({ key: filter.key, label: filter.label + LABELS.countBefore + filter.count + LABELS.countAfter, buttonClass: filter.key === selectedFilter ? FILTER_SELECTED_CLASS : FILTER_CLASS }));

  return buttons;
}

// Keeps the fields the chosen filter and the search text allow.
export function filterFields(fields, selectedFilter, searchText) {

  // [1] Apply the filter
  let filteredFields = fields;
  if (selectedFilter === FILTER_PII) filteredFields = fields.filter((field) => field.isPii);
  if (selectedFilter === FILTER_OVERRIDDEN) filteredFields = fields.filter((field) => field.isOverridden);

  // [2] Apply the search text to the label and the API name
  const lowerSearch = searchText ? searchText.trim().toLowerCase() : NO_TEXT;
  if (!lowerSearch) return filteredFields;

  const matchingFields = filteredFields.filter((field) => field.fieldLabel.toLowerCase().includes(lowerSearch) || field.fieldApiName.toLowerCase().includes(lowerSearch));

  return matchingFields;
}

// Builds one row for each field.
export function buildFieldRows(fields, typeOptions) {

  // [1] Build a row for each field
  const rows = fields.map((field) => {

    const typeOption = findTypeOption(typeOptions, field.piiFieldType);
    const complianceText = field.isPii ? field.complianceGroup || LABELS.none : NO_TEXT;
    const maskingText = field.isPii && typeOption ? typeOption.maskingText : NO_TEXT;
    const sourceLabel = field.isOverridden ? LABELS.overridden : LABELS.auto;
    const sourceClass = field.isOverridden ? SOURCE_OVERRIDDEN_CLASS : SOURCE_AUTO_CLASS;
    const typeChoices = buildTypeChoices(typeOptions, field.piiFieldType);
    const typeLabel = LABELS.piiTypeFor + field.fieldLabel;

    return { key: field.fieldId, fieldId: field.fieldId, fieldLabel: field.fieldLabel, fieldApiName: field.fieldApiName, dataType: formatDataType(field.dataType), isPii: field.isPii, piiFieldType: field.piiFieldType, typeChoices, typeLabel, complianceText, maskingText, isOverridden: field.isOverridden, sourceLabel, sourceClass };
  });

  return rows;
}

// Writes a data type without the size, so "Text(80)" reads "Text".
export function formatDataType(dataType) {

  // [1] Nothing to show without a type
  if (!dataType) return NO_TEXT;

  // [2] Take off the size in brackets
  const formattedType = dataType.replace(/\(.*\)/, NO_TEXT).trim();

  return formattedType;
}

// Finds the type option with this name, or nothing.
export function findTypeOption(typeOptions, piiFieldType) {

  // [1] Search the options
  const typeOption = typeOptions.find((option) => option.piiFieldType === piiFieldType);

  return typeOption;
}

// Builds the choices of the PII type box, keeping a type the field has even when the options no longer list it.
export function buildTypeChoices(typeOptions, piiFieldType) {

  // [1] One choice for each option, with the field's type marked
  const choices = typeOptions.map((option) => ({ value: option.piiFieldType, label: option.piiFieldType, isSelected: option.piiFieldType === piiFieldType }));

  // [2] Add the field's own type when the options do not list it
  const isListed = choices.some((choice) => choice.isSelected);
  if (piiFieldType && !isListed) choices.unshift({ value: piiFieldType, label: piiFieldType, isSelected: true });

  return choices;
}
