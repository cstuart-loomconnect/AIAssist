/*
Component Name: aiToolsDataSources

=================================================================
=================================================================

Description: The extended methods of the Data Sources tab: build the filter buttons and the list rows, and write dates and errors.

Step 1: Count the data sources for each filter and build the filter buttons
Step 2: Keep the data sources that match the filter and the search, and build one row for each
Step 3: Write the last test date and turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { FILTER_ALL, FILTER_SOQL, FILTER_APEX, FILTER_INACTIVE, SOURCE_TYPE_SOQL, SOURCE_TYPE_APEX, TEST_STATUS_PASSED, TEST_STATUS_PARTIAL, TEST_STATUS_FAILED, NO_VALUE, DATE_LOCALE, DATE_OPTIONS, FILTER_BUTTON_CLASS, FILTER_BUTTON_SELECTED_CLASS, PILL_PASSED_CLASS, PILL_PARTIAL_CLASS, PILL_FAILED_CLASS, PILL_NEVER_CLASS, PILL_ACTIVE_CLASS, PILL_INACTIVE_CLASS, LABELS } from "./aiToolsDataSourcesSettings";

// Says whether a data source belongs under a filter.
export function isInFilter(row, filterKey) {

  // [1] Each filter looks at one thing about the data source
  if (filterKey === FILTER_SOQL) return row.sourceType === SOURCE_TYPE_SOQL;
  if (filterKey === FILTER_APEX) return row.sourceType === SOURCE_TYPE_APEX;
  if (filterKey === FILTER_INACTIVE) return row.isActive !== true;

  return true;
}

// Builds the filter buttons, each with the number of data sources under it.
export function buildFilterButtons(rows, selectedFilter) {

  // [1] Name each filter
  const filters = [
    { key: FILTER_ALL, label: LABELS.filterAll },
    { key: FILTER_SOQL, label: LABELS.filterSoql },
    { key: FILTER_APEX, label: LABELS.filterApex },
    { key: FILTER_INACTIVE, label: LABELS.filterInactive }
  ];

  // [2] Count the data sources under each one and pick its class
  const buttons = filters.map((filter) => {

    const count = rows.filter((row) => isInFilter(row, filter.key)).length;
    const isSelected = filter.key === selectedFilter;
    const buttonClass = isSelected ? FILTER_BUTTON_SELECTED_CLASS : FILTER_BUTTON_CLASS;

    return { key: filter.key, label: filter.label + " (" + count + ")", buttonClass };
  });

  return buttons;
}

// Writes the day and month a data source was last tested, such as 12/10.
export function formatTestedDate(testedOn) {

  // [1] Nothing to write when it was never tested
  if (!testedOn) return NO_VALUE;

  // [2] Write it in the tab's date style
  const testedDate = new Date(testedOn);
  const dateText = testedDate.toLocaleDateString(DATE_LOCALE, DATE_OPTIONS);

  return dateText;
}

// Builds one row of the list.
export function buildRowView(row) {

  // [1] The last test: a pill and, when there was one, its date
  const hasTest = Boolean(row.lastTestStatus);
  let testLabel = LABELS.never;
  let testClass = PILL_NEVER_CLASS;

  if (row.lastTestStatus === TEST_STATUS_PASSED) {

    testLabel = LABELS.passed;
    testClass = PILL_PASSED_CLASS;

  } else if (row.lastTestStatus === TEST_STATUS_PARTIAL) {

    testLabel = LABELS.partial;
    testClass = PILL_PARTIAL_CLASS;

  } else if (row.lastTestStatus === TEST_STATUS_FAILED) {

    testLabel = LABELS.failed;
    testClass = PILL_FAILED_CLASS;
  }

  // [2] The values the template shows
  const testedDate = hasTest ? formatTestedDate(row.lastTestedOn) : "";
  const maxRowsLabel = row.maxRows === null || row.maxRows === undefined ? NO_VALUE : String(row.maxRows);
  const isActive = row.isActive === true;
  const statusLabel = isActive ? LABELS.active : LABELS.inactive;
  const statusClass = isActive ? PILL_ACTIVE_CLASS : PILL_INACTIVE_CLASS;
  const objectLabel = row.targetObject || NO_VALUE;

  return { key: row.dataSourceId, sourceName: row.sourceName, sourceType: row.sourceType, objectLabel, bindingType: row.bindingType, maxRowsLabel, agentCount: row.agentCount, testLabel, testClass, testedDate, statusLabel, statusClass };
}

// Keeps the data sources under the filter whose name or object holds the search text, and builds a row for each.
export function buildRowViews(rows, selectedFilter, searchText) {

  // [1] Lower case the search so capital letters do not matter
  const search = (searchText || "").trim().toLowerCase();

  // [2] Keep the rows under the filter that match the search
  const matchingRows = rows.filter((row) => {

    if (!isInFilter(row, selectedFilter)) return false;
    if (!search) return true;

    const name = (row.sourceName || "").toLowerCase();
    const targetObject = (row.targetObject || "").toLowerCase();

    return name.includes(search) || targetObject.includes(search);
  });

  // [3] Build one view for each
  const rowViews = matchingRows.map((row) => buildRowView(row));

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
