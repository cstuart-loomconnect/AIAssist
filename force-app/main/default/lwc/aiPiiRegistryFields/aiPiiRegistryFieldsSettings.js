/*
Component Name: aiPiiRegistryFields

=================================================================
=================================================================

Description: The settings of the Fields tab of a registered object: label text, filter names and class names.

Step 1: Hold the text shown to the admin
Step 2: Name the filters, the events and the classes the controller and the helper use

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Text shown to the user.
export const LABELS = {
  searchFields: "Search fields",
  filterPiiOnly: "PII only",
  filterAll: "All",
  filterOverridden: "Overridden",
  countBefore: " (",
  countAfter: ")",
  columnField: "Field",
  columnType: "Type",
  columnPii: "PII",
  columnPiiType: "PII type",
  columnComplianceGroup: "Compliance group",
  columnMasking: "Masking",
  columnSource: "Source",
  piiToggle: "PII",
  piiTypeFor: "PII type for ",
  auto: "Auto",
  overridden: "Overridden",
  reset: "Reset",
  resetTitle: "Hand this field back to the automatic rules",
  noFields: "No fields match.",
  none: "—",
  footnote: "Fields are classified automatically from the rules in Custom Metadata (AIPiiFieldType__mdt). Turn PII on or off, or change the type, to override a field; overrides survive the next sync."
};

// The filters above the table.
export const FILTER_PII = "pii";
export const FILTER_ALL = "all";
export const FILTER_OVERRIDDEN = "overridden";

// The class of a filter button, and of the chosen one.
export const FILTER_CLASS = "slds-button slds-button_neutral";
export const FILTER_SELECTED_CLASS = "slds-button slds-button_brand";

// The class of the Source pill for an automatic and an overridden field.
export const SOURCE_AUTO_CLASS = "aiprf-pill aiprf-pill_auto";
export const SOURCE_OVERRIDDEN_CLASS = "aiprf-pill aiprf-pill_overridden";

// The names of the events the tab sends to the pane.
export const EVENT_FIELD_OVERRIDE = "fieldoverride";
export const EVENT_FIELD_RESET = "fieldreset";

// The text of a value when it is empty.
export const NO_TEXT = "";
