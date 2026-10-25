/*
Component Name: aiPiiRegistryDetail

=================================================================
=================================================================

Description: The settings of the pane of one registered object: label text, tab names, class names and status values.

Step 1: Hold the text shown to the admin
Step 2: Name the tabs, the events and the sync statuses the controller and the helper use
Step 3: Name the classes of the status chip

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Text shown to the user.
export const LABELS = {
  active: "Active",
  syncNow: "Sync now",
  syncAgain: "Sync again",
  tabFields: "Fields",
  tabTest: "Test masking",
  loading: "Loading the fields",
  maxFieldsBefore: "Max ",
  maxFieldsAfter: " fields queried",
  statusSynced: "Synced",
  statusFailed: "Failed",
  statusQueued: "Queued",
  statusSyncing: "Syncing",
  statusNotSynced: "Not synced",
  lastSyncFailedBefore: "Last sync failed at ",
  lastSyncFailedAfter: ".",
  lastSyncFailedNoTime: "The last sync failed.",
  limitReachedBefore: " Field describe returned more than ",
  limitReachedMiddle: " fields; only the first ",
  limitReachedAfter: " were classified (MaxFieldsToQuery).",
  piiFoundBefore: " ",
  piiFoundMiddle: " PII fields were found in those ",
  piiFoundAfter: ".",
  failedSeeLog: " The platform log says why.",
  maxFieldsLabel: "Max fields to query",
  raiseHintBefore: "Raise it, or the rest of ",
  raiseHintAfter: "'s fields aren't checked.",
  largestHintBefore: "This is the most the registry can read (",
  largestHintAfter: "). The rest of the fields can't be checked here.",
  raiseBefore: "Raise to ",
  raiseAfter: " and sync",
  viewLog: "View log",
  unmaskedBefore: "Until a sync succeeds, unclassified ",
  unmaskedMiddle: " fields are treated as not PII. If an agent reads ",
  unmaskedAfter: ", those values could reach the provider unmasked.",
  waitingQueued: "This object is waiting for its fields to be classified. They appear here when the sync finishes.",
  waitingSyncing: "This object's fields are being classified. They appear here when the sync finishes.",
  neverSynced: "This object has not been synced yet. Use Sync now to classify its fields.",
  switchedOffBefore: "Switched off: ",
  switchedOffAfter: " fields go to the provider unmasked."
};

// The tabs of the pane.
export const TAB_FIELDS = "fields";
export const TAB_TEST = "test";

// The class of a tab, and of the chosen tab.
export const TAB_CLASS = "slds-tabs_default__item";
export const TAB_SELECTED_CLASS = "slds-tabs_default__item slds-is-active";

// The values of AIPIIRegistry__c.SyncStatus__c. Mirrors AIAssistApplicationConstants.PII_SYNC_STATUS_*.
export const STATUS_NOT_SYNCED = "Not Synced";
export const STATUS_QUEUED = "Queued";
export const STATUS_IN_PROGRESS = "In Progress";
export const STATUS_SYNCED = "Synced";
export const STATUS_FAILED = "Failed";

// The classes of the chip beside the object name.
export const CHIP_SYNCED_CLASS = "aiprd-chip aiprd-chip_synced";
export const CHIP_FAILED_CLASS = "aiprd-chip aiprd-chip_failed";
export const CHIP_QUEUED_CLASS = "aiprd-chip aiprd-chip_queued";
export const CHIP_NOT_SYNCED_CLASS = "aiprd-chip aiprd-chip_not-synced";

// The names of the events the pane sends to the tab.
export const EVENT_ACTIVE_CHANGE = "activechange";
export const EVENT_SYNC = "sync";
export const EVENT_FIELD_OVERRIDE = "fieldoverride";
export const EVENT_FIELD_RESET = "fieldreset";
export const EVENT_VIEW_LOG = "viewlog";

// The text of a value when it is empty, and the aria value of a chosen tab.
export const NO_TEXT = "";
export const ARIA_TRUE = "true";
export const ARIA_FALSE = "false";
