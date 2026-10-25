/*
Component Name: aiPiiRegistryUnprotected

=================================================================
=================================================================

Description: The extended methods of the warning banner: write the headline and build the rows.

Step 1: Write the headline for one object or several
Step 2: Build one row for each object, with who reads it and the fields sent

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS, MAX_FIELDS_LISTED } from "./aiPiiRegistryUnprotectedSettings";

// Writes the bold part of the headline, such as "2 objects are read by agents but not in the registry."
export function buildHeadline(objectCount) {

  // [1] One is singular, any other number is plural
  if (objectCount === 1) return LABELS.headlineOne;

  const headline = LABELS.headlineManyBefore + objectCount + LABELS.headlineManyAfter;

  return headline;
}

// Builds the rows of the banner's table.
export function buildUnprotectedRows(objects) {

  // [1] Build a row for each object
  const rows = objects.map((unprotectedObject) => {

    const dataSourceNames = unprotectedObject.dataSourceNames;
    const readByPrefix = dataSourceNames.length === 1 ? LABELS.dataSourceOne : LABELS.dataSourceMany;
    const readBy = readByPrefix + dataSourceNames.join(LABELS.listSeparator);
    const fieldsSent = buildFieldsText(unprotectedObject.fieldsSent);

    return { key: unprotectedObject.objectApiName, objectApiName: unprotectedObject.objectApiName, readBy, fieldsSent };
  });

  return rows;
}

// Lists the first fields a data source sends, and counts the rest. An Apex data source has none listed.
export function buildFieldsText(fieldsSent) {

  // [1] An Apex data source chooses its own fields
  if (!fieldsSent || fieldsSent.length === 0) return LABELS.fieldsFromApex;

  // [2] List the first few and count the rest
  const listedFields = fieldsSent.slice(0, MAX_FIELDS_LISTED).join(LABELS.listSeparator);
  const hiddenCount = fieldsSent.length - MAX_FIELDS_LISTED;
  if (hiddenCount <= 0) return listedFields;

  const fieldsText = listedFields + LABELS.andMoreBefore + hiddenCount + LABELS.andMoreAfter;

  return fieldsText;
}
