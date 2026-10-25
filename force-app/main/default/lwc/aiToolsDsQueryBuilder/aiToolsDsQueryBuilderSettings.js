/*
Component Name: aiToolsDsQueryBuilder

=================================================================
=================================================================

Description: The settings of the visual query builder: comparisons, filter value sources, list sizes, class names and label text.

Step 1: Name the comparisons and the three sources of a filter value
Step 2: Set how many matches the object list shows
Step 3: Name the classes of the lists and hold the label text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The three sources of a filter value. The Query step uses the same three values.
export const SOURCE_RECORD = "record";
export const SOURCE_FIXED = "fixed";
export const SOURCE_AGENT = "agent";

// The field type that is a true or false.
export const FIELD_TYPE_BOOLEAN = "boolean";

// The text of a value that is empty.
export const NO_TEXT = "";

// The order directions, and the text between a field and its direction in the order value.
export const ORDER_ASC = "ASC";
export const ORDER_DESC = "DESC";
export const ORDER_SEPARATOR = "|";

// How many objects the list shows while the admin types.
export const MAX_OBJECT_MATCHES = 8;

// The comparisons the builder can write, with the words shown for each.
export const OPERATOR_OPTIONS = [
  { label: "equals", value: "=" },
  { label: "not equals", value: "!=" },
  { label: "<", value: "<" },
  { label: "≤", value: "<=" },
  { label: ">", value: ">" },
  { label: "≥", value: ">=" }
];

// The values of a true or false filter.
export const BOOLEAN_OPTIONS = [
  { label: "true", value: "true" },
  { label: "false", value: "false" }
];

// The classes of the object list and the fields list.
export const OBJECT_ITEM_CLASS = "aiadqb-object-item";
export const PILL_CLASS = "aiadqb-source";

// Text shown to the user.
export const LABELS = {
  object: "Object",
  objectPlaceholder: "Start typing an object",
  maxRows: "Max rows",
  maxRowsHelp: "LIMIT · 1 to 200",
  fields: "Fields",
  fieldsCountMiddle: " of ",
  fieldsNote: " · only fields you can read are listed",
  searchFields: "Search fields",
  noFields: "Choose an object to see its fields.",
  noMatchingFields: "No field matches.",
  noObjects: "No object matches.",
  filters: "Filters",
  addFilter: "+ Filter",
  filterField: "Field",
  filterOperator: "Comparison",
  filterSource: "Value from",
  filterValue: "Value",
  filterInputName: "Input name",
  removeFilter: "Remove filter",
  filtersNote: "Each value is the open record, a fixed value, or an input the agent fills in. All filters are joined with AND.",
  sourceRecord: "Open record (:recordId)",
  sourceFixed: "Fixed value",
  sourceAgent: "Agent input",
  orderBy: "Order by",
  orderNone: "No order",
  ascending: " · ascending",
  descending: " · descending"
};
