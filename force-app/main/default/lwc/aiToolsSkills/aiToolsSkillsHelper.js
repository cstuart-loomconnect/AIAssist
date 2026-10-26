/*
Component Name: aiToolsSkills

=================================================================
=================================================================

Description: The extended methods of the Skills panel: filter the list, build its rows and write an error message.

Step 1: Work out which skills each filter holds, and build the filter buttons with their counts
Step 2: Build one row for each skill that matches the filter and the search
Step 3: Turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { FILTER_ALL, FILTER_ACTIVE, FILTER_BOUND, FILTER_ATTENTION, OUTPUT_RECORD_CHANGE, OUTPUT_REPORT, TEST_STATUS_PASSED, TEST_STATUS_FAILED, TEST_STATUS_NOT_PICKED, FILTER_CLASS, FILTER_SELECTED_CLASS, PILL_PASSED_CLASS, PILL_FAILED_CLASS, PILL_WARNING_CLASS, PILL_NEVER_CLASS, PILL_ACTIVE_CLASS, PILL_INACTIVE_CLASS, DATE_LOCALE, DATE_OPTIONS, NO_TEXT, LABELS } from "./aiToolsSkillsSettings";

// True when the skill needs a look: Apex flagged it, or its last test did not pass.
export function isNeedsAttention(skill) {

  // [1] A flag from Apex, or a test that failed or was not picked
  const hasFlag = Boolean(skill.attention);
  const hasBadTest = skill.lastTestStatus === TEST_STATUS_FAILED || skill.lastTestStatus === TEST_STATUS_NOT_PICKED;

  return hasFlag || hasBadTest;
}

// True when the skill belongs under the filter.
export function matchesFilter(skill, filterKey) {

  // [1] Each filter looks at one thing
  if (filterKey === FILTER_ACTIVE) return skill.isActive === true;
  if (filterKey === FILTER_BOUND) return Boolean(skill.boundObject);
  if (filterKey === FILTER_ATTENTION) return isNeedsAttention(skill);

  return true;
}

// Builds the four filter buttons, each with how many skills it holds.
export function buildFilterViews(skills, selectedKey) {

  // [1] Name the filters in the order they are shown
  const filterDefinitions = [ { key: FILTER_ALL, label: LABELS.filterAll }, { key: FILTER_ACTIVE, label: LABELS.filterActive }, { key: FILTER_BOUND, label: LABELS.filterBound }, { key: FILTER_ATTENTION, label: LABELS.filterAttention } ];

  // [2] Count what each one holds
  const filterViews = filterDefinitions.map((definition) => {

    const matchingSkills = skills.filter((skill) => matchesFilter(skill, definition.key));
    const label = definition.label + " (" + matchingSkills.length + ")";
    const buttonClass = definition.key === selectedKey ? FILTER_SELECTED_CLASS : FILTER_CLASS;

    return { key: definition.key, label, buttonClass };
  });

  return filterViews;
}

// Writes what the skill produces, such as "Record change".
export function getOutputLabel(outputType) {

  // [1] One label for each output
  if (outputType === OUTPUT_RECORD_CHANGE) return LABELS.outputRecordChange;
  if (outputType === OUTPUT_REPORT) return LABELS.outputReport;

  return LABELS.outputChat;
}

// Writes the tools of the skill, such as "2 data · 1 actions".
export function getToolsLabel(skill) {

  // [1] Each kind with its count
  const toolsLabel = skill.dataSourceCount + LABELS.dataSourcesSuffix + LABELS.toolsSeparator + skill.actionCount + LABELS.actionsSuffix;

  return toolsLabel;
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
export function buildTestedView(skill) {

  // [1] A flag from Apex comes first, because it says the skill cannot work as it is
  if (skill.attention) return { label: skill.attention, pillClass: PILL_FAILED_CLASS, dateLabel: NO_TEXT };

  // [2] A test result with its date
  const dateLabel = formatShortDate(skill.lastTestedOn);
  if (skill.lastTestStatus === TEST_STATUS_PASSED) return { label: LABELS.passed, pillClass: PILL_PASSED_CLASS, dateLabel };
  if (skill.lastTestStatus === TEST_STATUS_FAILED) return { label: LABELS.failed, pillClass: PILL_FAILED_CLASS, dateLabel };
  if (skill.lastTestStatus === TEST_STATUS_NOT_PICKED) return { label: LABELS.notPicked, pillClass: PILL_WARNING_CLASS, dateLabel };

  // [3] Never tested
  return { label: LABELS.never, pillClass: PILL_NEVER_CLASS, dateLabel: NO_TEXT };
}

// Builds the rows of the table for the filter and the search text.
export function buildRowViews(skills, filterKey, searchText) {

  // [1] Keep what matches the filter and the text
  const searchValue = (searchText || NO_TEXT).trim().toLowerCase();
  const matchingSkills = skills.filter((skill) => {

    const isInFilter = matchesFilter(skill, filterKey);
    const searchableText = (skill.skillName + " " + skill.developerName + " " + (skill.description || NO_TEXT) + " " + (skill.boundObject || NO_TEXT)).toLowerCase();
    const isFound = !searchValue || searchableText.includes(searchValue);

    return isInFilter && isFound;
  });

  // [2] Build one row for each
  const rowViews = matchingSkills.map((skill) => {

    const testedView = buildTestedView(skill);
    const isActive = skill.isActive === true;

    return { key: skill.skillId, skillName: skill.skillName, description: skill.description, toolsLabel: getToolsLabel(skill), outputLabel: getOutputLabel(skill.outputType), recordLabel: skill.boundObject || LABELS.anyRecord, agentCount: skill.agentCount, testedLabel: testedView.label, testedClass: testedView.pillClass, testedDate: testedView.dateLabel, statusLabel: isActive ? LABELS.active : LABELS.inactive, statusClass: isActive ? PILL_ACTIVE_CLASS : PILL_INACTIVE_CLASS };
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
