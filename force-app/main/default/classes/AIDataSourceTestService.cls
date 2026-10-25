/*
Class Name: AIDataSourceTestService

=================================================================
=================================================================

Description: Runs a data source definition once, as the admin, so the AI Tools tab can show what the agent would get and whether another user would see all of it.

Step 1: Check the definition can run and the inputs are the ones it declares
Step 2: Run the SOQL template or the Apex class the same way the dispatcher does, in user mode
Step 3: Turn the records into a table, and note the fields the PII Registry masks and the rows that were not returned
Step 4: When another user is being checked, find the fields their permission sets cannot read
Step 5: Report passed, partial or failed

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIDataSourceTestService {

    public class AIDataSourceTestServiceException extends Exception {}

    private static final Pattern COUNT_SELECT_PATTERN = Pattern.compile('(?is)^\\s*SELECT\\s+.+?\\s+FROM\\s+');
    private static final Pattern COUNT_ORDER_PATTERN = Pattern.compile('(?is)\\s+ORDER\\s+BY\\s+.*?(?=\\s+LIMIT\\b|\\z)');
    private static final Pattern COUNT_LIMIT_PATTERN = Pattern.compile('(?is)\\s+LIMIT\\s+\\d+');
    private static final String ID_FIELD = 'Id';
    private static final String ATTRIBUTES_KEY = 'attributes';
    private static final String PARENT_SEPARATOR = '.';

    // Runs the definition and reports what happened. A failure is reported in the result, never thrown, because a failing test is an answer.
    public static AIToolsDataStructure.TestResult runTest(AIToolsDataStructure.DataSourceDetail detail, AIToolsDataStructure.TestRequest request) {

        AIToolsDataStructure.TestResult result = new AIToolsDataStructure.TestResult();
        result.queryLimit = Limits.getLimitQueries();
        result.currencyCode = UserInfo.getDefaultCurrency();
        Long startedAt = System.currentTimeMillis();
        Integer queriesBefore = Limits.getQueries();

        try {

            // [1] Refuse a bound data source with no record to run against
            AIToolsDataStructure.TestRequest testRequest = request == null ? new AIToolsDataStructure.TestRequest() : request;
            Boolean isBound = detail.bindingType == AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
            if (isBound && testRequest.recordId == null) throw new AIDataSourceTestServiceException(Label.AI_Tools_Error_Record_Required);

            // [2] Keep only the inputs the data source declares, in the type it declares
            Map<String, Object> bindValues = AIDataSourceInputBinder.getBindValues(detail.inputSchema, testRequest.inputValues);
            Integer maxRows = detail.maxRows == null ? null : detail.maxRows.intValue();

            // [3] Run the data source
            List<SObject> records;

            if (detail.sourceType == AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL) {

                if (testRequest.recordId != null) bindValues.put(AIAssistApplicationConstants.TOOLS_BIND_RECORD_ID, testRequest.recordId);
                records = runSoql(detail.soqlTemplate, bindValues, maxRows, result);

            } else if (detail.sourceType == AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX) {

                records = runApex(detail, testRequest.recordId, bindValues, maxRows);

            } else {

                throw new AIDataSourceTestServiceException(Label.AI_Tools_Error_Source_Type);
            }

            result.queriesUsed = Limits.getQueries() - queriesBefore;
            result.rowCount = records.size();

            // [4] Build the table and note the fields that are masked
            buildTable(records, result);

            // [5] Check what another user would see, when one was chosen
            if (testRequest.runAsUserId != null && testRequest.runAsUserId != UserInfo.getUserId()) checkUserAccess(testRequest.runAsUserId, records, result);

            // [6] Passed when everything shows, partial when a field was hidden
            result.status = result.removedFields.isEmpty() ? AIAssistApplicationConstants.TOOLS_TEST_STATUS_PASSED : AIAssistApplicationConstants.TOOLS_TEST_STATUS_PARTIAL;

        } catch (Exception ex) {

            result.status = AIAssistApplicationConstants.TOOLS_TEST_STATUS_FAILED;
            result.message = getFriendlyMessage(ex);
        }

        result.elapsedMilliseconds = System.currentTimeMillis() - startedAt;

        return result;
    }

    // Runs the template through the runner the dispatcher uses, and warns when more rows matched than were returned.
    private static List<SObject> runSoql(String soqlTemplate, Map<String, Object> bindValues, Integer maxRows, AIToolsDataStructure.TestResult result) {

        // [1] Refuse a data source with no template
        if (String.isBlank(soqlTemplate)) throw new AIDataSourceTestServiceException(Label.AI_Tools_Error_No_Template);

        // [2] Run it in user mode
        List<SObject> records = AISoqlTemplateRunner.runTemplate(soqlTemplate, bindValues, maxRows);

        // [3] A full result may be cut short, so count what matched
        Integer rowCap = maxRows == null || maxRows < 1 ? AIAssistApplicationConstants.TOOLS_SOQL_DEFAULT_LIMIT : maxRows;
        if (records.size() < rowCap) return records;

        try {

            String countSoql = soqlTemplate.trim().removeEnd(';');
            countSoql = COUNT_ORDER_PATTERN.matcher(countSoql).replaceAll('');
            countSoql = COUNT_LIMIT_PATTERN.matcher(countSoql).replaceAll('');
            countSoql = COUNT_SELECT_PATTERN.matcher(countSoql).replaceFirst('SELECT COUNT() FROM ');
            Integer matchedRows = Database.countQueryWithBinds(countSoql, bindValues, AccessLevel.USER_MODE);

            if (matchedRows > rowCap) result.warnings.add(String.format(Label.AI_Tools_Error_Too_Many_Rows, new List<String>{String.valueOf(matchedRows), String.valueOf(rowCap)}));

        } catch (Exception ex) {

            // [4] A query that cannot be counted is not a reason to fail the test
            result.warnings.add(Label.AI_Tools_Warning_Count_Failed);
        }

        return records;
    }

    // Runs the Apex class the same way the dispatcher does, after checking it implements the interface.
    private static List<SObject> runApex(AIToolsDataStructure.DataSourceDetail detail, Id recordId, Map<String, Object> inputParameters, Integer maxRows) {

        // [1] Refuse a data source with no class, or a class that is not an executor
        if (String.isBlank(detail.apexClassName)) throw new AIDataSourceTestServiceException(Label.AI_Tools_Error_Apex_Class);

        Type apexType = Type.forName('', detail.apexClassName.trim());

        if (apexType == null || !IAIDataSourceExecutor.class.isAssignableFrom(apexType)) throw new AIDataSourceTestServiceException(String.format(Label.AI_Tools_Error_Class_Not_Executor, new List<String>{detail.apexClassName}));

        // [2] Tell the class who is asking and for what
        AIDataSourceRequest request = new AIDataSourceRequest();
        request.recordId = recordId;
        request.inputParameters = inputParameters;
        request.userId = UserInfo.getUserId();
        request.dataSourceName = detail.developerName;
        request.maxRows = maxRows;

        // [3] Run the class and take its records, cut to the row cap
        Object executor = apexType.newInstance();
        AIDataSourceResponse response = ((IAIDataSourceExecutor) executor).execute(request);
        List<SObject> records = response == null || response.records == null ? new List<SObject>() : response.records;
        if (maxRows == null || records.size() <= maxRows) return records;

        List<SObject> cappedRecords = new List<SObject>();

        for (Integer recordIndex = 0; recordIndex < maxRows; recordIndex++) cappedRecords.add(records[recordIndex]);

        return cappedRecords;
    }

    // Puts the records in rows and columns, one level of parent fields flattened, and notes the fields the PII Registry masks.
    private static void buildTable(List<SObject> records, AIToolsDataStructure.TestResult result) {

        // [1] Nothing to show - no records
        if (records.isEmpty()) return;

        Schema.DescribeSObjectResult objectDescribe = records[0].getSObjectType().getDescribe();
        Map<String, Schema.SObjectField> fieldsByName = objectDescribe.fields.getMap();
        Map<String, AIToolsDataStructure.TestColumn> columnsByName = new Map<String, AIToolsDataStructure.TestColumn>();

        // [2] The lookup that points to a parent is left out when the parent itself is shown, because the platform fills it in without being asked. Every record of a query has the same parents
        Set<String> shownParentLookups = getShownParentLookups(fieldsByName, records[0].getPopulatedFieldsAsMap());

        for (SObject record : records) {

            // [3] Read each populated field, and the populated fields of each parent
            Map<String, Object> row = new Map<String, Object>();
            Map<String, Object> populatedFields = record.getPopulatedFieldsAsMap();

            for (String fieldName : populatedFields.keySet()) {

                if (fieldName == ID_FIELD || fieldName == ATTRIBUTES_KEY || shownParentLookups.contains(fieldName)) continue;

                Object fieldValue = populatedFields.get(fieldName);

                if (fieldValue instanceof SObject) {

                    SObject parentRecord = (SObject) fieldValue;
                    Map<String, Schema.SObjectField> parentFields = parentRecord.getSObjectType().getDescribe().fields.getMap();

                    for (String parentFieldName : parentRecord.getPopulatedFieldsAsMap().keySet()) {

                        if (parentFieldName == ID_FIELD || parentFieldName == ATTRIBUTES_KEY) continue;

                        String columnName = fieldName + PARENT_SEPARATOR + parentFieldName;
                        row.put(columnName, parentRecord.get(parentFieldName));
                        if (!columnsByName.containsKey(columnName)) columnsByName.put(columnName, buildColumn(columnName, parentFields.get(parentFieldName.toLowerCase())));
                    }

                } else if (!(fieldValue instanceof List<SObject>)) {

                    row.put(fieldName, fieldValue);
                    if (!columnsByName.containsKey(fieldName)) columnsByName.put(fieldName, buildColumn(fieldName, fieldsByName.get(fieldName.toLowerCase())));
                }
            }

            result.rows.add(row);
        }

        // [4] Keep the columns in the order they were found, and note the ones the PII Registry masks
        result.columns = columnsByName.values();
        String objectApiName = objectDescribe.getName();

        for (AIToolsDataStructure.TestColumn column : result.columns) {

            if (!column.apiName.contains(PARENT_SEPARATOR) && AIPiiFieldRegistry.isPii(objectApiName, column.apiName)) result.maskedFields.add(column.apiName);
        }
    }

    // The names of the lookup fields whose parent record is in the same row.
    private static Set<String> getShownParentLookups(Map<String, Schema.SObjectField> fieldsByName, Map<String, Object> populatedFields) {

        // [1] Find each parent that is in the row
        Set<String> shownParentLookups = new Set<String>();
        Set<String> parentNames = new Set<String>();

        for (String fieldName : populatedFields.keySet()) {

            if (populatedFields.get(fieldName) instanceof SObject) parentNames.add(fieldName.toLowerCase());
        }

        if (parentNames.isEmpty()) return shownParentLookups;

        // [2] Find the lookup field of each parent
        for (Schema.SObjectField field : fieldsByName.values()) {

            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            String relationshipName = fieldDescribe.getRelationshipName();
            if (relationshipName != null && parentNames.contains(relationshipName.toLowerCase())) shownParentLookups.add(fieldDescribe.getName());
        }

        return shownParentLookups;
    }

    // One column of the table, described from the field.
    private static AIToolsDataStructure.TestColumn buildColumn(String columnName, Schema.SObjectField field) {

        // [1] Describe it from the field, or plainly when the field cannot be found
        AIToolsDataStructure.TestColumn column = new AIToolsDataStructure.TestColumn();
        column.apiName = columnName;
        column.label = field == null ? columnName : field.getDescribe().getLabel();
        column.dataType = field == null ? 'string' : field.getDescribe().getType().name().toLowerCase();
        column.isRemoved = false;

        return column;
    }

    // Finds the fields the chosen user cannot read, takes their values out and records them. This checks field access from the user's permission sets; record sharing is not checked.
    private static void checkUserAccess(Id userId, List<SObject> records, AIToolsDataStructure.TestResult result) {

        // [1] Name the user being checked
        List<User> users = [SELECT Name FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
        if (users.isEmpty()) return;

        result.runAsName = users[0].Name;
        if (records.isEmpty()) return;

        // [2] Collect the permission sets of the user, including those inside a permission set group
        Set<Id> permissionSetIds = new Set<Id>();
        Set<Id> groupIds = new Set<Id>();

        for (PermissionSetAssignment assignment : [SELECT PermissionSetId, PermissionSetGroupId FROM PermissionSetAssignment WHERE AssigneeId = :userId WITH SYSTEM_MODE]) {

            permissionSetIds.add(assignment.PermissionSetId);
            if (assignment.PermissionSetGroupId != null) groupIds.add(assignment.PermissionSetGroupId);
        }

        for (PermissionSetGroupComponent component : [SELECT PermissionSetId FROM PermissionSetGroupComponent WHERE PermissionSetGroupId IN :groupIds WITH SYSTEM_MODE]) permissionSetIds.add(component.PermissionSetId);

        // [3] Find what the permission sets let the user read
        Schema.DescribeSObjectResult objectDescribe = records[0].getSObjectType().getDescribe();
        String objectApiName = objectDescribe.getName();
        Boolean canReadObject = !([SELECT Id FROM ObjectPermissions WHERE ParentId IN :permissionSetIds AND SobjectType = :objectApiName AND PermissionsRead = TRUE WITH SYSTEM_MODE LIMIT 1]).isEmpty();
        Set<String> readableFields = new Set<String>();

        for (FieldPermissions fieldPermission : [SELECT Field FROM FieldPermissions WHERE ParentId IN :permissionSetIds AND SobjectType = :objectApiName AND PermissionsRead = TRUE WITH SYSTEM_MODE]) readableFields.add(fieldPermission.Field.substringAfter(PARENT_SEPARATOR).toLowerCase());

        // [4] Take out each field the user cannot read
        Map<String, Schema.SObjectField> fieldsByName = objectDescribe.fields.getMap();

        for (AIToolsDataStructure.TestColumn column : result.columns) {

            if (column.apiName.contains(PARENT_SEPARATOR)) continue;

            Schema.SObjectField field = fieldsByName.get(column.apiName.toLowerCase());
            Boolean isHidden = !canReadObject || (field != null && field.getDescribe().isPermissionable() && !readableFields.contains(column.apiName.toLowerCase()));
            if (!isHidden) continue;

            column.isRemoved = true;
            result.removedFields.add(column.apiName);

            for (Map<String, Object> row : result.rows) row.put(column.apiName, null);
        }
    }

    // The reason a test failed, in words the admin can act on.
    private static String getFriendlyMessage(Exception ex) {

        // [1] The runner wraps the real reason, so show the reason
        String message = ex.getCause() == null ? ex.getMessage() : ex.getCause().getMessage();

        // [2] A query that ran too long reads better as advice
        Boolean isTimeout = message != null && (message.containsIgnoreCase('too long') || message.containsIgnoreCase('non-selective') || message.containsIgnoreCase('timeout'));

        return isTimeout ? Label.AI_Tools_Error_Timeout : message;
    }
}
