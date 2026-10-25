/*
Component Name: aiAgentWizardList

=================================================================
=================================================================

Description: The extended methods of the agent list: sort, build the rows the table shows, count and filter them.

Step 1: Put the active agents first and then sort by name
Step 2: Turn each agent into the values the table needs, with its status, hint line and menu
Step 3: Count the segments, and keep the rows that match the segment and the search

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { SEGMENT_ALL, SEGMENT_ACTIVE, SEGMENT_DRAFT, SEVERITY_BLOCKER, SEVERITY_WARNING, PILL_ACTIVE_CLASS, PILL_DRAFT_CLASS, HINT_BLOCKER_CLASS, HINT_WARNING_CLASS, SEGMENT_SELECTED_CLASS, SEGMENT_CLASS, DATE_LOCALE, LIST_SEPARATOR, NO_TEXT, LABELS } from "./aiAgentWizardListSettings";

// Puts the active agents first, then sorts by name.
export function sortRows(rows) {

  // [1] Copy the list so the original is not changed
  const sortedRows = [...(rows || [])];

  // [2] Active before draft, then A to Z
  sortedRows.sort((first, second) => {
    if (first.isActive !== second.isActive) return first.isActive ? -1 : 1;

    return first.name.localeCompare(second.name);
  });

  return sortedRows;
}

// Writes the date of the last change in the local style.
export function formatLastChanged(value) {

  // [1] An agent with no date shows nothing
  if (!value) return NO_TEXT;

  // [2] Write it in the local style
  const formatted = new Date(value).toLocaleDateString(DATE_LOCALE);

  return formatted;
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

  return LABELS.fallbackError;
}

// Turns the worst finding of an agent into the hint line under its row.
export function buildHint(row) {

  // [1] A blocker says what stops the agent being switched on, in lower case so it reads as one sentence
  const hasBlocker = row.topFindingSeverity === SEVERITY_BLOCKER;
  const blockerStart = row.isActive ? LABELS.hintBlockerActive : LABELS.hintBlockerDraft;
  const title = row.topFindingTitle || NO_TEXT;
  const lowerTitle = title.charAt(0).toLowerCase() + title.slice(1);
  if (hasBlocker) return { hintText: blockerStart + lowerTitle, hintClass: HINT_BLOCKER_CLASS };

  // [2] Warnings are counted
  const hasWarning = row.topFindingSeverity === SEVERITY_WARNING;
  const warningText = row.warningCount === 1 ? LABELS.hintWarningOne : row.warningCount + LABELS.hintWarningMiddle;
  if (hasWarning) return { hintText: warningText, hintClass: HINT_WARNING_CLASS };

  return { hintText: NO_TEXT, hintClass: NO_TEXT };
}

// Builds the values the table needs for each agent.
export function buildRowViews(rows) {

  // [1] Sort the agents, then build one view for each
  const rowViews = [];
  const sortedRows = sortRows(rows);

  sortedRows.forEach((row) => {
    const hint = buildHint(row);
    const pagesText = row.objectLabels && row.objectLabels.length > 0 ? row.objectLabels.join(LIST_SEPARATOR) : LABELS.noPages;
    const modelText = row.modelName || LABELS.noModel;
    const usersText = row.isAllUsers ? LABELS.allUsers : String(row.userCount || 0);
    const statusLabel = row.isActive ? LABELS.active : LABELS.draft;
    const pillClass = row.isActive ? PILL_ACTIVE_CLASS : PILL_DRAFT_CLASS;
    const lastChangedText = formatLastChanged(row.lastModifiedDate);
    const hasHint = Boolean(hint.hintText);
    const searchText = (row.name + " " + pagesText + " " + modelText).toLowerCase();
    rowViews.push({ agentId: row.agentId, name: row.name, isActive: row.isActive, statusLabel, pillClass, pagesText, modelText, usersText, lastChangedText, hasHint, hintText: hint.hintText, hintClass: hint.hintClass, searchText });
  });

  return rowViews;
}

// Counts the agents of each segment.
export function countSegments(rows) {

  // [1] Count the active agents, and the rest are drafts
  const rowList = rows || [];
  const activeCount = rowList.filter((row) => row.isActive).length;
  const counts = { all: rowList.length, active: activeCount, draft: rowList.length - activeCount };

  return counts;
}

// Builds the three segment buttons with their counts.
export function buildSegmentViews(counts, selectedSegment) {

  // [1] One button for each segment, the chosen one highlighted
  const segments = [{ value: SEGMENT_ALL, label: LABELS.all, count: counts.all }, { value: SEGMENT_ACTIVE, label: LABELS.active, count: counts.active }, { value: SEGMENT_DRAFT, label: LABELS.draft, count: counts.draft }];
  const segmentViews = segments.map((segment) => {
    const isSelected = segment.value === selectedSegment;
    const buttonClass = isSelected ? SEGMENT_SELECTED_CLASS : SEGMENT_CLASS;

    return { value: segment.value, label: segment.label + " (" + segment.count + ")", buttonClass, isSelected };
  });

  return segmentViews;
}

// Keeps the rows that are in the segment and match the search text.
export function filterRowViews(rowViews, segment, searchTerm) {

  // [1] Keep the agents of the segment
  const lowerTerm = (searchTerm || NO_TEXT).trim().toLowerCase();
  const filteredViews = rowViews.filter((rowView) => {
    const isInSegment = segment === SEGMENT_ALL || (segment === SEGMENT_ACTIVE && rowView.isActive) || (segment === SEGMENT_DRAFT && !rowView.isActive);
    const isMatch = !lowerTerm || rowView.searchText.includes(lowerTerm);

    return isInSegment && isMatch;
  });

  return filteredViews;
}
