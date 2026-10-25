/*
Component Name: aiToolsWaStepSource

=================================================================
=================================================================

Description: The settings of step 2 of the workflow action wizard: types, input sources, class names and label text.

Step 1: Name the values the step reads and reports
Step 2: Name the names that are filled automatically
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Values that mirror AIWorkflowAction__c: ActionType__c.
export const ACTION_TYPE_APEX = "Apex";
export const ACTION_TYPE_SCREEN_FLOW = "Screen Flow";

// The data types of an input, as the Apex controller names them.
export const DATA_TYPE_TEXT = "Text";
export const DATA_TYPE_NUMBER = "Number";
export const DATA_TYPE_BOOLEAN = "Boolean";
export const DATA_TYPE_DATE = "Date";
export const DATA_TYPE_DATE_TIME = "DateTime";

// Who fills an input.
export const SOURCE_PAGE = "page";
export const SOURCE_USER = "user";
export const SOURCE_AGENT = "agent";
export const SOURCE_LEFT = "left";
export const SOURCE_UNSUPPORTED = "unsupported";

// The keys read from a schema a class describes. Mirror AIAssistApplicationConstants.WORKFLOW_SCHEMA_*.
export const SCHEMA_SOURCE_KEY = "x-source";

// The JSON Schema words for each data type.
export const JSON_TYPE_NUMBER = "number";
export const JSON_TYPE_INTEGER = "integer";
export const JSON_TYPE_BOOLEAN = "boolean";
export const JSON_FORMAT_DATE = "date";
export const JSON_FORMAT_DATE_TIME = "date-time";

// The input names that fill themselves: the open record, and the person chatting.
export const PAGE_INPUT_NAME = "recordId";
export const USER_INPUT_PATTERN = /^(ownerId|userId|currentUserId)$/i;

// How a modified date is shown.
export const DATE_LOCALE = "en-GB";

// The classes of a list row, plain and chosen.
export const ROW_CLASS = "aitwa-row";
export const ROW_SELECTED_CLASS = "aitwa-row aitwa-row_selected";

// The text of a value that is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  introFlow: "Only active autolaunched flows are listed. Picking one reads its input and output variables.",
  introScreenFlow: "Only active screen flows are listed. Picking one reads its input variables.",
  introApex: "Only classes that implement IAIWorkflowActionExecutor are listed. A class that also implements IAIWorkflowActionInputDescriber fills in the next step for you.",
  columnFlow: "Flow",
  columnVersion: "Active version",
  columnInputs: "Inputs",
  columnModified: "Last modified",
  columnClass: "Class",
  columnDeclares: "Declares inputs",
  columnCallouts: "Callouts",
  noneDeclared: "none: add them on the next step",
  noCallouts: "—",
  calloutWarning: "This class says it does something that cannot be rolled back, such as sending email. It can only be tested in a sandbox.",
  noFlows: "There are no active flows of this kind.",
  noClasses: "No Apex classes implement IAIWorkflowActionExecutor. A developer needs to write and deploy one first.",
  loading: "Loading",
  chooseOne: "Choose one",
  fallbackError: "Something went wrong. Please try again."
};
