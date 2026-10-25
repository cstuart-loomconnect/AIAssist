/*
Component Name: aiToolsSkStepTools

=================================================================
=================================================================

Description: The extended methods of step 2 of the skill wizard: build the list to pick from, the tools in the skill, and what is wrong with them.

Step 1: Build the filter buttons and the options that match the filter and the search
Step 2: Build one row for each tool in the skill, with its tags
Step 3: Add, move and remove tools, keeping the order
Step 4: Find the objects of the bound data sources, because a skill runs against one open record

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { TOOL_KIND_DATA_SOURCE, FILTER_ALL, FILTER_DATA_SOURCES, FILTER_ACTIONS, BINDING_BOUND, EXECUTION_WRITE, FILTER_CLASS, FILTER_SELECTED_CLASS, KIND_DATA_SOURCE_CLASS, KIND_ACTION_CLASS, TAG_CLASS, TAG_WARNING_CLASS, NO_TEXT, LABELS } from "./aiToolsSkStepToolsSettings";

// True when the option belongs under the filter.
export function matchesFilter(option, filterKey) {

  // [1] Each filter keeps one kind
  if (filterKey === FILTER_DATA_SOURCES) return option.kind === TOOL_KIND_DATA_SOURCE;
  if (filterKey === FILTER_ACTIONS) return option.kind !== TOOL_KIND_DATA_SOURCE;

  return true;
}

// Builds the three filter buttons, each with how many options it holds.
export function buildFilterViews(options, selectedKey) {

  // [1] Name the filters in the order they are shown
  const filterDefinitions = [ { key: FILTER_ALL, label: LABELS.filterAll }, { key: FILTER_DATA_SOURCES, label: LABELS.filterDataSources }, { key: FILTER_ACTIONS, label: LABELS.filterActions } ];

  // [2] Count what each one holds
  const filterViews = filterDefinitions.map((definition) => {

    const matchingCount = options.filter((option) => matchesFilter(option, definition.key)).length;
    const buttonClass = definition.key === selectedKey ? FILTER_SELECTED_CLASS : FILTER_CLASS;

    return { key: definition.key, label: definition.label + " (" + matchingCount + ")", buttonClass };
  });

  return filterViews;
}

// Builds the tags of a tool or option: switched off, changes data, and the record it needs.
export function buildTags(tool) {

  // [1] Add each tag that applies
  const tags = [];
  const isBoundSource = tool.kind === TOOL_KIND_DATA_SOURCE && tool.bindingType === BINDING_BOUND && Boolean(tool.targetObject);

  if (tool.isActive === false) tags.push({ key: "inactive", label: LABELS.tagInactive, tagClass: TAG_WARNING_CLASS });
  if (tool.executionType === EXECUTION_WRITE) tags.push({ key: "write", label: LABELS.tagWrite, tagClass: TAG_CLASS });
  if (isBoundSource) tags.push({ key: "record", label: LABELS.tagRecordPrefix + tool.targetObject, tagClass: TAG_CLASS });

  return tags;
}

// Builds the options that match the filter and the search, saying which are already in the skill.
export function buildOptionViews(options, tools, filterKey, searchText) {

  // [1] Note what is already in the skill
  const addedIds = (tools || []).map((tool) => tool.recordId);
  const searchValue = (searchText || NO_TEXT).trim().toLowerCase();

  // [2] Keep the options that match
  const matchingOptions = options.filter((option) => {

    const searchableText = (option.name + " " + option.developerName + " " + (option.description || NO_TEXT) + " " + (option.targetObject || NO_TEXT)).toLowerCase();
    const isFound = !searchValue || searchableText.includes(searchValue);

    return matchesFilter(option, filterKey) && isFound;
  });

  // [3] Build one view for each
  const optionViews = matchingOptions.map((option) => {

    const isAdded = addedIds.includes(option.recordId);
    const isDataSource = option.kind === TOOL_KIND_DATA_SOURCE;

    return { key: option.recordId, name: option.name, developerName: option.developerName, description: option.description, kindLabel: isDataSource ? LABELS.kindDataSource : LABELS.kindAction, kindClass: isDataSource ? KIND_DATA_SOURCE_CLASS : KIND_ACTION_CLASS, tags: buildTags(option), isAdded, buttonLabel: isAdded ? LABELS.added : LABELS.add };
  });

  return optionViews;
}

// Builds one row for each tool in the skill, in order, with whether it can move up or down.
export function buildToolViews(tools) {

  // [1] Build one row for each
  const lastIndex = (tools || []).length - 1;
  const toolViews = (tools || []).map((tool, toolIndex) => {

    const isDataSource = tool.kind === TOOL_KIND_DATA_SOURCE;

    return { key: tool.recordId, orderLabel: String(toolIndex + 1), index: toolIndex, name: tool.name, developerName: "@" + tool.developerName, kindLabel: isDataSource ? LABELS.kindDataSource : LABELS.kindAction, kindClass: isDataSource ? KIND_DATA_SOURCE_CLASS : KIND_ACTION_CLASS, tags: buildTags(tool), isRequired: tool.isRequired !== false, isFirst: toolIndex === 0, isLast: toolIndex === lastIndex };
  });

  return toolViews;
}

// Adds the option to the end of the skill as a required tool. The skill is returned unchanged when the option is already in it.
export function addTool(tools, option) {

  // [1] Keep a tool once
  const currentTools = tools || [];
  const isAlreadyAdded = currentTools.some((tool) => tool.recordId === option.recordId);
  if (isAlreadyAdded) return currentTools;

  // [2] Add it at the end
  const addedTools = [ ...currentTools, { ...option, isRequired: true } ];

  return addedTools;
}

// Moves the tool at the index one place up (-1) or down (1).
export function moveTool(tools, toolIndex, direction) {

  // [1] Stop at either end
  const targetIndex = toolIndex + direction;
  if (targetIndex < 0 || targetIndex >= tools.length) return tools;

  // [2] Swap the two tools
  const movedTools = [ ...tools ];
  const movingTool = movedTools[toolIndex];
  movedTools[toolIndex] = movedTools[targetIndex];
  movedTools[targetIndex] = movingTool;

  return movedTools;
}

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
