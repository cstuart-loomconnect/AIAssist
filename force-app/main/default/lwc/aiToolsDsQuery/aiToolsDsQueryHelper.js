/*
Component Name: aiToolsDsQuery

=================================================================
=================================================================

Description: The extended methods of the Query step: write a query from the builder, read a simple query back into the builder, highlight a query and write the checking message.

Step 1: Write the query from the object, fields, filters, order and max rows of the builder
Step 2: Read a simple query back into the builder, or say it is too complex
Step 3: Work out the input type of each bind from the field it is compared to
Step 4: Highlight a query and write the message under it

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { FILTER_SOURCE_RECORD, FILTER_SOURCE_FIXED, FILTER_SOURCE_AGENT, BIND_RECORD_ID, DEFAULT_MAX_ROWS, INPUT_TYPE_STRING, INPUT_TYPE_DATE, INPUT_TYPE_DATE_TIME, INPUT_TYPE_NUMBER, INPUT_TYPE_INTEGER, INPUT_TYPE_BOOLEAN, FIELD_TYPES_BOOLEAN, FIELD_TYPES_WHOLE_NUMBER, FIELD_TYPES_NUMBER, FIELD_TYPES_DATE, FIELD_TYPES_DATE_TIME, KEYWORD_PATTERN, BIND_PATTERN, SIMPLE_QUERY_PATTERN, SIMPLE_FILTER_PATTERN, SIMPLE_FIELD_PATTERN, BIND_VALUE_PATTERN, QUOTED_VALUE_PATTERN, NOT_SIMPLE_WHERE_PATTERN, FILTER_SPLIT_PATTERN, KEYWORD_CLASS, BIND_CLASS, PLAIN_CLASS, ORDER_ASC, ORDER_SEPARATOR, NO_TEXT, LABELS } from "./aiToolsDsQuerySettings";

// Builds an empty builder, for a query that has not been started.
export function buildEmptyBuilder() {

  // [1] Nothing is chosen yet
  const builder = { objectApiName: NO_TEXT, selectedFields: [], filters: [], orderValue: NO_TEXT };

  return builder;
}

// Finds the type of a field in the list of fields of the object.
export function findFieldType(fieldOptions, fieldApiName) {

  // [1] An unknown field is treated as text
  const field = fieldOptions.find((option) => option.apiName === fieldApiName);

  return field ? field.dataType : NO_TEXT;
}

// Writes a value so it can sit in a query, quoting text and leaving numbers, dates and true or false bare.
export function buildLiteral(value, dataType) {

  // [1] Read the value as text
  const text = String(value === undefined || value === null ? NO_TEXT : value).trim();

  // [2] True or false and numbers are not quoted
  if (FIELD_TYPES_BOOLEAN.includes(dataType)) return text.toLowerCase() === "true" ? "true" : "false";
  if ([...FIELD_TYPES_WHOLE_NUMBER, ...FIELD_TYPES_NUMBER].includes(dataType)) return text !== NO_TEXT && Number.isFinite(Number(text)) ? text : "0";

  // [3] Dates, date times and date words such as LAST_N_DAYS:30 are not quoted
  if ([...FIELD_TYPES_DATE, ...FIELD_TYPES_DATE_TIME].includes(dataType)) return text || "TODAY";

  // [4] Any other value is quoted, with backslashes and quotes escaped
  const escaped = text.replace(/\\/g, "\\\\").replace(/'/g, "\\'");

  return "'" + escaped + "'";
}

// Writes the right side of one filter.
export function buildFilterValue(filter, dataType) {

  // [1] The open record and the agent are binds, and a fixed value is written out
  if (filter.source === FILTER_SOURCE_RECORD) return ":" + BIND_RECORD_ID;
  if (filter.source === FILTER_SOURCE_AGENT) return ":" + filter.inputName;

  return buildLiteral(filter.fixedValue, dataType);
}

// Writes the query from the builder.
export function buildSoql(builder, maxRows, fieldOptions) {

  // [1] Nothing to write until an object is chosen
  if (!builder || !builder.objectApiName) return NO_TEXT;

  // [2] Always select the Id, then the chosen fields in the order the list shows them
  const orderedFields = fieldOptions.filter((option) => builder.selectedFields.includes(option.apiName)).map((option) => option.apiName);
  const unlistedFields = builder.selectedFields.filter((name) => !fieldOptions.some((option) => option.apiName === name));
  const selectList = ["Id", ...orderedFields, ...unlistedFields].join(", ");
  const lines = ["SELECT " + selectList, "FROM " + builder.objectApiName];

  // [3] One condition for each filter that has a field, joined with AND
  const conditions = builder.filters.filter((filter) => filter.fieldApiName).map((filter) => {

    const dataType = filter.fieldType || findFieldType(fieldOptions, filter.fieldApiName);

    return filter.fieldApiName + " " + filter.operator + " " + buildFilterValue(filter, dataType);
  });

  conditions.forEach((condition, index) => lines.push((index === 0 ? "WHERE " : "  AND ") + condition));

  // [4] The order by and the LIMIT
  if (builder.orderValue) {

    const [orderField, orderDirection] = builder.orderValue.split(ORDER_SEPARATOR);
    lines.push("ORDER BY " + orderField + " " + orderDirection);
  }

  lines.push("LIMIT " + (maxRows || DEFAULT_MAX_ROWS));

  return lines.join("\n");
}

// Gives each filter the type of its field, so the query and the inputs are written with the right type.
export function fillFilterTypes(builder, fieldOptions) {

  // [1] Copy each filter with the type of its field
  const filters = builder.filters.map((filter) => ({ ...filter, fieldType: findFieldType(fieldOptions, filter.fieldApiName) || filter.fieldType }));

  return { ...builder, filters };
}

// Works out the input type of a field type, for the agent input that a filter creates.
export function getInputTypeOfField(dataType) {

  // [1] Match the field type to an input type
  if (FIELD_TYPES_DATE.includes(dataType)) return INPUT_TYPE_DATE;
  if (FIELD_TYPES_DATE_TIME.includes(dataType)) return INPUT_TYPE_DATE_TIME;
  if (FIELD_TYPES_BOOLEAN.includes(dataType)) return INPUT_TYPE_BOOLEAN;
  if (FIELD_TYPES_WHOLE_NUMBER.includes(dataType)) return INPUT_TYPE_INTEGER;
  if (FIELD_TYPES_NUMBER.includes(dataType)) return INPUT_TYPE_NUMBER;

  return INPUT_TYPE_STRING;
}

// Builds the input type of each agent bind, from the filters of the builder.
export function buildBindTypes(builder) {

  // [1] Only a filter the agent fills creates a bind
  const typeByBind = {};

  if (!builder) return typeByBind;

  builder.filters.forEach((filter) => {

    if (filter.source === FILTER_SOURCE_AGENT && filter.inputName) typeByBind[filter.inputName] = getInputTypeOfField(filter.fieldType);
  });

  return typeByBind;
}

// Reads a filter back from text such as "CloseDate <= :closeBefore", or returns null when it is not simple.
function parseFilter(conditionText) {

  // [1] Split it into field, comparison and value
  const match = SIMPLE_FILTER_PATTERN.exec(conditionText.trim());
  if (!match) return null;

  const [, fieldApiName, operator, rawValue] = match;
  const value = rawValue.trim();
  const key = Math.random().toString(36).slice(2);
  const filter = { key, fieldApiName, fieldType: NO_TEXT, operator, source: FILTER_SOURCE_FIXED, fixedValue: NO_TEXT, inputName: NO_TEXT };

  // [2] A bind is the open record or an agent input
  const bindMatch = BIND_VALUE_PATTERN.exec(value);

  if (bindMatch) {

    filter.source = bindMatch[1] === BIND_RECORD_ID ? FILTER_SOURCE_RECORD : FILTER_SOURCE_AGENT;
    filter.inputName = bindMatch[1] === BIND_RECORD_ID ? NO_TEXT : bindMatch[1];

    return filter;
  }

  // [3] Anything else is a fixed value, with quotes taken off
  const quotedMatch = QUOTED_VALUE_PATTERN.exec(value);
  filter.fixedValue = quotedMatch ? quotedMatch[1].replace(/\\'/g, "'").replace(/\\\\/g, "\\") : value;

  return filter;
}

// Reads a simple query back into the builder. Returns null when the query is not simple, such as one with OR, brackets or functions.
export function parseSoql(soql) {

  // [1] Match the whole query against the simple shape
  const match = SIMPLE_QUERY_PATTERN.exec(soql || NO_TEXT);
  if (!match) return null;

  const [, selectText, objectApiName, whereText, orderField, orderDirection] = match;

  // [2] Every selected field must be a plain name. The Id is always selected, so it is not listed
  const selectParts = selectText.split(",").map((part) => part.trim());
  if (!selectParts.every((part) => SIMPLE_FIELD_PATTERN.test(part))) return null;

  const selectedFields = selectParts.filter((part) => part.toLowerCase() !== "id");

  // [3] The filters must be plain comparisons joined with AND
  let filters = [];

  if (whereText) {

    if (NOT_SIMPLE_WHERE_PATTERN.test(whereText.replace(/'(?:[^'\\]|\\.)*'/g, "''"))) return null;

    const parsedFilters = whereText.split(FILTER_SPLIT_PATTERN).map((conditionText) => parseFilter(conditionText));
    if (parsedFilters.some((filter) => filter === null)) return null;

    filters = parsedFilters;
  }

  // [4] The order by
  const orderValue = orderField ? orderField + ORDER_SEPARATOR + (orderDirection ? orderDirection.toUpperCase() : ORDER_ASC) : NO_TEXT;

  return { objectApiName, selectedFields, filters, orderValue };
}

// Reads the LIMIT of a query, or returns null when it has none.
export function parseLimit(soql) {

  // [1] Find the number after LIMIT
  const match = /\bLIMIT\s+(\d+)/i.exec(soql || NO_TEXT);

  return match ? Number(match[1]) : null;
}

// Cuts a query into pieces, each with the class that colours it: keywords, binds and plain text.
export function buildHighlightedParts(soql) {

  // [1] Mark each keyword and bind with the place it starts and ends
  const marks = [];

  for (const match of soql.matchAll(KEYWORD_PATTERN)) marks.push({ start: match.index, end: match.index + match[0].length, cssClass: KEYWORD_CLASS });
  for (const match of soql.matchAll(BIND_PATTERN)) marks.push({ start: match.index, end: match.index + match[0].length, cssClass: BIND_CLASS });

  marks.sort((first, second) => first.start - second.start);

  // [2] Cut the text at each mark, keeping the plain text between
  const parts = [];
  let position = 0;

  marks.forEach((mark, index) => {

    if (mark.start > position) parts.push({ key: "p" + index, text: soql.slice(position, mark.start), cssClass: PLAIN_CLASS });
    parts.push({ key: "m" + index, text: soql.slice(mark.start, mark.end), cssClass: mark.cssClass });
    position = mark.end;
  });

  if (position < soql.length) parts.push({ key: "end", text: soql.slice(position), cssClass: PLAIN_CLASS });

  return parts;
}

// Writes the message under the generated query, such as "Valid · 2 binds found: :recordId, :closeBefore".
export function buildValidMessage(binds) {

  // [1] No binds
  if (binds.length === 0) return LABELS.validNoBinds;

  // [2] List each bind with its colon
  const bindList = binds.map((bind) => ":" + bind).join(", ");
  const bindText = binds.length === 1 ? LABELS.validBindOne : LABELS.validBindMany;

  return LABELS.validStart + binds.length + bindText + bindList;
}

// Applies a fix to the query text: the text from start to end is replaced.
export function applyFix(soql, fix) {

  // [1] Cut the text around the part to replace, and put the new text between
  const fixedText = soql.slice(0, fix.start) + fix.text + soql.slice(fix.end);

  return fixedText;
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
