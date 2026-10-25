/*
Component Name: aiPolicies

=================================================================
=================================================================

Description: The extended methods of the AI Policies tab: build the policy list, keep it in order and write an error message.

Step 1: Build one list item for each policy, with its Default pill and its assignment summary
Step 2: Replace one policy in the list with its saved version
Step 3: Turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import {
  LABELS,
  FIELD_IS_DEFAULT,
  ASSIGNEE_TYPE_USER,
  POLICY_ITEM_CLASS,
  POLICY_ITEM_SELECTED_CLASS,
  RANK_DEFAULT_FIRST,
  RANK_DEFAULT_LAST,
  NO_TEXT
} from "./aiPoliciesSettings";

// Builds the list items for the policies, with an extra item for a new policy that is not saved yet.
export function buildPolicyItems(policies, selectedKey, isNewPolicy) {
  // [1] Build an item for each saved policy
  const items = [];

  policies.forEach((policy) => {
    const isSelected = policy.policyId === selectedKey;
    const itemClass = isSelected
      ? POLICY_ITEM_SELECTED_CLASS
      : POLICY_ITEM_CLASS;
    const isDefault = policy.values[FIELD_IS_DEFAULT] === true;
    const summary = formatAssignmentSummary(policy.assignments, isDefault);
    items.push({
      key: policy.policyId,
      name: policy.name,
      summary,
      itemClass,
      isDefault,
      defaultLabel: LABELS.defaultPill
    });
  });

  // [2] Add the new policy at the end, selected
  if (isNewPolicy)
    items.push({
      key: selectedKey,
      name: LABELS.newPolicyName,
      summary: LABELS.newPolicyNote,
      itemClass: POLICY_ITEM_SELECTED_CLASS,
      isDefault: false,
      defaultLabel: NO_TEXT
    });

  return items;
}

// Writes what a policy is assigned to, such as "Default · 2 permission sets, 1 user" or "4 users".
export function formatAssignmentSummary(assignments, isDefault) {
  // [1] Count the users and the permission sets
  const assignmentList = assignments || [];
  const userCount = assignmentList.filter(
    (assignment) => assignment.assigneeType === ASSIGNEE_TYPE_USER
  ).length;
  const permissionSetCount = assignmentList.length - userCount;

  // [2] Write each count that is not zero
  const parts = [];
  if (permissionSetCount > 0)
    parts.push(
      permissionSetCount +
        (permissionSetCount === 1
          ? LABELS.permissionSetOne
          : LABELS.permissionSetMany)
    );
  if (userCount > 0)
    parts.push(
      userCount + (userCount === 1 ? LABELS.userOne : LABELS.userMany)
    );
  const countText = parts.length > 0 ? parts.join(", ") : LABELS.noAssignments;

  // [3] A default policy says so first
  const summary = isDefault
    ? LABELS.defaultPrefix + LABELS.summarySeparator + countText
    : countText;

  return summary;
}

// Gets the sort rank of a policy: the default policy comes first.
export function getDefaultRank(policy) {
  // [1] A default policy ranks first, any other policy last
  const isDefault = policy.values[FIELD_IS_DEFAULT] === true;
  const rank = isDefault ? RANK_DEFAULT_FIRST : RANK_DEFAULT_LAST;

  return rank;
}

// Puts a saved policy into the list in place of the old one, or at the end when it is new, and keeps the list in name order with the default first.
export function replacePolicy(policies, savedPolicy) {
  // [1] Remove the old version, if there is one
  const others = policies.filter(
    (policy) => policy.policyId !== savedPolicy.policyId
  );

  // [2] Add the saved one
  const combined = [...others, savedPolicy];

  // [3] A policy made the default takes the Default pill from the others
  const savedIsDefault = savedPolicy.values[FIELD_IS_DEFAULT] === true;
  const fixed = combined.map((policy) => {
    const needsFix =
      savedIsDefault &&
      policy.policyId !== savedPolicy.policyId &&
      policy.values[FIELD_IS_DEFAULT] === true;

    return needsFix
      ? { ...policy, values: { ...policy.values, [FIELD_IS_DEFAULT]: false } }
      : policy;
  });

  // [4] Sort with the default first, then by name
  fixed.sort((first, second) => {
    const firstRank = getDefaultRank(first);
    const secondRank = getDefaultRank(second);
    if (firstRank !== secondRank) return firstRank - secondRank;

    return first.name.localeCompare(second.name);
  });

  return fixed;
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
