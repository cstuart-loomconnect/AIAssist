/*
Component Name: aiPiiRegistryUnprotected

=================================================================
=================================================================

Description: The settings of the warning banner for objects agents read without cover: label text and limits.

Step 1: Hold the text shown to the admin
Step 2: Hold how many fields a row lists before it says "and more"

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Text shown to the user.
export const LABELS = {
  headlineOne: "1 object is read by agents but not in the registry.",
  headlineManyBefore: "",
  headlineManyAfter: " objects are read by agents but not in the registry.",
  headlineRest: " Their fields go to the provider unmasked.",
  columnObject: "Object",
  columnReadBy: "Read by",
  columnFieldsSent: "Fields sent",
  dataSourceOne: "Data source: ",
  dataSourceMany: "Data sources: ",
  fieldsFromApex: "Chosen by the Apex class",
  andMoreBefore: " and ",
  andMoreAfter: " more",
  addToRegistry: "Add to registry",
  footnote: "Found by checking every active data source's target object against the registry. Shown at the top of this tab until fixed.",
  listSeparator: ", "
};

// How many fields a row lists before the rest are counted.
export const MAX_FIELDS_LISTED = 8;

// The name of the event the banner sends to the tab.
export const EVENT_ADD_OBJECT = "addobject";
