/*
Component Name: aiAgentWizardStepSkills

=================================================================
=================================================================

Description: The extended methods of the Skills step of the AI Agent Wizard: build the rows of the skills given and not given, and the findings.

Step 1: Build the line of detail and the pills of a skill
Step 2: Build the rows of the skills given to the agent and of the others that match the search
Step 3: Build the findings of the step and say how many there are

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { OUTPUT_RECORD_CHANGE, OUTPUT_REPORT, TEST_STATUS_FAILED, TEST_STATUS_NOT_PICKED, SEVERITY_BLOCKER, PILL_CLASS, PILL_WARNING_CLASS, PILL_DANGER_CLASS, DETAIL_SEPARATOR, NO_TEXT, LABELS } from "./aiAgentWizardStepSkillsSettings";

// Writes the line of detail of a skill: its tools, the page it runs on and how many agents have it.
export function buildDetail(option, objectOptions) {

  // [1] The tools of each kind, the page and the agents
  const objectOption = (objectOptions || []).find((candidate) => candidate.apiName === option.boundObject);
  const pageText = option.boundObject ? LABELS.needsPrefix + (objectOption ? objectOption.label : option.boundObject) : LABELS.anyPage;
  const detail = option.dataSourceCount + LABELS.dataSuffix + DETAIL_SEPARATOR + option.actionCount + LABELS.actionsSuffix + DETAIL_SEPARATOR + pageText + DETAIL_SEPARATOR + option.agentCount + LABELS.agentsSuffix;

  return detail;
}

// Builds the pills of a skill: switched off, what it produces, and how its last test went.
export function buildPills(option) {

  // [1] Add each pill that applies
  const pills = [];

  if (!option.isActive) pills.push({ key: "inactive", label: LABELS.inactive, pillClass: PILL_DANGER_CLASS });
  if (option.outputType === OUTPUT_RECORD_CHANGE) pills.push({ key: "output", label: LABELS.outputRecordChange, pillClass: PILL_CLASS });
  if (option.outputType === OUTPUT_REPORT) pills.push({ key: "output", label: LABELS.outputReport, pillClass: PILL_CLASS });
  if (option.lastTestStatus === TEST_STATUS_FAILED) pills.push({ key: "test", label: LABELS.testFailed, pillClass: PILL_DANGER_CLASS });
  if (option.lastTestStatus === TEST_STATUS_NOT_PICKED) pills.push({ key: "test", label: LABELS.notPicked, pillClass: PILL_WARNING_CLASS });
  if (!option.lastTestStatus) pills.push({ key: "test", label: LABELS.neverTested, pillClass: PILL_WARNING_CLASS });

  return pills;
}

// Builds the rows of the skills, given or not, that match the search.
export function buildSkillViews(options, ids, objectOptions, searchText, isGiven) {

  // [1] Keep the skills on the right side that match the search
  const searchValue = (searchText || NO_TEXT).trim().toLowerCase();
  const givenIds = ids || [];
  const matchingOptions = (options || []).filter((option) => {

    const isOnSide = givenIds.includes(option.skillId) === isGiven;
    const searchableText = (option.name + " " + option.developerName + " " + (option.description || NO_TEXT)).toLowerCase();

    return isOnSide && (!searchValue || searchableText.includes(searchValue));
  });

  // [2] Build one row for each
  const skillViews = matchingOptions.map((option) => ({ key: option.skillId, name: option.name, description: option.description, detail: buildDetail(option, objectOptions), pills: buildPills(option) }));

  return skillViews;
}

// Builds one view for each finding of the step.
export function buildFindingViews(findings) {

  // [1] One view for each finding
  const findingViews = (findings || []).map((finding, index) => {

    const isBlocker = finding.severity === SEVERITY_BLOCKER;

    return { key: index, title: finding.title, message: finding.message, severityLabel: isBlocker ? LABELS.blocker : LABELS.warning, severityClass: isBlocker ? PILL_DANGER_CLASS : PILL_WARNING_CLASS, itemId: finding.itemId, showRemove: Boolean(finding.itemId) };
  });

  return findingViews;
}

// Writes how many findings the step has.
export function formatFindingCount(count) {

  // [1] One or many
  if (count === 1) return LABELS.needLookOne;

  return count + LABELS.needLookMany;
}
