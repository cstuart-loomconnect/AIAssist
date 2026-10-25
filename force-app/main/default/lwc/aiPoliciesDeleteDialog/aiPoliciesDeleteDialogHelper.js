/*
Component Name: aiPoliciesDeleteDialog

=================================================================
=================================================================

Description: The extended methods of the delete dialog: build the message, the choices and the id of the policy the people move to.

Step 1: Build the opening sentence, with the number of users in bold
Step 2: Build the choices of the dropdown of other policies
Step 3: Work out the policy the people move to
Step 4: Turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import {
  MOVE_TO_DEFAULT,
  MOVE_TO_OTHER,
  NO_TEXT,
  LABELS
} from "./aiPoliciesDeleteDialogSettings";

// Builds the opening sentence in three parts, so the number of users can be bold.
export function buildMessageParts(options, policyName) {
  // [1] Nothing is known until the options arrive
  if (!options)
    return {
      policyName,
      hasPeople: false,
      beforeCount: NO_TEXT,
      countText: NO_TEXT,
      afterCount: NO_TEXT,
      noPeopleText: NO_TEXT
    };

  // [2] A policy with no assignments affects nobody
  const userCount = options.userCount || 0;
  const hasPeople = options.assignmentCount > 0;
  const suffix = userCount === 1 ? LABELS.userOne : LABELS.userMany;

  return {
    policyName,
    hasPeople,
    beforeCount: LABELS.isAssignedTo,
    countText: userCount + suffix,
    afterCount: LABELS.chooseWhat,
    noPeopleText: LABELS.noAssignments
  };
}

// Builds the choices of the dropdown of other policies.
export function buildPolicyChoices(options, otherPolicyId) {
  // [1] One choice for each other policy, marking the chosen one
  const policies = options ? options.otherPolicies : [];
  const policyChoices = policies.map((policy) => ({
    value: policy.policyId,
    label: policy.name,
    isSelected: policy.policyId === otherPolicyId
  }));

  return policyChoices;
}

// Works out the policy the people move to, or null when the policy has nobody to move.
export function getMoveToPolicyId(options, moveMode, otherPolicyId) {
  // [1] Nobody to move
  if (!options || !(options.assignmentCount > 0)) return null;

  // [2] The default policy, or the one picked from the list
  const moveToPolicyId =
    moveMode === MOVE_TO_DEFAULT ? options.defaultPolicyId : otherPolicyId;

  return moveToPolicyId || null;
}

// Says whether the admin has chosen a way to move the people that can be used.
export function isMoveChosen(options, moveMode, otherPolicyId) {
  // [1] A policy with nobody to move needs no choice
  if (!options) return false;
  if (!(options.assignmentCount > 0)) return true;

  // [2] The default needs a default policy, the other way needs a policy picked
  const isDefaultChosen =
    moveMode === MOVE_TO_DEFAULT && Boolean(options.defaultPolicyId);
  const isOtherChosen = moveMode === MOVE_TO_OTHER && Boolean(otherPolicyId);

  return isDefaultChosen || isOtherChosen;
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
