/*
Component Name: aiToolsDsQueryEditor

=================================================================
=================================================================

Description: The settings of the SOQL editor: severities, class names and label text.

Step 1: Name the two severities of a problem, which Apex sends
Step 2: Name the classes of the severity pills
Step 3: Hold the label text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The severities of a problem. Mirror AIAssistApplicationConstants.TOOLS_PROBLEM_ERROR and TOOLS_PROBLEM_WARNING.
export const SEVERITY_ERROR = "Error";
export const SEVERITY_WARNING = "Warning";

// The classes of the severity pills.
export const PILL_ERROR_CLASS = "aiadqe-pill aiadqe-pill_error";
export const PILL_WARNING_CLASS = "aiadqe-pill aiadqe-pill_warning";

// Text shown to the user.
export const LABELS = {
  editorLabel: "SOQL query",
  problems: "Problems",
  noProblems: "No problems found.",
  line: "Line ",
  noteText: "Only SELECT is allowed. DML, sub-queries over 1 level, and dynamic object names are rejected by the query check before the query can be saved. Max rows is added as the LIMIT automatically when there is none."
};
