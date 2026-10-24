/*
Component Name: aiToolsDsQueryEditor

=================================================================
=================================================================

Description: The extended methods of the SOQL editor: build the rows of the problems list.

Step 1: Build one row for each problem, with its pill, its line and its fix

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { SEVERITY_ERROR, PILL_ERROR_CLASS, PILL_WARNING_CLASS, LABELS } from "./aiToolsDsQueryEditorSettings";

// Builds one row for each problem.
export function buildProblemViews(problems) {

  // [1] Pick the pill and write the line of each problem
  const problemViews = problems.map((problem, index) => {

    const isError = problem.severity === SEVERITY_ERROR;
    const pillClass = isError ? PILL_ERROR_CLASS : PILL_WARNING_CLASS;
    const hasFix = Boolean(problem.fixLabel);

    return { key: "problem" + index, severity: problem.severity, pillClass, lineLabel: LABELS.line + problem.line + ":", message: problem.message, hasFix, fixLabel: problem.fixLabel, fixStart: problem.fixStart, fixEnd: problem.fixEnd, fixText: problem.fixText };
  });

  return problemViews;
}
