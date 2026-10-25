/*
Component Name: aiAssistSettingsPanel

=================================================================
=================================================================

Description: One settings object on the Settings tab, with Org-wide, Profiles and Users sub-tabs.

Step 1: Show the organisation row, or the profiles or users that have a row, as a list beside the form
Step 2: Let the admin find a profile or user and start a new row that begins as a copy of the organisation values
Step 3: Save, or delete, one row through Apex and tell the Settings tab to reload

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { SCOPE_ORGANISATION, SCOPE_PROFILE, SCOPE_USER, TAB_COUNT_OPEN, TAB_COUNT_CLOSE, LABELS, FALLBACK_ERROR_MESSAGE } from "./aiAssistSettingsPanelSettings";

// Finds the organisation row, which always exists and is first.
export function findOrganisationRow(rows) {

  // [1] Look for the row at organisation level
  const organisationRow = rows.find((row) => row.scope === SCOPE_ORGANISATION);

  return organisationRow;
}

// Builds the list of entries for the Profiles or Users sub-tab: saved rows first, then profiles or users the admin has just added.
export function buildEntries(rows, newOwners, scope) {

  // [1] Saved rows at this level
  const entries = [];
  const savedRows = rows.filter((row) => row.scope === scope);

  savedRows.forEach((row) => {

    entries.push({ ownerId: row.ownerId, name: row.ownerName, row, isNew: false });
  });

  // [2] Owners added but not saved yet
  const addedOwners = newOwners.filter((owner) => owner.scope === scope);

  addedOwners.forEach((owner) => {

    entries.push({ ownerId: owner.ownerId, name: owner.name, row: null, isNew: true });
  });

  return entries;
}

// Keeps only the fields a profile or user row may hold, dropping groups left empty.
export function filterGroupsToOverridable(groups) {

  // [1] Keep the overridable fields of each group
  const filteredGroups = [];

  groups.forEach((group) => {

    const overridableFields = group.fields.filter((field) => field.overridable);
    const hasOverridableFields = overridableFields.length > 0;
    if (hasOverridableFields) filteredGroups.push({ ...group, fields: overridableFields });
  });

  return filteredGroups;
}

// Builds the values for the form: the saved row, or for a new row a copy of the organisation values.
export function buildFormValues(entry, organisationRow, formGroups) {

  // [1] Start from the saved row, or from the organisation row for a new one
  const hasSavedRow = entry && entry.row;
  const sourceRow = hasSavedRow ? entry.row : organisationRow;
  const sourceValues = sourceRow.values;
  const formValues = {};

  // [2] Copy the value of each field the form shows from the row
  formGroups.forEach((group) => {

    group.fields.forEach((field) => {

      const value = sourceValues[field.key];
      formValues[field.key] = value === undefined ? null : value;
    });
  });

  return formValues;
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

  return FALLBACK_ERROR_MESSAGE;
}

// Writes the label of a sub-tab with how many rows its level has, for example "Profiles (2)".
export function formatTabLabel(label, rowCount) {

  // [1] The name, then the count in brackets
  const tabLabel = label + TAB_COUNT_OPEN + rowCount + TAB_COUNT_CLOSE;

  return tabLabel;
}

// Builds the label of each sub-tab, with how many rows a level has.
export function buildSubTabs(rows, newOwners) {

  // [1] Count the rows at profile and user level
  const profileCount = buildEntries(rows, newOwners, SCOPE_PROFILE).length;
  const userCount = buildEntries(rows, newOwners, SCOPE_USER).length;

  // [2] Build the three tabs
  const organisationTab = { value: SCOPE_ORGANISATION, label: LABELS.organisationTab };
  const profileTab = { value: SCOPE_PROFILE, label: formatTabLabel(LABELS.profileTab, profileCount) };
  const userTab = { value: SCOPE_USER, label: formatTabLabel(LABELS.userTab, userCount) };

  return [organisationTab, profileTab, userTab];
}
