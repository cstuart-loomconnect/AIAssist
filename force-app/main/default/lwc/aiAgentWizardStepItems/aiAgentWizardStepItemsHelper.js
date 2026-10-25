/*
Component Name: aiAgentWizardStepItems

=================================================================
=================================================================

Description: The extended methods of the Data sources and Workflow actions steps: build the rows of what is added, the summary of the actions and the findings.

Step 1: Build one row for each data source or action that is added, with its line of detail and its pills
Step 2: Build the summary of the actions that are added
Step 3: Build the findings the step shows

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { KIND_DATA_SOURCE, ACTION_TYPE_APEX, ACTION_TYPE_SCREEN_FLOW, CODE_WORKFLOW_ACTIONS_DISABLED, SEVERITY_BLOCKER, PILL_CLASS, PILL_WARNING_CLASS, PILL_DANGER_CLASS, DETAIL_SEPARATOR, LIST_SEPARATOR, NO_TEXT, LABELS } from "./aiAgentWizardStepItemsSettings";

// Writes the name of an action type for the admin.
export function formatActionType(actionType) {

  // [1] One answer for each type
  if (actionType === ACTION_TYPE_SCREEN_FLOW) return LABELS.screenFlowType;
  if (actionType === ACTION_TYPE_APEX) return LABELS.apexType;

  return LABELS.flowType;
}

// Says whether the user is asked before an action runs.
export function isAskedFirst(option) {

  // [1] A write that asks, or a screen flow that opens a modal, puts the user in charge
  const isScreenFlow = option.actionType === ACTION_TYPE_SCREEN_FLOW;
  const asks = Boolean(option.isWrite) && (Boolean(option.requiresConfirmation) || isScreenFlow);

  return asks;
}

// Builds the row of one data source.
export function buildDataSourceView(option) {

  // [1] The line of detail: type, object, binding and the most rows it reads
  const bindingText = option.bindingType === "Bound" ? LABELS.bound : LABELS.unbound;
  const rowsText = option.maxRows ? LABELS.maxRows.replace("{count}", option.maxRows) : NO_TEXT;
  const detail = [option.sourceType, option.targetObject, bindingText, rowsText].filter((part) => Boolean(part)).join(DETAIL_SEPARATOR);

  // [2] The pills say what to know about it
  const pills = [];
  if (option.isPiiProtected) pills.push({ key: "pii", label: LABELS.piiMasked, pillClass: PILL_CLASS });
  if (!option.isActive) pills.push({ key: "inactive", label: LABELS.inactive, pillClass: PILL_DANGER_CLASS });

  return { key: option.dataSourceId, name: option.name, detail, extra: option.description || NO_TEXT, pills };
}

// Builds the row of one workflow action.
export function buildActionView(option) {

  // [1] The line of detail: type, whether it writes, and the object it changes
  const writeText = option.isWrite ? LABELS.writeText : LABELS.readText;
  const detail = [formatActionType(option.actionType), writeText, option.targetObject].filter((part) => Boolean(part)).join(DETAIL_SEPARATOR);

  // [2] The second line: the flow, its active version and who finishes it
  const hasVersion = option.activeFlowVersion !== null && option.activeFlowVersion !== undefined;
  const versionText = hasVersion ? LABELS.activeVersion + option.activeFlowVersion : NO_TEXT;
  const finishText = option.actionType === ACTION_TYPE_SCREEN_FLOW ? LABELS.userFinishes : NO_TEXT;
  const extra = [option.flowApiName, versionText, finishText].filter((part) => Boolean(part)).join(DETAIL_SEPARATOR) || option.description || NO_TEXT;

  // [3] The pills say how it runs and what is wrong with it
  const pills = [];
  if (option.actionType === ACTION_TYPE_SCREEN_FLOW) pills.push({ key: "modal", label: LABELS.opensModal, pillClass: PILL_WARNING_CLASS });
  if (option.actionType !== ACTION_TYPE_SCREEN_FLOW && isAskedFirst(option)) pills.push({ key: "asks", label: LABELS.asksFirst, pillClass: PILL_WARNING_CLASS });
  if (option.hasActiveFlowVersion === false) pills.push({ key: "version", label: LABELS.noActiveVersion, pillClass: PILL_DANGER_CLASS });
  if (!option.isActive) pills.push({ key: "inactive", label: LABELS.inactive, pillClass: PILL_DANGER_CLASS });

  return { key: option.actionId, name: option.name, detail, extra, pills };
}

// Builds the rows of what the agent has, in the order the admin added it, keeping those that match the search.
export function buildItemViews(kind, options, ids, searchText) {

  // [1] Find the option of each id, and skip an id whose record no longer exists
  const optionList = options || [];
  const idList = ids || [];
  const isDataSource = kind === KIND_DATA_SOURCE;
  const searchWords = (searchText || NO_TEXT).trim().toLowerCase();
  const itemViews = [];

  idList.forEach((id) => {
    const option = optionList.find((candidate) => (isDataSource ? candidate.dataSourceId : candidate.actionId) === id);
    if (!option) return;

    // [2] Keep it when the search is blank or matches the name or API name
    const searchable = (option.name + " " + (option.developerName || NO_TEXT)).toLowerCase();
    if (searchWords && !searchable.includes(searchWords)) return;
    itemViews.push(isDataSource ? buildDataSourceView(option) : buildActionView(option));
  });

  return itemViews;
}

// Finds the label of an object, and falls back to its API name.
export function getObjectLabel(apiName, objectOptions) {

  // [1] Look in the list the tab passed
  const found = (objectOptions || []).find((option) => option.apiName === apiName);

  return found ? found.label : apiName;
}

// Builds the summary rows of the actions the agent has.
export function buildSummaryRows(options, ids, objectOptions) {

  // [1] Pick out the actions that are added
  const added = (ids || []).map((id) => (options || []).find((option) => option.actionId === id)).filter((option) => Boolean(option));
  const writeActions = added.filter((option) => option.isWrite);
  const readActions = added.filter((option) => !option.isWrite);
  const askedCount = writeActions.filter((option) => isAskedFirst(option)).length;

  // [2] Say how many write actions ask the user first
  const askText = askedCount === writeActions.length ? LABELS.allAskFirst : ", " + askedCount + LABELS.someAskFirst;
  const writeText = writeActions.length + (writeActions.length > 0 ? askText : NO_TEXT);

  // [3] List the records the write actions change, each once
  const objectNames = [];
  writeActions.forEach((option) => {
    const objectName = option.targetObject ? getObjectLabel(option.targetObject, objectOptions) : NO_TEXT;
    if (objectName && !objectNames.includes(objectName)) objectNames.push(objectName);
  });

  const summaryRows = [{ key: "read", label: LABELS.readOnlyActions, value: String(readActions.length) }, { key: "write", label: LABELS.writeActions, value: writeText }];
  if (objectNames.length > 0) summaryRows.push({ key: "records", label: LABELS.recordsItCanChange, value: objectNames.join(LIST_SEPARATOR) });

  return summaryRows;
}

// Builds the findings of the step, each with the button that fixes it.
export function buildFindingViews(findings) {

  // [1] One view for each finding
  const findingViews = [];
  const findingList = findings || [];

  findingList.forEach((finding, index) => {
    const isBlocker = finding.severity === SEVERITY_BLOCKER;
    const hasItem = Boolean(finding.itemId);
    const isSettings = finding.code === CODE_WORKFLOW_ACTIONS_DISABLED;
    findingViews.push({ key: index, title: finding.title, message: finding.message, severityLabel: isBlocker ? LABELS.blocker : LABELS.warning, severityClass: isBlocker ? PILL_DANGER_CLASS : PILL_WARNING_CLASS, itemId: finding.itemId, showRemove: hasItem, showSettings: !hasItem && isSettings });
  });

  return findingViews;
}

// Writes how many findings the step has.
export function formatFindingCount(count) {

  // [1] One or many
  if (count === 1) return LABELS.needLookOne;

  return count + LABELS.needLookMany;
}
