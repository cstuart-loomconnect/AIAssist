/*
Component Name: aiToolsDsQuery

=================================================================
=================================================================

Description: The settings of the Query step: modes, how a query is read and written, class names and label text.

Step 1: Name the two modes of the step and the three kinds of filter value
Step 2: Describe the words and patterns a simple query is made of
Step 3: Name the classes of the highlighted query and hold the label text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The two modes of the step.
export const QUERY_MODE_VISUAL = "visual";
export const QUERY_MODE_WRITE = "write";

// Who gives a filter its value. The builder component uses the same three values.
export const FILTER_SOURCE_RECORD = "record";
export const FILTER_SOURCE_FIXED = "fixed";
export const FILTER_SOURCE_AGENT = "agent";

// The binding type of a data source that needs the open record. Mirrors AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND.
export const BINDING_BOUND = "Bound";

// The severity of a problem that blocks the query. Mirrors AIAssistApplicationConstants.TOOLS_PROBLEM_ERROR.
export const PROBLEM_ERROR = "Error";

// The bind the open record fills. Mirrors AIAssistApplicationConstants.TOOLS_BIND_RECORD_ID.
export const BIND_RECORD_ID = "recordId";

// The most rows a data source may return, and the starting number. Mirror AIAssistApplicationConstants.TOOLS_SOQL_MAX_LIMIT and TOOLS_SOQL_DEFAULT_LIMIT.
export const MAX_ROWS_LIMIT = 200;
export const DEFAULT_MAX_ROWS = 20;

// How long to wait after the last change before the query is checked.
export const VALIDATE_DELAY_MS = 400;

// The comparisons the builder can write. The key is what is written in the query.
export const OPERATORS = ["=", "!=", "<", "<=", ">", ">="];

// The input types a bind can take, from the type of the field it is compared to.
export const INPUT_TYPE_STRING = "String";
export const INPUT_TYPE_DATE = "Date";
export const INPUT_TYPE_DATE_TIME = "DateTime";
export const INPUT_TYPE_NUMBER = "Number";
export const INPUT_TYPE_INTEGER = "Integer";
export const INPUT_TYPE_BOOLEAN = "Boolean";

// The field types that are written without quotes.
export const FIELD_TYPES_BOOLEAN = ["boolean"];
export const FIELD_TYPES_WHOLE_NUMBER = ["integer", "long"];
export const FIELD_TYPES_NUMBER = ["double", "currency", "percent"];
export const FIELD_TYPES_DATE = ["date"];
export const FIELD_TYPES_DATE_TIME = ["datetime"];

// The words the query writer puts in capitals, and the patterns that read a simple query back.
export const KEYWORD_PATTERN = /\b(SELECT|FROM|WHERE|AND|ORDER BY|ASC|DESC|LIMIT)\b/g;
export const BIND_PATTERN = /:[A-Za-z_]\w*/g;
export const SIMPLE_QUERY_PATTERN = /^\s*SELECT\s+(.+?)\s+FROM\s+(\w+)(?:\s+WHERE\s+(.+?))?(?:\s+ORDER\s+BY\s+(\w+)(?:\s+(ASC|DESC))?)?(?:\s+LIMIT\s+(\d+))?\s*;?\s*$/is;
export const SIMPLE_FILTER_PATTERN = /^(\w+)\s*(=|!=|<=|>=|<|>)\s*(.+)$/s;
export const SIMPLE_FIELD_PATTERN = /^\w+$/;
export const BIND_VALUE_PATTERN = /^:(\w+)$/;
export const QUOTED_VALUE_PATTERN = /^'(.*)'$/s;
export const NOT_SIMPLE_WHERE_PATTERN = /\bOR\b|\bNOT\b|\(|\)|\bIN\b|\bLIKE\b|\bINCLUDES\b|\bEXCLUDES\b/i;
export const FILTER_SPLIT_PATTERN = /\s+AND\s+/i;

// The classes of the highlighted query.
export const KEYWORD_CLASS = "aiadq-keyword";
export const BIND_CLASS = "aiadq-bind";
export const PLAIN_CLASS = "aiadq-plain";

// The text of a value that is empty.
export const NO_TEXT = "";

// The word before and after the order by field, and the directions.
export const ORDER_ASC = "ASC";
export const ORDER_DESC = "DESC";
export const ORDER_SEPARATOR = "|";

// Text shown to the user.
export const LABELS = {
  visualBuilder: "Visual builder",
  writeSoql: "Write SOQL",
  switchNote: "Switch any time; the builder reads back simple queries.",
  blockedByErrors: "The visual builder can't show this query until the errors are fixed.",
  blockedNotSimple: "The visual builder can only show simple queries: one object, plain fields, AND filters, one order by and a LIMIT.",
  maxRows: "Max rows",
  maxRowsHelp: "LIMIT · 1 to 200",
  generated: "Generated SOQL",
  validStart: "Valid · ",
  validBindOne: " bind found: ",
  validBindMany: " binds found: ",
  validNoBinds: "Valid · no binds",
  invalid: "The query has errors. Fix them to continue.",
  runsNote: "Runs with Database.queryWithBinds in USER_MODE through AISoqlTemplateRunner. Binds are values, never pasted into the query text.",
  checking: "Checking the query",
  noQuery: "Choose an object and the fields to read.",
  loading: "Loading objects and fields",
  fallbackError: "Something went wrong. Please try again."
};
