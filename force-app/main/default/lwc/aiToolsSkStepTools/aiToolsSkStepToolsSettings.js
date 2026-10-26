/*
Component Name: aiToolsSkStepTools

=================================================================
=================================================================

Description: The settings of step 2 of the skill wizard: the kinds of tool, the filters, the limits, class names and the text shown to the admin.

Step 1: Name the two kinds of tool and the filters of the list to pick from
Step 2: Hold the values that mirror the data source and workflow action objects, and the most tools a skill holds
Step 3: Hold the class names and the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The two kinds of tool, as Apex names them.
export const TOOL_KIND_DATA_SOURCE = "dataSource";
export const TOOL_KIND_ACTION = "action";

// The filters of the list to pick from.
export const FILTER_ALL = "all";
export const FILTER_DATA_SOURCES = "dataSources";
export const FILTER_ACTIONS = "actions";

// Values that mirror AIDataSource__c.BindingType__c and AIWorkflowAction__c.ExecutionType__c.
export const BINDING_BOUND = "Bound";
export const EXECUTION_WRITE = "Write";

// The most tools a skill holds. It mirrors AIAssistApplicationConstants.SKILL_MAX_TOOLS.
export const MAX_TOOLS = 20;

// The text of a value that is empty.
export const NO_TEXT = "";

// The classes of a filter button, a kind badge and a tag.
export const FILTER_CLASS = "aitsk-filter";
export const FILTER_SELECTED_CLASS = "aitsk-filter aitsk-filter_selected";
export const KIND_DATA_SOURCE_CLASS = "aitsk-kind aitsk-kind_data";
export const KIND_ACTION_CLASS = "aitsk-kind aitsk-kind_action";
export const TAG_CLASS = "aitsk-tag";
export const TAG_WARNING_CLASS = "aitsk-tag aitsk-tag_warning";

// Text shown to the user.
export const LABELS = {
  pickTitle: "Existing tools",
  pickHelp: "A skill only uses data sources and workflow actions that already exist. Build new ones on their own tabs.",
  searchLabel: "Search tools",
  searchPlaceholder: "Search",
  filterAll: "All",
  filterDataSources: "Data sources",
  filterActions: "Workflow actions",
  add: "Add",
  added: "Added",
  noOptions: "No tools match.",
  skillTitle: "In this skill",
  skillHelp: "Put the tools in the order the instructions call them. The model can call any of them once it picks the skill.",
  noTools: "Add at least one tool.",
  kindDataSource: "Data",
  kindAction: "Action",
  moveUp: "Move up",
  moveDown: "Move down",
  remove: "Remove",
  required: "Required",
  requiredHelp: "Untick for a tool the skill can do without. A required tool that is switched off flags the skill.",
  tagInactive: "Switched off",
  tagWrite: "Changes data",
  tagRecordPrefix: "Needs a ",
  tagAnyRecord: "Any page",
  mixedObjects: "Bound data sources must all be on one object, because a skill runs against one open record. Remove the ones on ",
  mixedObjectsSuffix: ".",
  inactiveNote: "Switched off tools are left out when the skill runs, and the model cannot call them.",
  tooMany: "A skill holds up to 20 tools. Split it into two skills.",
  countSuffix: " of 20"
};
