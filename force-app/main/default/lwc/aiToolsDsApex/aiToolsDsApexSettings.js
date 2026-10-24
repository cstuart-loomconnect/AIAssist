/*
Component Name: aiToolsDsApex

=================================================================
=================================================================

Description: The settings of the Apex class step: the source type to switch to, the example class, class names and label text.

Step 1: Name the source type the Switch to SOQL button chooses
Step 2: Hold the example class that is copied for a developer
Step 3: Hold the label text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The source type the Switch to SOQL button chooses. Mirrors AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL.
export const SOURCE_TYPE_SOQL = "SOQL";

// The text of a value that is empty.
export const NO_TEXT = "";
export const NO_VALUE = "—";

// The number of digits after the point in an API version.
export const API_VERSION_DIGITS = 1;

// The classes of a class row, and of the chosen row.
export const ROW_CLASS = "aiadap-row";
export const ROW_SELECTED_CLASS = "aiadap-row aiadap-row_selected";
export const NAME_CLASS = "aiadap-class";
export const NAME_SELECTED_CLASS = "aiadap-class aiadap-class_selected";

// The toast variants.
export const TOAST_VARIANT_SUCCESS = "success";
export const TOAST_VARIANT_ERROR = "error";

// The example class a developer starts from. It implements the executor and the optional describer.
export const APEX_EXAMPLE = "public with sharing class MyDataSource implements IAIDataSourceExecutor, IAIDataSourceInputDescriber {\n\n    public AIDataSourceResponse execute(AIDataSourceRequest request) {\n\n        // Query in user mode, because what you return goes to an AI model\n        Map<String, Object> binds = new Map<String, Object>{'recordId' => request.recordId};\n        List<SObject> records = Database.queryWithBinds('SELECT Id, Name FROM Account WHERE Id = :recordId LIMIT 5', binds, AccessLevel.USER_MODE);\n\n        return new AIDataSourceResponse(records);\n    }\n\n    public String describeInputs() {\n\n        return '{\"type\":\"object\",\"properties\":{\"recordId\":{\"type\":\"string\",\"x-source\":\"page\"}}}';\n    }\n}";

// Text shown to the user.
export const LABELS = {
  intro: "Only classes in this org that implement IAIDataSourceExecutor are listed, found with an ApexTypeImplementor query.",
  columnClass: "Class",
  columnNamespace: "Namespace",
  columnApi: "API",
  columnInputs: "Declares inputs",
  noInputs: "none: add them on the next step",
  note: "Classes can describe their own inputs by also implementing IAIDataSourceInputDescriber. If they do, the next step is filled in for you.",
  emptyTitle: "No Apex classes implement IAIDataSourceExecutor",
  emptyText: "A developer needs to write and deploy one first. Until then, use a SOQL query, which covers most read-only needs.",
  switchToSoql: "Switch to SOQL",
  copyInterface: "Copy the interface to clipboard",
  copied: "Example class copied.",
  copyFailed: "The example could not be copied.",
  loading: "Loading Apex classes",
  chooseClass: "Choose class",
  fallbackError: "Something went wrong. Please try again."
};
