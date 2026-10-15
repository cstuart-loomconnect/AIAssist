/*
Component Name: aiAssistUsagePolicies

=================================================================
=================================================================

Description: The extended methods of the AI Usage Policies tab: build the policy list, keep it in order and write an error message.

Step 1: Build one list item for each policy, with its pills and assignment count
Step 2: Replace one policy in the list with its saved version
Step 3: Turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS, POLICY_ITEM_CLASS, POLICY_ITEM_SELECTED_CLASS, PILL_ACTIVE_CLASS, PILL_INACTIVE_CLASS, PILL_DEFAULT_CLASS, FIELD_IS_ACTIVE, FIELD_IS_DEFAULT, RANK_DEFAULT_FIRST, RANK_DEFAULT_LAST, NO_TEXT } from "./aiAssistUsagePoliciesSettings";

// Builds the list items for the policies, with an extra item for a new policy that is not saved yet.
export function buildPolicyItems(policies, selectedKey, isNewPolicy) {

  // [1] Build an item for each saved policy
  const items = [];

  policies.forEach((policy) => {

    const isSelected = policy.policyId === selectedKey;
    const itemClass = isSelected ? POLICY_ITEM_SELECTED_CLASS : POLICY_ITEM_CLASS;
    const countLabel = formatAssignmentCount(policy.assignments.length);
    const isActive = policy.values[FIELD_IS_ACTIVE] === true;
    const isDefault = policy.values[FIELD_IS_DEFAULT] === true;
    const activeLabel = isActive ? LABELS.active : LABELS.inactive;
    const activeClass = isActive ? PILL_ACTIVE_CLASS : PILL_INACTIVE_CLASS;
    items.push({ key: policy.policyId, name: policy.name, countLabel, itemClass, activeLabel, activeClass, isDefault, defaultLabel: LABELS.defaultPill, defaultClass: PILL_DEFAULT_CLASS, hasPills: true });
  });

  // [2] Add the new policy at the end, selected
  if (isNewPolicy) items.push({ key: selectedKey, name: LABELS.newPolicyName, countLabel: LABELS.newPolicyNote, itemClass: POLICY_ITEM_SELECTED_CLASS, activeLabel: NO_TEXT, activeClass: NO_TEXT, isDefault: false, defaultLabel: NO_TEXT, defaultClass: NO_TEXT, hasPills: false });

  return items;
}

// Writes how many assignments a policy has, such as "1 assignment" or "3 assignments".
export function formatAssignmentCount(assignmentCount) {

  // [1] One assignment is singular, any other number is plural
  const suffix = assignmentCount === 1 ? LABELS.assignmentCountOne : LABELS.assignmentCountMany;
  const countLabel = assignmentCount + suffix;

  return countLabel;
}

// Gets the sort rank of a policy: default policies come first.
export function getDefaultRank(policy) {

  // [1] A default policy ranks first, any other policy last
  const isDefault = policy.values[FIELD_IS_DEFAULT] === true;
  const rank = isDefault ? RANK_DEFAULT_FIRST : RANK_DEFAULT_LAST;

  return rank;
}

// Puts a saved policy into the list in place of the old one, or at the end when it is new, and keeps the list in name order with the defaults first.
export function replacePolicy(policies, savedPolicy) {

  // [1] Remove the old version, if there is one
  const others = policies.filter((policy) => policy.policyId !== savedPolicy.policyId);

  // [2] Add the saved one
  const combined = [...others, savedPolicy];

  // [3] Sort with the defaults first, then by name
  combined.sort((first, second) => {

    const firstRank = getDefaultRank(first);
    const secondRank = getDefaultRank(second);
    if (firstRank !== secondRank) return firstRank - secondRank;

    return first.name.localeCompare(second.name);
  });

  return combined;
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
