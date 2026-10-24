/*
Component Name: aiPromptTemplatesUsedBy

=================================================================
=================================================================

Description: The settings of the Used by tab: class names and label text.

Step 1: Name the classes of the status pills
Step 2: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The classes of the status pills.
export const PILL_ACTIVE_CLASS = "aipt-pill aipt-pill_success";
export const PILL_INACTIVE_CLASS = "aipt-pill aipt-pill_neutral";

// The toast variant.
export const TOAST_VARIANT_ERROR = "error";

// Text shown to the user.
export const LABELS = {
  loading: "Loading",
  fallbackError: "Something went wrong. Please try again.",
  columnAgent: "Agent",
  columnUsers: "Users",
  columnOpen: "Open conversations",
  columnStatus: "Status",
  active: "Active",
  inactive: "Inactive",
  usesDefault: "uses the default",
  fallbackNote: "Agents with no template of their own use the default template.",
  empty: "No agent uses this template yet. Pick it on the agent record."
};
