/*
Component Name: aiToolsSkStepTest

=================================================================
=================================================================

Description: The extended methods of step 4 of the skill wizard: find the record the skill needs, build the agent options, and describe how a test ended.

Step 1: Find the object of the skill's bound data sources
Step 2: Build the agent options from the agents Apex lists
Step 3: Build the result banner, the line of timings and the steps
Step 4: Turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { TEST_STATUS_PASSED, TEST_STATUS_NOT_PICKED, TOOL_KIND_DATA_SOURCE, BINDING_BOUND, BANNER_PASSED_CLASS, BANNER_WARNING_CLASS, BANNER_FAILED_CLASS, STEP_OK_CLASS, STEP_FAILED_CLASS, NO_TEXT, LABELS } from "./aiToolsSkStepTestSettings";

// The object of the first bound data source in the skill, or blank when the skill runs on any page.
export function getBoundObject(tools) {

  // [1] Find the first bound data source with an object
  const boundTool = (tools || []).find((tool) => tool.kind === TOOL_KIND_DATA_SOURCE && tool.bindingType === BINDING_BOUND && Boolean(tool.targetObject));
  const boundObject = boundTool ? boundTool.targetObject : NO_TEXT;

  return boundObject;
}

// Builds the options of the agent box: the agent's name with its model.
export function buildAgentOptions(agents) {

  // [1] One option for each agent
  const agentOptions = (agents || []).map((agent) => ({ label: agent.agentName + (agent.modelName ? " · " + agent.modelName : NO_TEXT), value: agent.agentId }));

  return agentOptions;
}

// Builds the banner that says how the test ended.
export function buildBannerView(result) {

  // [1] Passed is green, not picked is orange, anything else is red with the reason
  if (result.status === TEST_STATUS_PASSED) return { text: LABELS.passed, bannerClass: BANNER_PASSED_CLASS };
  if (result.status === TEST_STATUS_NOT_PICKED) return { text: LABELS.notPicked + (result.message || NO_TEXT), bannerClass: BANNER_WARNING_CLASS };

  return { text: LABELS.failed + (result.message || NO_TEXT), bannerClass: BANNER_FAILED_CLASS };
}

// Writes how long the test took and how many tokens it used.
export function buildMetaText(result) {

  // [1] The time and the tokens, when Apex gave them
  const elapsed = result.elapsedMilliseconds == null ? 0 : Math.round(result.elapsedMilliseconds);
  const tokens = result.totalTokens == null ? 0 : Math.round(result.totalTokens);
  const metaText = elapsed + LABELS.meta + tokens + LABELS.tokens;

  return metaText;
}

// Builds one line for each step of the test turn, in order.
export function buildStepViews(result) {

  // [1] One line for each step, with a tick or a cross
  const stepViews = (result.steps || []).map((step, stepIndex) => ({ key: String(stepIndex), stepType: step.stepType, detail: step.detail, mark: step.isSuccess ? LABELS.stepOk : LABELS.stepFailed, markClass: step.isSuccess ? STEP_OK_CLASS : STEP_FAILED_CLASS }));

  return stepViews;
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
