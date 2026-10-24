/*
Component Name: aiPoliciesAssignDialog

=================================================================
=================================================================

Description: The extended methods of the Add assignment dialog: build the list of assignees and write an error message.

Step 1: Build one row for each user or permission set that was found
Step 2: Build the switch between users and permission sets
Step 3: Turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import {
  ASSIGNEE_TYPE_USER,
  ASSIGNEE_TYPE_PERMISSION_SET,
  TYPE_BUTTON_CLASS,
  TYPE_BUTTON_SELECTED_CLASS,
  OPTION_CLASS,
  OPTION_SELECTED_CLASS,
  OPTION_DISABLED_CLASS,
  NO_TEXT,
  LABELS
} from "./aiPoliciesAssignDialogSettings";

// Writes how many users a permission set covers, such as "1 user" or "3 users".
export function formatUserCount(userCount) {
  // [1] One user is singular, any other number is plural
  const suffix = userCount === 1 ? LABELS.userOne : LABELS.userMany;
  const userCountText = userCount + suffix;

  return userCountText;
}

// Builds the rows of the list: the name, what the assignee gets today and any pill.
export function buildOptionViews(options, assigneeType, selectedId) {
  // [1] Build one row for each assignee that was found
  const optionViews = options.map((option) => {
    // [2] A user shows their username, a permission set shows how many users hold it
    const isUser = assigneeType === ASSIGNEE_TYPE_USER;
    const detail = isUser
      ? option.detail
      : formatUserCount(option.usersCovered);

    // [3] Say which policy they get today, and whether it is only the default
    const hasCurrentPolicy = Boolean(option.currentPolicyId);
    const currentPolicyName = hasCurrentPolicy
      ? option.currentPolicyName
      : LABELS.noCurrentPolicy;
    const defaultSuffix = option.isCurrentPolicyDefault
      ? LABELS.defaultSuffix
      : NO_TEXT;

    // [4] Pick the pill and the class of the row
    const isOnThisPolicy = option.isOnThisPolicy === true;
    const showHasPolicyPill = option.hasPolicy === true && !isOnThisPolicy;
    const isSelected = option.assigneeId === selectedId;
    let optionClass = isSelected ? OPTION_SELECTED_CLASS : OPTION_CLASS;
    if (isOnThisPolicy) optionClass = OPTION_DISABLED_CLASS;

    return {
      key: option.assigneeId,
      assigneeId: option.assigneeId,
      name: option.name,
      detail,
      currentPolicyName,
      defaultSuffix,
      currentLabel: LABELS.currentlyGet,
      isSelected,
      isDisabled: isOnThisPolicy,
      showHasPolicyPill,
      showOnThisPolicyPill: isOnThisPolicy,
      optionClass
    };
  });

  return optionViews;
}

// Builds the two choices of the switch between users and permission sets.
export function buildTypeButtons(assigneeType) {
  // [1] Build the two choices, with the class that marks the chosen one
  const types = [
    { value: ASSIGNEE_TYPE_USER, label: LABELS.typeUser },
    { value: ASSIGNEE_TYPE_PERMISSION_SET, label: LABELS.typePermissionSet }
  ];

  const typeButtons = types.map((type) => {
    const isSelected = type.value === assigneeType;
    const buttonClass = isSelected
      ? TYPE_BUTTON_SELECTED_CLASS
      : TYPE_BUTTON_CLASS;

    return { value: type.value, label: type.label, buttonClass, isSelected };
  });

  return typeButtons;
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
