/*
Component Name: aiAgentWizardAssigneeDialog

=================================================================
=================================================================

Description: The extended methods of the Add assignment dialog: build the type buttons and the rows, and write the errors Apex threw.

Step 1: Build the type buttons, with the chosen one marked
Step 2: Build one row for each match, marking the ones already added and the ones ticked
Step 3: Turn a row back into the assignment the tab keeps

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { ASSIGNEE_USER, TYPE_CHOICES, SEG_CLASS, SEG_SELECTED_CLASS, OPTION_CLASS, OPTION_SELECTED_CLASS, OPTION_DISABLED_CLASS, NO_TEXT, LABELS } from "./aiAgentWizardAssigneeDialogSettings";

// Builds the type buttons, with the chosen one marked.
export function buildTypeButtons(assigneeType) {

  // [1] One button for each type
  const typeButtons = TYPE_CHOICES.map((choice) => ({ ...choice, buttonClass: choice.value === assigneeType ? SEG_SELECTED_CLASS : SEG_CLASS }));

  return typeButtons;
}

// Finds the key of an assignee: the user id or the permission set name.
export function getAssigneeKey(assignee) {

  // [1] A user is named by the id, a permission set by its API name
  const isUser = assignee.assigneeType === ASSIGNEE_USER;
  const assigneeKey = isUser ? assignee.userId : assignee.permissionSetName;

  return assigneeKey;
}

// Writes how many users an assignee covers.
export function formatUserCount(userCount) {

  // [1] One or many
  if (userCount === 1) return LABELS.userOne;

  return (userCount || 0) + LABELS.userMany;
}

// Builds the rows of the matches of the search.
export function buildOptionViews(matches, assigneeType, existingAssignments, selectedKeys) {

  // [1] Keep the matches of the type that is chosen
  const existingKeys = (existingAssignments || []).map((assignment) => getAssigneeKey(assignment));
  const typeMatches = matches.filter((match) => match.assigneeType === assigneeType);

  // [2] Build a row for each match
  const optionViews = typeMatches.map((match) => {
    const key = getAssigneeKey(match);
    const isAdded = existingKeys.includes(key);
    const isSelected = !isAdded && selectedKeys.includes(key);
    let optionClass = isSelected ? OPTION_SELECTED_CLASS : OPTION_CLASS;
    if (isAdded) optionClass = OPTION_DISABLED_CLASS;

    return { key, label: match.label, detail: formatUserCount(match.userCount), isAdded, isSelected, optionClass, addedLabel: LABELS.alreadyAdded };
  });

  return optionViews;
}

// Turns the ticked matches into the assignments the tab keeps, switched on.
export function buildNewAssignments(matches, selectedKeys) {

  // [1] One assignment for each ticked match
  const picked = matches.filter((match) => selectedKeys.includes(getAssigneeKey(match)));
  const newAssignments = picked.map((match) => ({ assigneeType: match.assigneeType, userId: match.userId, permissionSetName: match.permissionSetName, label: match.label, userCount: match.userCount, isActive: true }));

  return newAssignments;
}

// Turns whatever an Apex call threw into text.
export function formatErrorMessage(error) {

  // [1] An Apex refusal carries its message in the body
  const errorBody = error && error.body;
  const bodyMessage = errorBody && errorBody.message;
  if (bodyMessage) return bodyMessage;

  // [2] A plain error has a message
  const plainMessage = error && error.message;
  if (plainMessage) return plainMessage;

  return NO_TEXT;
}
