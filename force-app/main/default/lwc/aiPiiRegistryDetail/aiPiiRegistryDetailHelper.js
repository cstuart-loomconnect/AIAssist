/*
Component Name: aiPiiRegistryDetail

=================================================================
=================================================================

Description: The extended methods of the pane of one registered object: the status chip, the time of the last sync and the wording of a failed sync.

Step 1: Choose the chip text and class for a sync status
Step 2: Write the time of the last sync
Step 3: Write the message of a failed sync and the button that raises the limit

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS, STATUS_QUEUED, STATUS_IN_PROGRESS, STATUS_SYNCED, STATUS_FAILED, CHIP_SYNCED_CLASS, CHIP_FAILED_CLASS, CHIP_QUEUED_CLASS, CHIP_NOT_SYNCED_CLASS, NO_TEXT } from "./aiPiiRegistryDetailSettings";

// Writes the time of a sync as hours and minutes, such as "06:12". Blank when the object has never been synced.
export function formatSyncTime(lastSynced) {

  // [1] Nothing to show without a time
  if (!lastSynced) return NO_TEXT;

  // [2] Format it in the admin's own locale
  const syncDate = new Date(lastSynced);
  const syncTime = syncDate.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

  return syncTime;
}

// Builds the text and class of the chip beside the object name, such as "Synced 06:12".
export function buildChip(registry) {

  // [1] Each status has its own wording and colour
  const syncTime = formatSyncTime(registry.lastSynced);
  const timeSuffix = syncTime ? " " + syncTime : NO_TEXT;
  const status = registry.syncStatus;

  if (status === STATUS_SYNCED) return { label: LABELS.statusSynced + timeSuffix, chipClass: CHIP_SYNCED_CLASS };
  if (status === STATUS_FAILED) return { label: LABELS.statusFailed + timeSuffix, chipClass: CHIP_FAILED_CLASS };
  if (status === STATUS_QUEUED) return { label: LABELS.statusQueued, chipClass: CHIP_QUEUED_CLASS };
  if (status === STATUS_IN_PROGRESS) return { label: LABELS.statusSyncing, chipClass: CHIP_QUEUED_CLASS };

  return { label: LABELS.statusNotSynced, chipClass: CHIP_NOT_SYNCED_CLASS };
}

// Writes the message of a failed sync: the time, and when the object has more fields than the limit, how many were classified and how many of them are PII.
export function buildFailedMessage(registry, isFieldLimitReached) {

  // [1] The lead says when the sync failed
  const syncTime = formatSyncTime(registry.lastSynced);
  const lead = syncTime ? LABELS.lastSyncFailedBefore + syncTime + LABELS.lastSyncFailedAfter : LABELS.lastSyncFailedNoTime;

  // [2] Any other failure points to the log
  if (!isFieldLimitReached) return { lead, rest: LABELS.failedSeeLog };

  // [3] A limit that was too small says how many fields were read and how many of them are PII
  const maxFields = registry.maxFieldsToQuery;
  const limitText = LABELS.limitReachedBefore + maxFields + LABELS.limitReachedMiddle + maxFields + LABELS.limitReachedAfter;
  const piiText = LABELS.piiFoundBefore + registry.piiCount + LABELS.piiFoundMiddle + maxFields + LABELS.piiFoundAfter;

  return { lead, rest: limitText + piiText };
}

// Writes the button that raises the limit and syncs, or Sync again when there is no higher limit to try.
export function buildRaiseLabel(maxFieldsToQuery, currentMaxFields) {

  // [1] A limit that is not higher than the current one only syncs again
  const isHigher = maxFieldsToQuery && maxFieldsToQuery > currentMaxFields;
  if (!isHigher) return LABELS.syncAgain;

  // [2] Name the new limit
  const raiseLabel = LABELS.raiseBefore + maxFieldsToQuery + LABELS.raiseAfter;

  return raiseLabel;
}
