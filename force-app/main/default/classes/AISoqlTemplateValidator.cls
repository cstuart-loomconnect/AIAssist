/*
Class Name: AISoqlTemplateValidator

=================================================================
=================================================================

Description: Checks the SOQL template of a data source before it is saved and tells the admin what is wrong, with a fix where there is one.

Step 1: Refuse anything that is not a single SELECT, and read the object, fields, filters, order and limit
Step 2: Check the object and every field exists and the user can read it, suggesting the closest name when it does not
Step 3: Check the LIMIT and warn about hard-coded record ids and unused or misused binds
Step 4: Work out the binds, and the object of the open record from the field compared to :recordId

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AISoqlTemplateValidator {

    public class AISoqlTemplateValidatorException extends Exception {}

    private static final Pattern SELECT_PATTERN = Pattern.compile('(?is)^\\s*SELECT\\s+(.+?)\\s+FROM\\s+([A-Za-z_]\\w*)');
    private static final Pattern DYNAMIC_OBJECT_PATTERN = Pattern.compile('(?is)^\\s*SELECT\\s+.+?\\s+FROM\\s+:');
    private static final Pattern WRITE_PATTERN = Pattern.compile('(?i)\\b(INSERT|UPDATE|DELETE|UPSERT|MERGE|UNDELETE)\\b');
    private static final Pattern SUBQUERY_PATTERN = Pattern.compile('(?i)\\(\\s*SELECT\\b');
    private static final Pattern WHERE_PATTERN = Pattern.compile('(?is)\\bWHERE\\b(.*?)(?=\\bGROUP\\s+BY\\b|\\bHAVING\\b|\\bORDER\\s+BY\\b|\\bLIMIT\\b|\\bOFFSET\\b|\\bFOR\\b|\\z)');
    private static final Pattern ORDER_PATTERN = Pattern.compile('(?is)\\bORDER\\s+BY\\b(.*?)(?=\\bLIMIT\\b|\\bOFFSET\\b|\\bFOR\\b|\\z)');
    private static final Pattern LIMIT_PATTERN = Pattern.compile('(?i)\\bLIMIT\\s+(\\d+)');
    private static final Pattern FIELD_PATH_PATTERN = Pattern.compile('^[A-Za-z_]\\w*(\\.[A-Za-z_]\\w*)*$');
    private static final Pattern FILTER_FIELD_PATTERN = Pattern.compile('(?i)([A-Za-z_]\\w*(?:\\.[A-Za-z_]\\w*)*)\\s*(?:=|!=|<>|<=|>=|<|>|\\s+LIKE\\b|\\s+NOT\\s+IN\\b|\\s+IN\\b|\\s+INCLUDES\\b|\\s+EXCLUDES\\b)');
    private static final Pattern RECORD_FILTER_PATTERN = Pattern.compile('(?i)([A-Za-z_]\\w*(?:\\.[A-Za-z_]\\w*)*)\\s*=\\s*:' + AIAssistApplicationConstants.TOOLS_BIND_RECORD_ID + '\\b');
    private static final Pattern BIND_PATTERN = Pattern.compile(':([A-Za-z_]\\w*)');
    private static final Pattern ID_LITERAL_PATTERN = Pattern.compile('\'([A-Za-z0-9]{15}|[A-Za-z0-9]{18})\'');
    private static final Pattern FILTER_BEFORE_LITERAL_PATTERN = Pattern.compile('(?i)([A-Za-z_]\\w*)\\s*(?:=|!=|<>|IN\\s*\\()\\s*$');
    private static final Integer MAX_SUGGESTION_DISTANCE = 2;

    // Checks a query. isBound says whether the open record fills :recordId, and maxRows is the LIMIT the runner adds when the query has none.
    public static AIToolsDataStructure.SoqlValidation validate(String soql, Boolean isBound, Integer maxRows) {

        try {

            AIToolsDataStructure.SoqlValidation validation = new AIToolsDataStructure.SoqlValidation();
            String queryText = soql == null ? '' : soql;

            // [1] Look at the query with the quoted text and the bracketed parts blanked out, so keywords inside them are not mistaken for the query's own
            String topLevelText = blankOut(queryText, true);
            String unquotedText = blankOut(queryText, false);

            // [2] Collect the binds, which are found outside quoted text
            validation.binds = getBinds(unquotedText);

            // [3] Refuse a query that is not a single SELECT
            Matcher writeMatcher = WRITE_PATTERN.matcher(topLevelText);
            Matcher selectMatcher = SELECT_PATTERN.matcher(topLevelText);

            if (writeMatcher.find()) {

                addProblem(validation, AIAssistApplicationConstants.TOOLS_PROBLEM_ERROR, queryText, writeMatcher.start(), String.format(Label.AI_Tools_Soql_Only_Select, new List<String>{writeMatcher.group(1).toUpperCase()}));

            } else if (DYNAMIC_OBJECT_PATTERN.matcher(topLevelText).find()) {

                addProblem(validation, AIAssistApplicationConstants.TOOLS_PROBLEM_ERROR, queryText, 0, Label.AI_Tools_Soql_Object_Bind);

            } else if (!selectMatcher.find()) {

                addProblem(validation, AIAssistApplicationConstants.TOOLS_PROBLEM_ERROR, queryText, 0, Label.AI_Tools_Soql_Shape);

            } else {

                // [4] Check the query part by part
                validateQuery(validation, queryText, topLevelText, unquotedText, selectMatcher, isBound == true, maxRows);
            }

            // [5] The query is valid when it has no errors, warnings do not count
            validation.isValid = true;

            for (AIToolsDataStructure.SoqlProblem problem : validation.problems) {

                if (problem.severity == AIAssistApplicationConstants.TOOLS_PROBLEM_ERROR) validation.isValid = false;
            }

            return validation;

        } catch (Exception ex) {
            throw new AISoqlTemplateValidatorException('Failed to check the SOQL template: ' + ex.getMessage(), ex);
        }
    }

    // Checks a query that is a single SELECT.
    private static void validateQuery(AIToolsDataStructure.SoqlValidation validation, String queryText, String topLevelText, String unquotedText, Matcher selectMatcher, Boolean isBound, Integer maxRows) {

        // [1] Check the sub-queries are no more than one level deep
        checkSubqueryDepth(validation, queryText, unquotedText);

        // [2] Check the object exists and can be read
        String objectName = selectMatcher.group(2);
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName.toLowerCase());

        if (objectType == null || !objectType.getDescribe().isAccessible() || !objectType.getDescribe().isQueryable()) {

            addProblem(validation, AIAssistApplicationConstants.TOOLS_PROBLEM_ERROR, queryText, selectMatcher.start(2), String.format(Label.AI_Tools_Soql_Object_Missing, new List<String>{objectName}));
            return;
        }

        validation.objectApiName = objectType.getDescribe().getName();

        // [3] Check each selected field
        Integer selectListStart = selectMatcher.start(1);

        for (AIToolsDataStructure.SoqlPart part : splitList(topLevelText.substring(selectListStart, selectMatcher.end(1)), selectListStart)) {

            if (FIELD_PATH_PATTERN.matcher(part.text).matches()) checkFieldPath(validation, queryText, objectType, part.text, part.start);
        }

        // [4] Check each field in the WHERE and ORDER BY
        Matcher whereMatcher = WHERE_PATTERN.matcher(topLevelText);

        if (whereMatcher.find()) {

            Matcher filterMatcher = FILTER_FIELD_PATTERN.matcher(whereMatcher.group(1));

            while (filterMatcher.find()) {

                String candidate = filterMatcher.group(1);
                if (isKeyword(candidate)) continue;

                checkFieldPath(validation, queryText, objectType, candidate, whereMatcher.start(1) + filterMatcher.start(1));
            }

            // [5] Work out the object of the open record from the field compared to :recordId
            Matcher recordMatcher = RECORD_FILTER_PATTERN.matcher(whereMatcher.group(1));
            if (recordMatcher.find()) validation.recordObjectApiName = getRecordObjectApiName(objectType, recordMatcher.group(1));
        }

        Matcher orderMatcher = ORDER_PATTERN.matcher(topLevelText);

        if (orderMatcher.find()) {

            Integer orderStart = orderMatcher.start(1);

            for (AIToolsDataStructure.SoqlPart part : splitList(orderMatcher.group(1), orderStart)) {

                String firstWord = part.text.split('\\s+')[0];
                if (FIELD_PATH_PATTERN.matcher(firstWord).matches()) checkFieldPath(validation, queryText, objectType, firstWord, part.start);
            }
        }

        // [6] Check the LIMIT
        checkLimit(validation, queryText, topLevelText, maxRows);

        // [7] Warn about hard-coded record ids
        checkHardCodedIds(validation, queryText);

        // [8] Check :recordId is used the way the binding says
        Boolean usesRecordId = validation.binds.contains(AIAssistApplicationConstants.TOOLS_BIND_RECORD_ID);
        if (usesRecordId && !isBound) addProblem(validation, AIAssistApplicationConstants.TOOLS_PROBLEM_ERROR, queryText, unquotedText.indexOf(':' + AIAssistApplicationConstants.TOOLS_BIND_RECORD_ID), Label.AI_Tools_Soql_Record_Id_Unbound);
        if (!usesRecordId && isBound) addProblem(validation, AIAssistApplicationConstants.TOOLS_PROBLEM_WARNING, queryText, 0, Label.AI_Tools_Soql_Record_Id_Unused);
    }

    // Refuses a sub-query that holds another sub-query.
    private static void checkSubqueryDepth(AIToolsDataStructure.SoqlValidation validation, String queryText, String unquotedText) {

        // [1] Look at each opening sub-query bracket
        Matcher subqueryMatcher = SUBQUERY_PATTERN.matcher(unquotedText);

        while (subqueryMatcher.find()) {

            // [2] Find where that bracket closes
            Integer depth = 0;
            Integer closeIndex = unquotedText.length();

            for (Integer charIndex = subqueryMatcher.start(); charIndex < unquotedText.length(); charIndex++) {

                String character = unquotedText.substring(charIndex, charIndex + 1);
                if (character == '(') depth++;
                if (character == ')') depth--;

                if (depth == 0) {

                    closeIndex = charIndex;
                    break;
                }
            }

            // [3] Refuse it when another sub-query is inside
            String inside = unquotedText.substring(subqueryMatcher.start() + 1, closeIndex);

            if (SUBQUERY_PATTERN.matcher(inside).find()) {

                addProblem(validation, AIAssistApplicationConstants.TOOLS_PROBLEM_ERROR, queryText, subqueryMatcher.start(), Label.AI_Tools_Soql_Subquery_Depth);
                return;
            }
        }
    }

    // Checks a field path such as Name or Account.Owner.Name exists and can be read, and adds a problem with the closest name when it does not.
    private static void checkFieldPath(AIToolsDataStructure.SoqlValidation validation, String queryText, Schema.SObjectType rootType, String fieldPath, Integer pathStart) {

        // [1] Walk down the relationships, one name at a time
        List<String> names = fieldPath.split('\\.');
        Schema.SObjectType currentType = rootType;
        Integer nameStart = pathStart;

        for (Integer nameIndex = 0; nameIndex < names.size(); nameIndex++) {

            String name = names[nameIndex];
            Map<String, Schema.SObjectField> fieldsByName = currentType.getDescribe().fields.getMap();
            Boolean isLast = nameIndex == names.size() - 1;

            if (isLast) {

                // [2] The last name is a field
                Schema.SObjectField field = fieldsByName.get(name.toLowerCase());

                if (field == null) {

                    addFieldMissingProblem(validation, queryText, currentType, name, nameStart);

                } else if (!field.getDescribe().isAccessible()) {

                    addProblem(validation, AIAssistApplicationConstants.TOOLS_PROBLEM_ERROR, queryText, nameStart, String.format(Label.AI_Tools_Soql_Field_Hidden, new List<String>{name, currentType.getDescribe().getName()}));
                }

                return;
            }

            // [3] Any other name is a relationship to a parent
            Schema.SObjectType parentType = findParentType(fieldsByName, name);

            if (parentType == null) {

                addProblem(validation, AIAssistApplicationConstants.TOOLS_PROBLEM_ERROR, queryText, nameStart, String.format(Label.AI_Tools_Soql_Relationship_Missing, new List<String>{name, currentType.getDescribe().getName()}));
                return;
            }

            currentType = parentType;
            nameStart += name.length() + 1;
        }
    }

    // Adds the problem for a field that does not exist, with the closest name as the fix.
    private static void addFieldMissingProblem(AIToolsDataStructure.SoqlValidation validation, String queryText, Schema.SObjectType objectType, String name, Integer nameStart) {

        // [1] Look for a close name
        String objectName = objectType.getDescribe().getName();
        String suggestion = getClosestFieldName(objectType, name);

        // [2] Say so, with the fix when there is a close name
        if (suggestion == null) {

            addProblem(validation, AIAssistApplicationConstants.TOOLS_PROBLEM_ERROR, queryText, nameStart, String.format(Label.AI_Tools_Soql_Field_Missing, new List<String>{name, objectName}));
            return;
        }

        AIToolsDataStructure.SoqlProblem problem = addProblem(validation, AIAssistApplicationConstants.TOOLS_PROBLEM_ERROR, queryText, nameStart, String.format(Label.AI_Tools_Soql_Field_Suggest, new List<String>{name, objectName, suggestion}));
        problem.fixLabel = Label.AI_Tools_Fix;
        problem.fixStart = nameStart;
        problem.fixEnd = nameStart + name.length();
        problem.fixText = suggestion;
    }

    // The name of the field closest to the one typed, or null when none is close.
    private static String getClosestFieldName(Schema.SObjectType objectType, String name) {

        // [1] Prefer a field the typed name is the start of, or that is the start of the typed name
        String lowerName = name.toLowerCase();
        String bestName;
        Integer bestDistance = MAX_SUGGESTION_DISTANCE + 1;

        for (Schema.SObjectField field : objectType.getDescribe().fields.getMap().values()) {

            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (!fieldDescribe.isAccessible()) continue;

            String candidate = fieldDescribe.getName();
            String lowerCandidate = candidate.toLowerCase();

            // [2] A name that starts with the typed name is the best match, shortest first
            Boolean isPrefix = lowerCandidate.startsWith(lowerName) || lowerName.startsWith(lowerCandidate);
            Integer distance = isPrefix ? 0 : getEditDistance(lowerName, lowerCandidate);

            if (distance < bestDistance || (distance == bestDistance && bestName != null && candidate.length() < bestName.length())) {

                bestDistance = distance;
                bestName = candidate;
            }
        }

        return bestDistance <= MAX_SUGGESTION_DISTANCE ? bestName : null;
    }

    // The number of single-character changes between two names.
    private static Integer getEditDistance(String first, String second) {

        // [1] Names that differ a lot in length cannot be close
        if (Math.abs(first.length() - second.length()) > MAX_SUGGESTION_DISTANCE) return MAX_SUGGESTION_DISTANCE + 1;

        // [2] Fill the table one row at a time
        List<Integer> previousRow = new List<Integer>();

        for (Integer columnIndex = 0; columnIndex <= second.length(); columnIndex++) previousRow.add(columnIndex);

        for (Integer rowIndex = 1; rowIndex <= first.length(); rowIndex++) {

            List<Integer> currentRow = new List<Integer>{rowIndex};

            for (Integer columnIndex = 1; columnIndex <= second.length(); columnIndex++) {

                Integer substitutionCost = first.substring(rowIndex - 1, rowIndex) == second.substring(columnIndex - 1, columnIndex) ? 0 : 1;
                currentRow.add(Math.min(Math.min(currentRow[columnIndex - 1] + 1, previousRow[columnIndex] + 1), previousRow[columnIndex - 1] + substitutionCost));
            }

            previousRow = currentRow;
        }

        return previousRow[second.length()];
    }

    // The object a relationship name points to, or null when the object has no such relationship.
    private static Schema.SObjectType findParentType(Map<String, Schema.SObjectField> fieldsByName, String relationshipName) {

        // [1] Find the lookup field whose relationship has that name
        for (Schema.SObjectField field : fieldsByName.values()) {

            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            Boolean isMatch = fieldDescribe.getRelationshipName() != null && fieldDescribe.getRelationshipName().equalsIgnoreCase(relationshipName);

            if (isMatch && !fieldDescribe.getReferenceTo().isEmpty()) return fieldDescribe.getReferenceTo()[0];
        }

        return null;
    }

    // The object of the open record: the query object when the field is Id, or the object a lookup field points to.
    private static String getRecordObjectApiName(Schema.SObjectType objectType, String fieldPath) {

        // [1] Id means the open record is the queried object itself
        if (fieldPath.equalsIgnoreCase('Id')) return objectType.getDescribe().getName();

        // [2] Walk down to the last field
        List<String> names = fieldPath.split('\\.');
        Schema.SObjectType currentType = objectType;

        for (Integer nameIndex = 0; nameIndex < names.size() - 1; nameIndex++) {

            currentType = findParentType(currentType.getDescribe().fields.getMap(), names[nameIndex]);
            if (currentType == null) return null;
        }

        // [3] A lookup field points to the object of the open record
        Schema.SObjectField field = currentType.getDescribe().fields.getMap().get(names[names.size() - 1].toLowerCase());
        if (field == null || field.getDescribe().getReferenceTo().isEmpty()) return null;

        return field.getDescribe().getReferenceTo()[0].getDescribe().getName();
    }

    // Warns when there is no LIMIT, and refuses one over the most the data source may return.
    private static void checkLimit(AIToolsDataStructure.SoqlValidation validation, String queryText, String topLevelText, Integer maxRows) {

        // [1] No LIMIT: the runner adds one, so this is only a warning
        Integer rowCap = maxRows == null || maxRows < 1 ? AIAssistApplicationConstants.TOOLS_SOQL_DEFAULT_LIMIT : maxRows;
        Matcher limitMatcher = LIMIT_PATTERN.matcher(topLevelText);

        if (!limitMatcher.find()) {

            AIToolsDataStructure.SoqlProblem noLimitProblem = addProblem(validation, AIAssistApplicationConstants.TOOLS_PROBLEM_WARNING, queryText, queryText.length(), String.format(Label.AI_Tools_Soql_No_Limit, new List<String>{String.valueOf(rowCap)}));
            noLimitProblem.fixLabel = String.format(Label.AI_Tools_Fix_Add_Limit, new List<String>{String.valueOf(rowCap)});
            noLimitProblem.fixStart = queryText.length();
            noLimitProblem.fixEnd = queryText.length();
            noLimitProblem.fixText = '\nLIMIT ' + rowCap;
            return;
        }

        // [2] A LIMIT over the most a data source may return
        Integer limitValue = Integer.valueOf(limitMatcher.group(1));
        if (limitValue <= AIAssistApplicationConstants.TOOLS_SOQL_MAX_LIMIT) return;

        AIToolsDataStructure.SoqlProblem highLimitProblem = addProblem(validation, AIAssistApplicationConstants.TOOLS_PROBLEM_ERROR, queryText, limitMatcher.start(), String.format(Label.AI_Tools_Soql_Limit_Too_High, new List<String>{String.valueOf(limitValue)}));
        highLimitProblem.fixLabel = Label.AI_Tools_Fix_Use_Limit;
        highLimitProblem.fixStart = limitMatcher.start(1);
        highLimitProblem.fixEnd = limitMatcher.end(1);
        highLimitProblem.fixText = String.valueOf(AIAssistApplicationConstants.TOOLS_SOQL_MAX_LIMIT);
    }

    // Warns about a record id typed into the query, because it will not exist in another org.
    private static void checkHardCodedIds(AIToolsDataStructure.SoqlValidation validation, String queryText) {

        // [1] Look at each quoted text that is the length of an id
        Matcher idMatcher = ID_LITERAL_PATTERN.matcher(queryText);

        while (idMatcher.find()) {

            // [2] Only text that is a real id counts
            if (!isRecordId(idMatcher.group(1))) continue;

            // [3] Name the bind after the field it is compared to
            String textBefore = queryText.substring(0, idMatcher.start());
            Matcher fieldMatcher = FILTER_BEFORE_LITERAL_PATTERN.matcher(textBefore);
            String fieldName = fieldMatcher.find() ? fieldMatcher.group(1) : 'inputValue';
            String bindName = fieldName.left(1).toLowerCase() + fieldName.substring(1);

            AIToolsDataStructure.SoqlProblem problem = addProblem(validation, AIAssistApplicationConstants.TOOLS_PROBLEM_WARNING, queryText, idMatcher.start(), Label.AI_Tools_Soql_Hard_Coded_Id);
            problem.fixLabel = Label.AI_Tools_Fix_Turn_Into_Input;
            problem.fixStart = idMatcher.start();
            problem.fixEnd = idMatcher.end();
            problem.fixText = ':' + bindName;
        }
    }

    // True when the text is a record id of an object that exists.
    private static Boolean isRecordId(String idText) {

        // [1] Only an id with a known object prefix counts
        try {

            return Id.valueOf(idText).getSobjectType() != null;

        } catch (Exception ex) {

            return false;
        }
    }

    // The bind names in the order they first appear.
    private static List<String> getBinds(String unquotedText) {

        // [1] Collect each name once
        List<String> binds = new List<String>();
        Matcher bindMatcher = BIND_PATTERN.matcher(unquotedText);

        while (bindMatcher.find()) {

            if (!binds.contains(bindMatcher.group(1))) binds.add(bindMatcher.group(1));
        }

        return binds;
    }

    // Splits a list on the commas that are not inside brackets, keeping where each part starts in the query.
    private static List<AIToolsDataStructure.SoqlPart> splitList(String listText, Integer listStart) {

        // [1] Cut at each comma. The text has its brackets blanked, so every comma is a top level one
        List<AIToolsDataStructure.SoqlPart> parts = new List<AIToolsDataStructure.SoqlPart>();
        Integer partStart = 0;

        for (Integer charIndex = 0; charIndex <= listText.length(); charIndex++) {

            Boolean isEnd = charIndex == listText.length();
            if (!isEnd && listText.substring(charIndex, charIndex + 1) != ',') continue;

            // [2] Skip the spaces at the start of the part
            String rawPart = listText.substring(partStart, charIndex);
            String trimmedPart = rawPart.trim();

            if (String.isNotBlank(trimmedPart)) {

                AIToolsDataStructure.SoqlPart part = new AIToolsDataStructure.SoqlPart();
                part.text = trimmedPart;
                part.start = listStart + partStart + rawPart.indexOf(trimmedPart);
                parts.add(part);
            }

            partStart = charIndex + 1;
        }

        return parts;
    }

    // Blanks out the quoted text, and the bracketed parts when asked, keeping every other character in the same place.
    private static String blankOut(String queryText, Boolean shouldBlankBrackets) {

        // [1] Walk the text, tracking whether it is inside quotes or brackets
        String result = '';
        Boolean isInQuote = false;
        Integer depth = 0;

        for (Integer charIndex = 0; charIndex < queryText.length(); charIndex++) {

            String character = queryText.substring(charIndex, charIndex + 1);
            Boolean isEscaped = charIndex > 0 && queryText.substring(charIndex - 1, charIndex) == '\\';

            // [2] A quote starts or ends quoted text
            if (character == '\'' && !isEscaped) {

                isInQuote = !isInQuote;
                result += character;
                continue;
            }

            // [3] A bracket changes the depth, and the brackets themselves are kept
            if (!isInQuote && shouldBlankBrackets && character == '(') depth++;
            Boolean isBlanked = isInQuote || (shouldBlankBrackets && depth > 0 && character != '(' && character != ')');
            if (!isInQuote && shouldBlankBrackets && character == ')' && depth > 0) depth--;

            // [4] Keep the line breaks so line numbers stay right
            result += isBlanked && character != '\n' ? ' ' : character;
        }

        return result;
    }

    // True for a word that can appear before an operator in a WHERE but is not a field.
    private static Boolean isKeyword(String word) {

        // [1] Words that join or negate filters
        return new Set<String>{'and', 'or', 'not', 'where', 'having', 'null', 'true', 'false'}.contains(word.toLowerCase());
    }

    // Adds a problem on the line that holds the offset, and returns it so a fix can be added.
    private static AIToolsDataStructure.SoqlProblem addProblem(AIToolsDataStructure.SoqlValidation validation, String severity, String queryText, Integer offset, String message) {

        // [1] Work out the line from the number of line breaks before the offset
        Integer safeOffset = Math.min(Math.max(offset, 0), queryText.length());
        AIToolsDataStructure.SoqlProblem problem = new AIToolsDataStructure.SoqlProblem();
        problem.severity = severity;
        problem.line = queryText.substring(0, safeOffset).countMatches('\n') + 1;
        problem.message = message;
        validation.problems.add(problem);

        return problem;
    }
}
