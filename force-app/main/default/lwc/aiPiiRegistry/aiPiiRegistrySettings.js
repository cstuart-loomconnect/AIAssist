/*
Component Name: aiPiiRegistry

=================================================================
=================================================================

Description: The settings of the AI PII Registry tab: label text, class names, status values and timings.

Step 1: Hold the text shown to the admin
Step 2: Name the sync statuses, classes and toast variants the controller and the helper use
Step 3: Hold the timings of the sync follow-up

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Text shown to the user.
export const LABELS = {
  title: "AI PII Registry",
  subtitle: "Which fields are masked before anything reaches the AI provider",
  loading: "Loading the registry",
  addObject: "+ Add object",
  limitOf: " of ",
  limitObjects: " objects (MaxPIIRegistryObjects)",
  noObjects: "No objects yet. Add one to start masking its fields.",
  chooseOne: "Pick an object on the left, or add a new one.",
  fieldsWord: " fields",
  piiWord: " PII",
  detailSeparator: " · ",
  notSyncedYet: "Not synced yet",
  queued: "Queued",
  syncing: "Syncing",
  synced: "Synced",
  failed: "Failed",
  added: "Added to the registry. Its fields are classified in the background.",
  syncQueued: "Sync queued. The fields are classified in the background.",
  switchedOn: "Object switched on",
  switchedOff: "Object switched off. Its fields go to the provider unmasked.",
  fieldSaved: "Field saved",
  fieldReset: "Field handed back to the automatic rules",
  fallbackError: "Something went wrong. Try again."
};

// The values of AIPIIRegistry__c.SyncStatus__c. Mirrors AIAssistApplicationConstants.PII_SYNC_STATUS_*.
export const STATUS_NOT_SYNCED = "Not Synced";
export const STATUS_QUEUED = "Queued";
export const STATUS_IN_PROGRESS = "In Progress";
export const STATUS_SYNCED = "Synced";
export const STATUS_FAILED = "Failed";

// The classes of one object in the list and of the chip beside it; the chosen object also gets the second class.
export const ITEM_CLASS = "aipr-item";
export const ITEM_SELECTED_CLASS = "aipr-item aipr-item_selected";
export const CHIP_SYNCED_CLASS = "aipr-chip aipr-chip_synced";
export const CHIP_FAILED_CLASS = "aipr-chip aipr-chip_failed";
export const CHIP_QUEUED_CLASS = "aipr-chip aipr-chip_queued";
export const CHIP_NOT_SYNCED_CLASS = "aipr-chip aipr-chip_not-synced";

// The toast variants.
export const TOAST_VARIANT_SUCCESS = "success";
export const TOAST_VARIANT_WARNING = "warning";
export const TOAST_VARIANT_ERROR = "error";

// How the tab follows a sync that is queued or running: look again every few seconds, and stop after a while.
export const POLL_INTERVAL_MS = 5000;
export const POLL_MAX_ATTEMPTS = 60;

// The text of a message when it is empty.
export const NO_TEXT = "";

// The AI Platform Log list the View log button opens.
export const LOG_LIST_ACTION = "list";
export const LOG_OBJECT_PAGE_TYPE = "standard__objectPage";
