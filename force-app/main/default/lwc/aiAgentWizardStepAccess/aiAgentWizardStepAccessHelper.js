/*
Component Name: aiAgentWizardStepAccess

=================================================================
=================================================================

Description: The extended methods of the Access step: build the cards, the assignment rows, the user count banner and the agent picker note.

Step 1: Build the access cards and the assignment rows
Step 2: Write the banner that says how many users will see the agent
Step 3: Build the matches of the Check a user box

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { ACCESS_CARDS, ACCESS_ALL, ASSIGNEE_PERMISSION_SET, ASSIGNEE_USER, CARD_CLASS, CARD_SELECTED_CLASS, TAG_PERMISSION_SET_CLASS, TAG_USER_CLASS, LIST_SEPARATOR, NO_TEXT, LABELS } from "./aiAgentWizardStepAccessSettings";

// Builds the two access cards, with the chosen one marked.
export function buildAccessCards(accessMode) {

  // [1] One view for each mode
  const accessCards = ACCESS_CARDS.map((card) => ({ ...card, cardClass: card.value === accessMode ? CARD_SELECTED_CLASS : CARD_CLASS }));

  return accessCards;
}

// Finds the key of an assignment: the user id or the permission set name.
export function getAssignmentKey(assignment) {

  // [1] A user is named by the id, a permission set by its API name
  const isUser = assignment.assigneeType === ASSIGNEE_USER;
  const assignmentKey = isUser ? assignment.userId : assignment.permissionSetName;

  return assignmentKey;
}

// Writes how many users an assignment covers.
export function formatUserCount(userCount) {

  // [1] One or many
  if (userCount === 1) return LABELS.userOne;

  return (userCount || 0) + LABELS.userMany;
}

// Builds the rows of the assignment list.
export function buildAssignmentViews(assignments) {

  // [1] One row for each assignment
  const assignmentViews = [];

  (assignments || []).forEach((assignment) => {
    const isPermissionSet = assignment.assigneeType === ASSIGNEE_PERMISSION_SET;
    const tagLabel = isPermissionSet ? LABELS.permissionSet : LABELS.user;
    const tagClass = isPermissionSet ? TAG_PERMISSION_SET_CLASS : TAG_USER_CLASS;
    assignmentViews.push({ key: getAssignmentKey(assignment), label: assignment.label, userText: formatUserCount(assignment.userCount), isActive: Boolean(assignment.isActive), tagLabel, tagClass });
  });

  return assignmentViews;
}

// Writes the names of the objects as a sentence part: "Opportunity and Account".
export function formatObjectList(objectApiNames, objectOptions) {

  // [1] Find the label of each object
  const names = (objectApiNames || []).map((apiName) => {
    const found = (objectOptions || []).find((option) => option.apiName === apiName);

    return found ? found.label : apiName;
  });

  // [2] Join them with commas and a last "and"
  if (names.length <= 1) return names.join(LIST_SEPARATOR);
  const lastName = names[names.length - 1];
  const firstNames = names.slice(0, names.length - 1);

  return firstNames.join(LIST_SEPARATOR) + LABELS.and + lastName;
}

// Writes the banner that says how many users will see the agent.
export function buildUserBanner(accessMode, accessUserCount, assistUserCount, objectApiNames, objectOptions) {

  // [1] The count from the last check, or the whole AI Assist user count for everyone
  const isAll = accessMode === ACCESS_ALL;
  const count = accessUserCount !== null && accessUserCount !== undefined ? accessUserCount : isAll ? assistUserCount : null;
  if (count === null || count === undefined) return NO_TEXT;

  // [2] Say where they will see it
  const objectText = formatObjectList(objectApiNames, objectOptions);
  const bannerText = isAll ? LABELS.seeAllBefore + count + LABELS.seeAllMiddle + objectText + LABELS.seeAfter : count + LABELS.seeBefore + objectText + LABELS.seeAfter;

  return bannerText;
}

// Writes the note about the agent picker, naming the first object.
export function buildPickerNote(objectApiNames, objectOptions) {

  // [1] Name the first object
  const firstApiName = objectApiNames && objectApiNames.length > 0 ? objectApiNames[0] : NO_TEXT;
  const found = (objectOptions || []).find((option) => option.apiName === firstApiName);
  const objectName = found ? found.label : firstApiName || LABELS.pickerNoteFallback;
  const pickerNote = LABELS.pickerNote.replace("{object}", objectName);

  return pickerNote;
}

// Turns a finding into what the template shows.
export function buildFindingViews(findings) {

  // [1] One view for each finding
  const findingViews = (findings || []).map((finding, index) => ({ key: index, title: finding.title, message: finding.message }));

  return findingViews;
}

// Writes how many findings the step has.
export function formatFindingCount(count) {

  // [1] One or many
  if (count === 1) return LABELS.needLookOne;

  return count + LABELS.needLookMany;
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
