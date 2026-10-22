/*
Component Name: aiPoliciesAssignments

=================================================================
=================================================================

Description: The extended methods of the Assignments tab: build one row for each assignment.

Step 1: Build the type pill, the name and the caption of each assignment

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { ASSIGNEE_TYPE_USER, TYPE_PILL_PERMISSION_SET_CLASS, TYPE_PILL_USER_CLASS, NO_TEXT, LABELS } from "./aiPoliciesAssignmentsSettings";

// Builds the rows of the table: one for each assignment.
export function buildAssignmentViews(assignments) {

  // [1] The parent may not have set any assignments yet
  const assignmentList = assignments || [];

  // [2] Build one row for each assignment
  const assignmentViews = assignmentList.map((assignment) => {

    const isUser = assignment.assigneeType === ASSIGNEE_TYPE_USER;
    const typeLabel = isUser ? LABELS.typeUser : LABELS.typePermissionSet;
    const typeClass = isUser ? TYPE_PILL_USER_CLASS : TYPE_PILL_PERMISSION_SET_CLASS;
    const caption = isUser ? LABELS.userCaption : NO_TEXT;

    return { key: assignment.assignmentId, assignmentId: assignment.assignmentId, typeLabel, typeClass, name: assignment.assigneeName, caption, hasCaption: isUser, usersCovered: assignment.usersCovered, isActive: assignment.isActive === true };
  });

  return assignmentViews;
}
