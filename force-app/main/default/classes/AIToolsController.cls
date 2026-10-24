/*
Class Name: AIToolsController

=================================================================
=================================================================

Description: The Apex controller behind the AI Tools tab.

Step 1: Read the data sources, the objects, fields and Apex classes the wizard offers, and the agents that use a data source
Step 2: Check a query and test a data source
Step 3: Save a data source
Step 4: Show an expected refusal as it is, and log anything unexpected once and show the generic label

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIToolsController {

    public class AIToolsControllerException extends Exception {}

    // The data sources for the list.
    @AuraEnabled
    public static List<AIToolsDataStructure.DataSourceRow> getDataSourceRows() {

        try {

            // [1] Do the work
            return AIToolsEditorService.getDataSourceRows();

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getDataSourceRows');
        }
    }

    // One data source with every field the wizard edits.
    @AuraEnabled
    public static AIToolsDataStructure.DataSourceDetail getDataSourceDetail(Id dataSourceId) {

        try {

            // [1] Do the work
            return AIToolsEditorService.getDataSourceDetail(dataSourceId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getDataSourceDetail');
        }
    }

    // The active agents a data source is switched on for.
    @AuraEnabled
    public static List<AIToolsDataStructure.AgentUse> getAgentUses(Id dataSourceId) {

        try {

            // [1] Do the work
            return AIToolsEditorService.getAgentUses(dataSourceId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getAgentUses');
        }
    }

    // The objects the query can read from.
    @AuraEnabled
    public static List<AIToolsDataStructure.ObjectOption> getObjectOptions() {

        try {

            // [1] Do the work
            return AIToolsEditorService.getObjectOptions();

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getObjectOptions');
        }
    }

    // The fields of an object the user can read.
    @AuraEnabled
    public static List<AIToolsDataStructure.FieldOption> getFieldOptions(String objectApiName) {

        try {

            // [1] Do the work
            return AIToolsEditorService.getFieldOptions(objectApiName);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getFieldOptions');
        }
    }

    // The Apex classes that implement IAIDataSourceExecutor.
    @AuraEnabled
    public static List<AIToolsDataStructure.ApexClassOption> getApexClassOptions() {

        try {

            // [1] Do the work
            return AIToolsEditorService.getApexClassOptions();

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getApexClassOptions');
        }
    }

    // The users whose name or username matches the text, for the Run as picker.
    @AuraEnabled
    public static List<AIAssistSettingsDataStructure.OwnerOption> findUsers(String searchText) {

        try {

            // [1] Do the work
            return AIToolsEditorService.findUsers(searchText);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'findUsers');
        }
    }

    // Checks a query and returns the problems with their fixes.
    @AuraEnabled
    public static AIToolsDataStructure.SoqlValidation validateSoql(String soql, Boolean isBound, Integer maxRows) {

        try {

            // [1] Do the work
            return AIToolsEditorService.validateSoql(soql, isBound, maxRows);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'validateSoql');
        }
    }

    // Tests a data source definition, saved or not, and reports what the agent would get.
    @AuraEnabled
    public static AIToolsDataStructure.TestResult runTest(Map<String, Object> dataSourceDetail, Map<String, Object> testRequest) {

        try {

            // [1] Do the work
            return AIToolsEditorService.runTest(buildDataSourceDetail(dataSourceDetail), buildTestRequest(testRequest));

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'runTest');
        }
    }

    // Saves a data source, testing it first when a test request comes with it. A change to a data source that agents use is not saved when its test fails.
    @AuraEnabled
    public static AIToolsDataStructure.SaveResult saveDataSource(Map<String, Object> dataSourceDetail, Map<String, Object> testRequest) {

        try {

            // [1] Do the work
            return AIToolsEditorService.saveDataSource(buildDataSourceDetail(dataSourceDetail), buildTestRequest(testRequest));

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'saveDataSource');
        }
    }

    // Reads the data source the tab sent as plain values. The tab sends plain values because the platform did not fill in a class passed straight from the page.
    private static AIToolsDataStructure.DataSourceDetail buildDataSourceDetail(Map<String, Object> values) {

        // [1] No values mean no data source
        if (values == null) return null;

        // [2] Read the values into the class
        return (AIToolsDataStructure.DataSourceDetail) JSON.deserialize(JSON.serialize(values), AIToolsDataStructure.DataSourceDetail.class);
    }

    // Reads the test request the tab sent as plain values.
    private static AIToolsDataStructure.TestRequest buildTestRequest(Map<String, Object> values) {

        // [1] No values mean no test request
        if (values == null) return null;

        // [2] Read the values into the class one by one, because JSON.deserialize cannot fill a Map of Object
        AIToolsDataStructure.TestRequest testRequest = new AIToolsDataStructure.TestRequest();
        Object recordId = values.get('recordId');
        Object runAsUserId = values.get('runAsUserId');
        Object inputValues = values.get('inputValues');

        if (recordId != null && String.isNotBlank(String.valueOf(recordId))) testRequest.recordId = Id.valueOf(String.valueOf(recordId));
        if (runAsUserId != null && String.isNotBlank(String.valueOf(runAsUserId))) testRequest.runAsUserId = Id.valueOf(String.valueOf(runAsUserId));
        if (inputValues instanceof Map<String, Object>) testRequest.inputValues = (Map<String, Object>) inputValues;

        return testRequest;
    }

    // Shows a package refusal as it is, which is already a Custom Label, and logs anything else once so the tab gets the generic label.
    private static AuraHandledException buildAuraException(Exception ex, String methodName) {

        // [1] Choose the text
        String errorText = Label.AI_Error_Generic;
        if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
        else AIPlatformLogManager.logException(ex, 'AIToolsController', methodName);

        // [2] Build the exception the tab can read
        AuraHandledException auraException = new AuraHandledException(errorText);
        auraException.setMessage(errorText);

        return auraException;
    }
}
