/*
Component Name: aiAgentWizardStepReview

=================================================================
=================================================================

Description: The extended methods of the Review step: build the banner, the list of findings and the summary cards, and write the result of a trial.

Step 1: Count the blockers and warnings and write the banner
Step 2: Build one row for each finding, with the button that jumps to its step
Step 3: Build the summary cards from the draft and the lists the page offers
Step 4: Write what a trial returned

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { STEP_BASICS, STEP_MODEL, STEP_DATA_SOURCES, STEP_ACTIONS, STEP_CONVERSATIONS, STEP_LIMITS, STEP_ACCESS, STEP_LABELS, SEVERITY_BLOCKER, LOAD_LABELS, VISIBILITY_LABELS, RETENTION_LABELS, TRACKING_LABELS, ACCESS_ALL, ACCESS_LABELS, ASSIGNEE_PERMISSION_SET, MAX_NAMES, ACTION_TYPE_SCREEN_FLOW, PILL_CLASS, PILL_SUCCESS_CLASS, PILL_DANGER_CLASS, PILL_WARNING_CLASS, LIST_SEPARATOR, MILLISECONDS_PER_SECOND, NO_TEXT, LABELS } from "./aiAgentWizardStepReviewSettings";

// Counts the findings that block activation.
export function countBlockers(findings) {

  // [1] Count the blockers
  const blockers = (findings || []).filter((finding) => finding.severity === SEVERITY_BLOCKER);

  return blockers.length;
}

// Writes the banner at the top: ready, or what stops activation.
export function buildBanner(findings) {

  // [1] Count what is found
  const findingList = findings || [];
  const blockerCount = countBlockers(findingList);
  const warningCount = findingList.length - blockerCount;

  // [2] Blockers stop activation
  if (blockerCount > 0) {

    const countText = blockerCount === 1 ? LABELS.blockedOne : blockerCount + LABELS.blockedMany;

    return { isBlocked: true, bold: LABELS.blockedBold + countText, text: LABELS.blockedSaveDraft };
  }

  // [3] Otherwise it is ready, with a note when there are warnings
  let text = LABELS.readyAllPassed;
  if (warningCount === 1) text = LABELS.readyWarningsOne;
  if (warningCount > 1) text = warningCount + LABELS.readyWarningsMany;

  return { isBlocked: false, bold: LABELS.readyBold, text };
}

// Builds the rows of the finding list.
export function buildFindingViews(findings) {

  // [1] One row for each finding
  const findingViews = [];

  (findings || []).forEach((finding, index) => {
    const isBlocker = finding.severity === SEVERITY_BLOCKER;
    findingViews.push({ key: index, step: finding.step, title: finding.title, message: finding.message, severityLabel: isBlocker ? LABELS.blocker : LABELS.warning, severityClass: isBlocker ? PILL_DANGER_CLASS : PILL_WARNING_CLASS, buttonLabel: LABELS.goTo + (STEP_LABELS[finding.step] || NO_TEXT), buttonVariant: isBlocker ? "brand-outline" : "neutral" });
  });

  return findingViews;
}

// Finds the label of an object, and falls back to its API name.
export function getObjectLabel(apiName, objectOptions) {

  // [1] Look in the list the tab passed
  const found = (objectOptions || []).find((option) => option.apiName === apiName);

  return found ? found.label : apiName;
}

// Lists the first few names, then how many more there are.
export function formatNames(names) {

  // [1] Show the first few
  const shown = names.slice(0, MAX_NAMES).join(LIST_SEPARATOR);
  const hiddenCount = names.length - MAX_NAMES;

  // [2] Say how many are left out
  return hiddenCount > 0 ? shown + " +" + hiddenCount + LABELS.more : shown;
}

// Builds a row of a summary card.
export function buildRow(key, label, value, pillLabel, pillClass) {

  // [1] A row has a label, a value and an optional pill in place of the value
  return { key, label, value, pillLabel: pillLabel || NO_TEXT, pillClass: pillClass || PILL_CLASS, hasPill: Boolean(pillLabel) };
}

// Builds the cards of the summary.
export function buildSummaryCards(draft, page, objectOptions, modelTest) {

  // [1] Find what the draft points at in the lists the page offers
  const pageLists = page || {};
  const model = (pageLists.models || []).find((candidate) => candidate.modelId === draft.modelConfigurationId);
  const template = (pageLists.promptTemplates || []).find((candidate) => candidate.templateId === draft.promptTemplateId);
  const dataSources = (draft.dataSourceIds || []).map((id) => (pageLists.dataSources || []).find((candidate) => candidate.dataSourceId === id)).filter((found) => Boolean(found));
  const actions = (draft.workflowActionIds || []).map((id) => (pageLists.workflowActions || []).find((candidate) => candidate.actionId === id)).filter((found) => Boolean(found));
  const writeActions = actions.filter((action) => action.isWrite);
  const askedActions = writeActions.filter((action) => action.requiresConfirmation || action.actionType === ACTION_TYPE_SCREEN_FLOW);

  // [2] Basics and Model
  const objectNames = (draft.objectApiNames || []).map((apiName) => getObjectLabel(apiName, objectOptions));
  const basicsRows = [buildRow("name", LABELS.name, draft.agentName || NO_TEXT), buildRow("pages", LABELS.pages, objectNames.join(LIST_SEPARATOR)), buildRow("template", LABELS.promptTemplate, template ? template.name : LABELS.defaultTemplate)];
  const modelRows = [buildRow("model", LABELS.configuration, model ? model.name : LABELS.noneChosen)];
  if (model) modelRows.push(buildConnectionRow(modelTest, model.modelId));

  // [3] Data sources and Workflow actions
  const dataSourceRows = [buildRow("selected", LABELS.selected, dataSources.length === 0 ? LABELS.none : dataSources.length + " · " + formatNames(dataSources.map((dataSource) => dataSource.name)))];
  const actionRows = [buildRow("selected", LABELS.selected, actions.length === 0 ? LABELS.readOnly : actions.length + " · " + formatNames(actions.map((action) => action.name)))];
  if (writeActions.length > 0) actionRows.push(buildRow("write", LABELS.writeActions, writeActions.length + (askedActions.length === writeActions.length ? LABELS.allAskFirst : ", " + askedActions.length + LABELS.someAskFirst)));

  // [4] Conversations, Limits and Access
  const retentionText = draft.conversationRetentionDays + LABELS.retentionDays + (RETENTION_LABELS[draft.retentionTrigger] || NO_TEXT);
  const conversationRows = [buildRow("load", LABELS.load, LOAD_LABELS[draft.conversationLoadTrigger] || NO_TEXT), buildRow("visibility", LABELS.visibility, VISIBILITY_LABELS[draft.conversationVisibility] || NO_TEXT), buildRow("retention", LABELS.retention, retentionText)];
  const limitRows = [buildRow("per", LABELS.perConversation, draft.maxMessagesPerConversation + LABELS.messages + " · " + Number(draft.maxTokensPerConversation).toLocaleString() + LABELS.tokens), buildRow("rounds", LABELS.toolRounds, String(draft.maxToolCallingIterations)), buildRow("counting", LABELS.counting, TRACKING_LABELS[draft.tokenTrackingMethod] || NO_TEXT)];
  const accessRows = [buildRow("mode", LABELS.mode, ACCESS_LABELS[draft.accessMode] || NO_TEXT), buildRow("users", LABELS.users, buildUsersText(draft, pageLists.assistUserCount))];

  return [{ key: "basics", title: LABELS.basics, step: STEP_BASICS, rows: basicsRows }, { key: "model", title: LABELS.model, step: STEP_MODEL, rows: modelRows }, { key: "dataSources", title: LABELS.dataSources, step: STEP_DATA_SOURCES, rows: dataSourceRows }, { key: "actions", title: LABELS.actions, step: STEP_ACTIONS, rows: actionRows }, { key: "conversations", title: LABELS.conversations, step: STEP_CONVERSATIONS, rows: conversationRows }, { key: "limits", title: LABELS.limits, step: STEP_LIMITS, rows: limitRows }, { key: "access", title: LABELS.access, step: STEP_ACCESS, rows: accessRows }];
}

// Builds the Connection row of the Model card.
export function buildConnectionRow(modelTest, modelId) {

  // [1] Only a check of this model counts
  const isCurrent = modelTest && modelTest.modelId === modelId;
  if (!isCurrent) return buildRow("connection", LABELS.connection, NO_TEXT, LABELS.notTested, PILL_CLASS);

  // [2] Green when connected, red when failed
  return modelTest.isSuccessful ? buildRow("connection", LABELS.connection, NO_TEXT, LABELS.connected, PILL_SUCCESS_CLASS) : buildRow("connection", LABELS.connection, NO_TEXT, LABELS.failed, PILL_DANGER_CLASS);
}

// Writes how many users have the agent, and how.
export function buildUsersText(draft, assistUserCount) {

  // [1] Everyone with the permission set
  if (draft.accessMode === ACCESS_ALL) return assistUserCount === null || assistUserCount === undefined ? LABELS.usersAllBefore.trim() : LABELS.usersAllBefore + assistUserCount + LABELS.usersAllAfter;

  // [2] The assigned users, and how many permission sets bring them
  const permissionSets = (draft.assignments || []).filter((assignment) => assignment.isActive && assignment.assigneeType === ASSIGNEE_PERMISSION_SET);
  const userCount = (draft.assignments || []).filter((assignment) => assignment.isActive).reduce((total, assignment) => total + (assignment.userCount || 0), 0);
  if (permissionSets.length === 0) return String(userCount);

  return userCount + LABELS.usersViaBefore + permissionSets.length + (permissionSets.length === 1 ? LABELS.usersViaPermissionSet : LABELS.usersViaPermissionSets);
}

// Writes the line under a trial: how long it took and how many tokens it used.
export function formatTrialMeta(result) {

  // [1] The time, then the tokens when Apex counted them
  const seconds = ((result.latencyMilliseconds || 0) / MILLISECONDS_PER_SECOND).toFixed(1) + LABELS.seconds;
  const tokenText = result.totalTokens ? Number(result.totalTokens).toLocaleString() + LABELS.tokensUnit : NO_TEXT;

  return [seconds, tokenText].filter((part) => Boolean(part)).join(" · ");
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
