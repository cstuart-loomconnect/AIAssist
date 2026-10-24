/*
Component Name: aiToolsWorkflowActions

=================================================================
=================================================================

Description: The extended methods of the Workflow Actions panel: filter the list, build its rows and write an error message.

Step 1: Work out which actions each filter holds, and build the filter buttons with their counts
Step 2: Build one row for each action that matches the filter and the search
Step 3: Turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { FILTER_ALL, FILTER_WRITE, FILTER_READ_ONLY, FILTER_ATTENTION, ACTION_TYPE_APEX, ACTION_TYPE_FLOW, ACTION_TYPE_SCREEN_FLOW, EXECUTION_WRITE, TEST_STATUS_PASSED, TEST_STATUS_FAILED, FILTER_CLASS, FILTER_SELECTED_CLASS, PILL_PASSED_CLASS, PILL_FAILED_CLASS, PILL_ATTENTION_CLASS, PILL_NEVER_CLASS, PILL_ACTIVE_CLASS, PILL_INACTIVE_CLASS, DATE_LOCALE, DATE_OPTIONS, NO_TEXT, LABELS } from "./aiToolsWorkflowActionsSettings";

// True when the action needs a look: its flow is inactive or has changed, or its last test failed.
export function isNeedsAttention(action) {

  // [1] A flag from the flow, or a failed test
  const hasFlowFlag = Boolean(action.attention);
  const hasFailedTest = action.lastTestStatus === TEST_STATUS_FAILED;

  return hasFlowFlag || hasFailedTest;
}

// True when the action belongs under the filter.
export function matchesFilter(action, filterKey) {

  // [1] Each filter looks at one thing
  const isWrite = action.executionType === EXECUTION_WRITE;
  if (filterKey === FILTER_WRITE) return isWrite;
  if (filterKey === FILTER_READ_ONLY) return !isWrite;
  if (filterKey === FILTER_ATTENTION) return isNeedsAttention(action);

  return true;
}

// Builds the four filter buttons, each with how many actions it holds.
export function buildFilterViews(actions, selectedKey) {

  // [1] Name the filters in the order they are shown
  const filterDefinitions = [ { key: FILTER_ALL, label: LABELS.filterAll }, { key: FILTER_WRITE, label: LABELS.filterWrite }, { key: FILTER_READ_ONLY, label: LABELS.filterReadOnly }, { key: FILTER_ATTENTION, label: LABELS.filterAttention } ];

  // [2] Count what each one holds
  const filterViews = filterDefinitions.map((definition) => {

    const matchingActions = actions.filter((action) => matchesFilter(action, definition.key));
    const label = definition.label + " (" + matchingActions.length + ")";
    const buttonClass = definition.key === selectedKey ? FILTER_SELECTED_CLASS : FILTER_CLASS;

    return { key: definition.key, label, buttonClass };
  });

  return filterViews;
}

// Writes what the action runs, such as "Autolaunched flow".
export function getRunsLabel(actionType) {

  // [1] One label for each type
  if (actionType === ACTION_TYPE_APEX) return LABELS.runsApex;
  if (actionType === ACTION_TYPE_FLOW) return LABELS.runsFlow;
  if (actionType === ACTION_TYPE_SCREEN_FLOW) return LABELS.runsScreenFlow;

  return actionType;
}

// Writes how the action changes data, such as "Write · asks first".
export function getChangesLabel(action) {

  // [1] A read only action changes nothing
  if (action.executionType !== EXECUTION_WRITE) return LABELS.readOnly;

  // [2] A screen flow is finished by the user, any other write asks first
  const isScreenFlow = action.actionType === ACTION_TYPE_SCREEN_FLOW;

  return isScreenFlow ? LABELS.writeUserFinishes : LABELS.writeAsksFirst;
}

// Writes a date as day and month, such as 15/10.
export function formatShortDate(dateValue) {

  // [1] Nothing to show when there is no date
  if (!dateValue) return NO_TEXT;

  // [2] Turn it into text
  const parsedDate = new Date(dateValue);
  const shortDate = parsedDate.toLocaleDateString(DATE_LOCALE, DATE_OPTIONS);

  return shortDate;
}

// Works out the last tested pill and the date beside it.
export function buildTestedView(action) {

  // [1] A flag from the flow comes first, because it says the test no longer counts
  if (action.attention) return { label: action.attention, pillClass: PILL_ATTENTION_CLASS, dateLabel: NO_TEXT };

  // [2] A test result with its date
  const dateLabel = formatShortDate(action.lastTestedOn);
  if (action.lastTestStatus === TEST_STATUS_PASSED) return { label: LABELS.passed, pillClass: PILL_PASSED_CLASS, dateLabel };
  if (action.lastTestStatus === TEST_STATUS_FAILED) return { label: LABELS.failed, pillClass: PILL_FAILED_CLASS, dateLabel };

  // [3] Never tested
  return { label: LABELS.never, pillClass: PILL_NEVER_CLASS, dateLabel: NO_TEXT };
}

// Builds the rows of the table for the filter and the search text.
export function buildRowViews(actions, filterKey, searchText) {

  // [1] Keep what matches the filter and the text
  const searchValue = (searchText || NO_TEXT).trim().toLowerCase();
  const matchingActions = actions.filter((action) => {

    const isInFilter = matchesFilter(action, filterKey);
    const searchableText = (action.actionName + " " + (action.targetObject || NO_TEXT) + " " + action.developerName).toLowerCase();
    const isFound = !searchValue || searchableText.includes(searchValue);

    return isInFilter && isFound;
  });

  // [2] Build one row for each
  const rowViews = matchingActions.map((action) => {

    const testedView = buildTestedView(action);
    const isActive = action.isActive === true;

    return { key: action.actionId, actionName: action.actionName, runsLabel: getRunsLabel(action.actionType), changesLabel: getChangesLabel(action), targetLabel: action.targetObject || LABELS.noTarget, agentCount: action.agentCount, testedLabel: testedView.label, testedClass: testedView.pillClass, testedDate: testedView.dateLabel, statusLabel: isActive ? LABELS.active : LABELS.inactive, statusClass: isActive ? PILL_ACTIVE_CLASS : PILL_INACTIVE_CLASS };
  });

  return rowViews;
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
