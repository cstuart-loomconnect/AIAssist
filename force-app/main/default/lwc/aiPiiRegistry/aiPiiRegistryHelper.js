/*
Component Name: aiPiiRegistry

=================================================================
=================================================================

Description: The extended methods of the AI PII Registry tab: build the list, keep it in order, follow a sync and write an error message.

Step 1: Build one list item for each object, with its chip and counts
Step 2: Replace one object or one field with its saved version
Step 3: Say whether any object is still syncing
Step 4: Turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS, STATUS_NOT_SYNCED, STATUS_QUEUED, STATUS_IN_PROGRESS, STATUS_SYNCED, STATUS_FAILED, ITEM_CLASS, ITEM_SELECTED_CLASS, CHIP_SYNCED_CLASS, CHIP_FAILED_CLASS, CHIP_QUEUED_CLASS, CHIP_NOT_SYNCED_CLASS } from "./aiPiiRegistrySettings";

// Builds the list items for the registered objects.
export function buildRegistryItems(registries, selectedId) {

  // [1] Build an item for each object
  const items = [];

  registries.forEach((registry) => {

    const isSelected = registry.registryId === selectedId;
    const itemClass = isSelected ? ITEM_SELECTED_CLASS : ITEM_CLASS;
    const chip = getChip(registry.syncStatus);
    const detail = buildDetailText(registry);
    items.push({ key: registry.registryId, name: registry.objectApiName, detail, itemClass, chipLabel: chip.label, chipClass: chip.chipClass });
  });

  return items;
}

// Writes how many objects the registry holds out of how many it may hold.
export function formatLimitText(registryCount, registryLimit) {

  // [1] Join the parts
  const limitText = registryCount + LABELS.limitOf + registryLimit + LABELS.limitObjects;

  return limitText;
}

// Puts a saved object into the list in place of the old one, or adds it when it is new, and keeps the list in name order.
export function replaceRegistry(registries, savedRegistry) {

  // [1] Remove the old version, if there is one
  const others = registries.filter((registry) => registry.registryId !== savedRegistry.registryId);

  // [2] Add the saved one and put the list in order
  const combined = [...others, savedRegistry];
  combined.sort((first, second) => first.objectApiName.localeCompare(second.objectApiName));

  return combined;
}

// Puts a saved field into the list of fields in place of the old one.
export function replaceField(fields, savedField) {

  // [1] Swap the field that has the same id
  const replacedFields = fields.map((field) => (field.fieldId === savedField.fieldId ? savedField : field));

  return replacedFields;
}

// Counts the fields that are PII.
export function countPiiFields(fields) {

  // [1] Keep the PII ones
  const piiFields = fields.filter((field) => field.isPii);

  return piiFields.length;
}

// True when any object is queued or being synced.
export function hasRunningRegistry(registries) {

  // [1] Look for a status that has not finished
  const hasRunning = registries.some((registry) => isRunningStatus(registry.syncStatus));

  return hasRunning;
}

// True for a status that has not finished.
export function isRunningStatus(syncStatus) {

  // [1] Queued and in progress are both waiting for the job
  const isRunning = syncStatus === STATUS_QUEUED || syncStatus === STATUS_IN_PROGRESS;

  return isRunning;
}

// Turns whatever an Apex call threw into text the admin can read.
export function formatErrorMessage(error) {

  // [1] An Apex refusal carries its message in the body
  const errorBody = error && error.body;
  const bodyMessage = errorBody && errorBody.message;
  if (bodyMessage) return bodyMessage;

  // [2] A plain error has a message
  const plainMessage = error && error.message;
  if (plainMessage) return plainMessage;

  return LABELS.fallbackError;
}

// Chooses the chip text and class for a sync status.
export function getChip(syncStatus) {

  // [1] Each status has its own wording and colour
  if (syncStatus === STATUS_SYNCED) return { label: LABELS.synced, chipClass: CHIP_SYNCED_CLASS };
  if (syncStatus === STATUS_FAILED) return { label: LABELS.failed, chipClass: CHIP_FAILED_CLASS };
  if (syncStatus === STATUS_QUEUED) return { label: LABELS.queued, chipClass: CHIP_QUEUED_CLASS };
  if (syncStatus === STATUS_IN_PROGRESS) return { label: LABELS.syncing, chipClass: CHIP_QUEUED_CLASS };

  return { label: LABELS.notSyncedYet, chipClass: CHIP_NOT_SYNCED_CLASS };
}

// Writes the line under an object's name, such as "38 fields · 11 PII", or the status when it has no fields yet.
export function buildDetailText(registry) {

  // [1] An object waiting for its first sync has no counts to show
  const hasNoFields = registry.fieldCount === 0;
  if (hasNoFields && registry.syncStatus === STATUS_NOT_SYNCED) return LABELS.notSyncedYet;
  if (hasNoFields && isRunningStatus(registry.syncStatus)) return registry.syncStatus === STATUS_QUEUED ? LABELS.queued : LABELS.syncing;

  // [2] Join the counts
  const detailText = registry.fieldCount + LABELS.fieldsWord + LABELS.detailSeparator + registry.piiCount + LABELS.piiWord;

  return detailText;
}
