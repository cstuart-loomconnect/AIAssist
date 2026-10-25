/*
Component Name: aiToolsSkillWizard

=================================================================
=================================================================

Description: The extended methods of the skill wizard: check each step, build the stepper, and turn the draft into what Apex saves and back.

Step 1: Work out the bound object of the tools and the @ names the instructions use that are not tools
Step 2: Say whether each step is complete, and build the stepper with its markers
Step 3: Build the skill Apex saves from the draft, and the draft from a saved skill
Step 4: Turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { STEP_BASICS, STEP_TOOLS, STEP_INSTRUCTIONS, STEP_NAMES, BINDING_BOUND, TOOL_KIND_DATA_SOURCE, API_NAME_PATTERN, MENTION_PATTERN, DESCRIPTION_MIN_LENGTH, DESCRIPTION_MAX_LENGTH, MAX_TOOLS, STEP_CLASS, STEP_CURRENT_CLASS, STEP_DONE_CLASS, STEP_ERROR_CLASS, MARKER_DONE, MARKER_ERROR, NO_TEXT, LABELS } from "./aiToolsSkillWizardSettings";

// The objects of the bound data sources in the skill, without repeats. A skill runs on one open record, so more than one is a problem.
export function getBoundObjects(tools) {

  // [1] Keep the object of each bound data source once
  const boundObjects = [];

  (tools || []).forEach((tool) => {

    const isBoundSource = tool.kind === TOOL_KIND_DATA_SOURCE && tool.bindingType === BINDING_BOUND && Boolean(tool.targetObject);
    if (isBoundSource && !boundObjects.includes(tool.targetObject)) boundObjects.push(tool.targetObject);
  });

  return boundObjects;
}

// The @ names in the instructions that are not the API name of a tool in the skill, in the order they first appear.
export function getUnknownMentions(instructions, tools) {

  // [1] Collect the API names of the tools
  const toolNames = (tools || []).map((tool) => (tool.developerName || NO_TEXT).toLowerCase());

  // [2] Keep each @ name that is not one of them
  const unknownMentions = [];
  const mentions = (instructions || NO_TEXT).matchAll(MENTION_PATTERN);

  for (const mention of mentions) {

    const mentionedName = mention[1];
    const isKnown = toolNames.includes(mentionedName.toLowerCase());
    if (!isKnown && !unknownMentions.includes(mentionedName)) unknownMentions.push(mentionedName);
  }

  return unknownMentions;
}

// True when the When To Use It text is between the shortest and longest length the trigger allows.
export function isDescriptionLengthValid(description) {

  // [1] Count the characters the trigger counts
  const descriptionLength = (description || NO_TEXT).trim().length;
  const isDescriptionLengthValid = descriptionLength >= DESCRIPTION_MIN_LENGTH && descriptionLength <= DESCRIPTION_MAX_LENGTH;

  return isDescriptionLengthValid;
}

// True when the step holds everything it needs to go on.
export function isStepValid(draft, stepNumber) {

  // [1] Basics: a name, an API name of the right shape and a When To Use It of the right length
  if (stepNumber === STEP_BASICS) return Boolean((draft.skillName || NO_TEXT).trim()) && API_NAME_PATTERN.test((draft.developerName || NO_TEXT).trim()) && isDescriptionLengthValid(draft.description);

  // [2] Tools: at least one, no more than the limit, and bound data sources on one object
  if (stepNumber === STEP_TOOLS) return (draft.tools || []).length > 0 && draft.tools.length <= MAX_TOOLS && getBoundObjects(draft.tools).length <= 1;

  // [3] Instructions: some text, and every @ name a tool in the skill
  if (stepNumber === STEP_INSTRUCTIONS) return Boolean((draft.instructions || NO_TEXT).trim()) && getUnknownMentions(draft.instructions, draft.tools).length === 0;

  // [4] The test step is never required
  return true;
}

// True when a step the admin has passed is now incomplete.
export function hasStepProblem(draft, stepNumber, currentStep) {

  // [1] Only a step already passed can show a problem
  const hasStepProblem = stepNumber < currentStep && !isStepValid(draft, stepNumber);

  return hasStepProblem;
}

// Builds the stepper: one view for each step with its class, marker and whether it can be clicked.
export function buildStepViews(draft, currentStep, maxStep) {

  // [1] Build one view for each step
  const stepViews = STEP_NAMES.map((step) => {

    const isCurrent = step.number === currentStep;
    const isReachable = step.number <= maxStep;
    const hasProblem = hasStepProblem(draft, step.number, currentStep);
    const isDone = step.number < currentStep && !hasProblem;

    // [2] Choose the class and the marker
    let stepClass = STEP_CLASS;
    let marker = String(step.number);

    if (hasProblem) {

      stepClass = STEP_ERROR_CLASS;
      marker = MARKER_ERROR;

    } else if (isCurrent) {

      stepClass = STEP_CURRENT_CLASS;

    } else if (isDone) {

      stepClass = STEP_DONE_CLASS;
      marker = MARKER_DONE;
    }

    const hasLine = step.number < STEP_NAMES.length;

    return { number: step.number, label: step.label, stepClass, marker, isDisabled: !isReachable, hasLine };
  });

  return stepViews;
}

// Builds the skill Apex saves and tests from the draft. The tools keep their order and only what Apex reads is sent.
export function buildSkillDetail(draft) {

  // [1] Copy the tools Apex reads
  const tools = (draft.tools || []).map((tool) => ({ kind: tool.kind, recordId: tool.recordId, isRequired: tool.isRequired !== false }));

  // [2] Copy the skill
  const skillDetail = { skillId: draft.skillId, skillName: (draft.skillName || NO_TEXT).trim(), developerName: (draft.developerName || NO_TEXT).trim(), description: draft.description, instructions: draft.instructions, outputType: draft.outputType, isActive: draft.isActive === true, lastTestStatus: draft.lastTestStatus || null, lastTestedOn: draft.lastTestedOn, tools };

  return skillDetail;
}

// Builds the draft from a saved skill.
export function buildDraftFromDetail(detail) {

  // [1] Copy every value the steps show, with the tools in order
  const tools = (detail.tools || []).map((tool) => ({ ...tool }));
  const draft = { skillId: detail.skillId, skillName: detail.skillName || NO_TEXT, developerName: detail.developerName || NO_TEXT, description: detail.description || NO_TEXT, instructions: detail.instructions || NO_TEXT, outputType: detail.outputType, isActive: detail.isActive === true, lastTestStatus: detail.lastTestStatus || NO_TEXT, lastTestedOn: detail.lastTestedOn, agentCount: detail.agentCount || 0, agentNames: detail.agentNames || [], boundObject: detail.boundObject, tools };

  return draft;
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
