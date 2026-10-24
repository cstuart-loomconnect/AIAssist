/*
Component Name: aiToolsDsInputs

=================================================================
=================================================================

Description: The settings of the Inputs step: input types, who fills an input, class names and label text.

Step 1: Name the source types and the two ways an input is filled
Step 2: List the input types the admin can choose
Step 3: Hold the label text and the class names of the pills

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The source types. Mirror AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL and DATA_SOURCE_TYPE_APEX.
export const SOURCE_TYPE_APEX = "Apex";

// Who fills an input. The page value is the x-source value the Apex binder drops from what the model sends.
export const INPUT_SOURCE_PAGE = "page";
export const INPUT_SOURCE_AGENT = "agent";
export const INPUT_SOURCE_KEY = "x-source";

// The type of the input the open record fills.
export const INPUT_TYPE_ID = "Id";
export const INPUT_TYPE_STRING = "String";

// The name of a new input the admin adds to an Apex data source.
export const NEW_INPUT_NAME = "newInput";

// How each input type is written in the input schema.
export const INPUT_TYPE_SCHEMAS = [
  { type: "String", schemaType: "string", format: "" },
  { type: "Date", schemaType: "string", format: "date" },
  { type: "DateTime", schemaType: "string", format: "date-time" },
  { type: "Number", schemaType: "number", format: "" },
  { type: "Integer", schemaType: "integer", format: "" },
  { type: "Boolean", schemaType: "boolean", format: "" }
];

// The types the admin can choose for an input the agent fills.
export const TYPE_OPTIONS = INPUT_TYPE_SCHEMAS.map((item) => ({ label: item.type, value: item.type }));

// The text of a value that is empty.
export const NO_TEXT = "";

// The classes of the pill that says who fills an input.
export const PILL_PAGE_CLASS = "aiadi-pill aiadi-pill_page";
export const PILL_AGENT_CLASS = "aiadi-pill aiadi-pill_agent";

// Text shown to the user.
export const LABELS = {
  intro: "Built from the binds in the query. Tell the agent what each one means so it fills them in correctly.",
  introApex: "The inputs the class reads. Tell the agent what each one means so it fills them in correctly.",
  columnInput: "Input",
  columnFilledBy: "Filled by",
  columnType: "Type",
  columnRequired: "Required",
  columnDescription: "Description for the agent",
  filledByPage: "The page",
  filledByAgent: "The agent",
  pageDescription: "Set from the open record. The agent can't change it.",
  yes: "Yes",
  noInputs: "This data source has no inputs.",
  noInputsSoql: "The query has no binds yet, so it has no inputs. Add a filter that takes its value from the agent to create one.",
  addInput: "+ Add input",
  removeInput: "Remove input",
  inputName: "Input name",
  inputType: "Input type",
  inputRequired: "Required",
  inputDescription: "Description for the agent",
  schemaTitle: "Saved to InputSchema__c",
  schemaNote: "Read only · rebuilt from the table",
  noteSoql: "Anything the agent sends that isn't declared here is dropped before the query runs, the same way AIWorkflowActionDispatcher filters inputs.",
  noteApex: "Anything the agent sends that isn't declared here is dropped before the class runs, the same way AIWorkflowActionDispatcher filters inputs.",
  needsDescription: "Describe each input the agent fills in, so it knows what to send.",
  badName: "An input name must start with a letter and use only letters, numbers and underscores."
};
