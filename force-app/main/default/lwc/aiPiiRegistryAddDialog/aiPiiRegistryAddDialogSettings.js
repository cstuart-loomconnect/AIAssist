/*
Component Name: aiPiiRegistryAddDialog

=================================================================
=================================================================

Description: The settings of the Add object dialog: label text, limits, timings and event names.

Step 1: Hold the text shown to the admin
Step 2: Hold the limits and timings of the object search
Step 3: Name the events the dialog sends to the tab

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Text shown to the user.
export const LABELS = {
  title: "Add an object to the registry",
  objectLabel: "Object",
  objectPlaceholder: "Type part of an object's name",
  searchHint: "Type at least two letters to search.",
  searching: "Searching",
  noMatches: "No object matches that, or it is already in the registry.",
  fieldsWord: " fields",
  detailSeparator: " · ",
  usedByOne: "Used by 1 data source",
  usedByManyBefore: "Used by ",
  usedByManyAfter: " data sources",
  maxFieldsLabel: "Max fields to query",
  fieldsOnObjectBefore: "",
  fieldsOnObjectAfter: " fields on this object.",
  limitTooLowBefore: "Only the first ",
  limitTooLowMiddle: " of this object's ",
  limitTooLowAfter: " fields would be checked, so the sync would be marked Failed. Raise the limit to cover them all.",
  backgroundNote: "The fields are classified in the background (AIPiiRegistrySyncWorker). You can review and override them when it finishes.",
  cancel: "Cancel",
  addAndSync: "Add and sync",
  saving: "Adding",
  fallbackError: "Something went wrong. Try again."
};

// The object search: how many letters it needs, how long it waits after typing, and the field limit a new object starts with. Mirrors AIAssistApplicationConstants.PII_OBJECT_SEARCH_MIN_LENGTH and DEFAULT_PII_FIELDS_TO_QUERY_NEW_OBJECT.
export const SEARCH_MIN_LENGTH = 2;
export const SEARCH_DELAY_MS = 300;
export const DEFAULT_MAX_FIELDS = 100;

// The largest and smallest field limit an object accepts. Mirrors the AIPIIRegistry__c MaxFieldsToQueryRange validation rule.
export const MAX_FIELDS_LIMIT = 500;
export const MIN_FIELDS_LIMIT = 1;

// The class of one object in the list, and of the chosen one.
export const OPTION_CLASS = "aipra-option";
export const OPTION_SELECTED_CLASS = "aipra-option aipra-option_selected";

// The class of the hint under the field limit, and of the one that warns.
export const HINT_CLASS = "aipra-hint slds-text-body_small";
export const HINT_WARNING_CLASS = "aipra-hint aipra-hint_warning slds-text-body_small";

// The names of the events the dialog sends to the tab.
export const EVENT_CANCEL = "cancel";
export const EVENT_ADD = "add";

// The text of a value when it is empty.
export const NO_TEXT = "";
