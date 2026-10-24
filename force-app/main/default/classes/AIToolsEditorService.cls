/*
Class Name: AIToolsEditorService

=================================================================
=================================================================

Description: Reads, checks, tests and saves the data sources that the AI Tools tab edits.

Step 1: Read the list of data sources, and one data source with every field the wizard edits
Step 2: Offer the objects, fields and Apex classes the wizard lets the admin pick from
Step 3: Check a query, and test a data source as the admin or as another user
Step 4: Save a data source, refusing a change to one that agents use when its test fails
Step 5: Refuse anyone who does not hold the Manage Settings custom permission

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIToolsEditorService {

    public class AIToolsEditorServiceException extends Exception {}

    private static final Pattern DEVELOPER_NAME_PATTERN = Pattern.compile('^[A-Za-z][A-Za-z0-9_]*$');
    private static final Set<String> HIDDEN_FIELD_TYPES = new Set<String>{'address', 'location', 'base64', 'anytype', 'complexvalue', 'encryptedstring'};

    // Every data source for the list, newest changes last, with the number of active agents each is switched on for.
    public static List<AIToolsDataStructure.DataSourceRow> getDataSourceRows() {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Read the data sources and count the active agents of each
        List<AIDataSource__c> dataSources = [SELECT Id, SourceName__c, DeveloperName__c, SourceType__c, TargetObject__c, BindingType__c, MaxRows__c, IsActive__c, LastTestStatus__c, LastTestedOn__c FROM AIDataSource__c WITH SYSTEM_MODE ORDER BY SourceName__c LIMIT :AIAssistApplicationConstants.TOOLS_LIST_MAX_RESULTS];
        Map<Id, Integer> agentCountByDataSourceId = getAgentCounts();

        // [3] Build one row per data source
        List<AIToolsDataStructure.DataSourceRow> rows = new List<AIToolsDataStructure.DataSourceRow>();

        for (AIDataSource__c dataSource : dataSources) {

            rows.add(buildRow(dataSource, agentCountByDataSourceId.get(dataSource.Id)));
        }

        return rows;
    }

    // One data source with every field the wizard edits.
    public static AIToolsDataStructure.DataSourceDetail getDataSourceDetail(Id dataSourceId) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Read it and build the detail
        AIDataSource__c dataSource = findDataSource(dataSourceId);
        AIToolsDataStructure.DataSourceDetail detail = new AIToolsDataStructure.DataSourceDetail();
        detail.dataSourceId = dataSource.Id;
        detail.sourceName = dataSource.SourceName__c;
        detail.developerName = dataSource.DeveloperName__c;
        detail.description = dataSource.Description__c;
        detail.outputDescription = dataSource.OutputDescription__c;
        detail.sourceType = dataSource.SourceType__c;
        detail.bindingType = dataSource.BindingType__c;
        detail.targetObject = dataSource.TargetObject__c;
        detail.maxRows = dataSource.MaxRows__c;
        detail.soqlTemplate = dataSource.SOQLTemplate__c;
        detail.apexClassName = dataSource.ApexClassName__c;
        detail.inputSchema = dataSource.InputSchema__c;
        detail.isActive = dataSource.IsActive__c;
        detail.lastTestStatus = dataSource.LastTestStatus__c;
        detail.lastTestedOn = dataSource.LastTestedOn__c;
        detail.agentCount = getAgentUses(dataSource.Id).size();

        return detail;
    }

    // The active agents a data source is switched on for, by name.
    public static List<AIToolsDataStructure.AgentUse> getAgentUses(Id dataSourceId) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Read the agents, once each
        List<AIToolsDataStructure.AgentUse> agentUses = new List<AIToolsDataStructure.AgentUse>();
        Set<Id> seenAgentIds = new Set<Id>();

        for (AIAgentDataSource__c link : [SELECT AIAgent__c, AIAgent__r.Name FROM AIAgentDataSource__c WHERE AIDataSource__c = :dataSourceId AND IsActive__c = TRUE AND AIAgent__r.IsActive__c = TRUE WITH SYSTEM_MODE ORDER BY AIAgent__r.Name LIMIT :AIAssistApplicationConstants.TOOLS_LIST_MAX_RESULTS]) {

            if (!seenAgentIds.add(link.AIAgent__c)) continue;

            AIToolsDataStructure.AgentUse agentUse = new AIToolsDataStructure.AgentUse();
            agentUse.agentId = link.AIAgent__c;
            agentUse.agentName = link.AIAgent__r.Name;
            agentUses.add(agentUse);
        }

        return agentUses;
    }

    // The objects the user can query, by label.
    public static List<AIToolsDataStructure.ObjectOption> getObjectOptions() {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Keep the objects the user can read and query
        List<AIToolsDataStructure.ObjectOption> options = new List<AIToolsDataStructure.ObjectOption>();

        for (Schema.SObjectType objectType : Schema.getGlobalDescribe().values()) {

            Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();
            if (!objectDescribe.isAccessible() || !objectDescribe.isQueryable() || objectDescribe.isCustomSetting()) continue;

            AIToolsDataStructure.ObjectOption option = new AIToolsDataStructure.ObjectOption();
            option.apiName = objectDescribe.getName();
            option.label = objectDescribe.getLabel();
            options.add(option);
        }

        // [3] Put them in label order
        List<String> sortKeys = new List<String>();
        Map<String, AIToolsDataStructure.ObjectOption> optionBySortKey = new Map<String, AIToolsDataStructure.ObjectOption>();

        for (AIToolsDataStructure.ObjectOption option : options) {

            String sortKey = option.label.toLowerCase() + '|' + option.apiName;
            sortKeys.add(sortKey);
            optionBySortKey.put(sortKey, option);
        }

        sortKeys.sort();
        List<AIToolsDataStructure.ObjectOption> sortedOptions = new List<AIToolsDataStructure.ObjectOption>();

        for (String sortKey : sortKeys) sortedOptions.add(optionBySortKey.get(sortKey));

        return sortedOptions;
    }

    // The fields of an object the user can read, by label. Id is left out because the query always selects it.
    public static List<AIToolsDataStructure.FieldOption> getFieldOptions(String objectApiName) {

        // [1] Refuse a user who may not use the tab, and an object that does not exist
        AIAssistSettingsEditorService.requireManager();
        Schema.SObjectType objectType = String.isBlank(objectApiName) ? null : Schema.getGlobalDescribe().get(objectApiName.toLowerCase());
        if (objectType == null || !objectType.getDescribe().isAccessible()) throw new AIToolsEditorServiceException(Label.AI_Tools_Error_Object);

        // [2] Keep the fields the user can read and a query can select
        List<String> sortKeys = new List<String>();
        Map<String, AIToolsDataStructure.FieldOption> optionBySortKey = new Map<String, AIToolsDataStructure.FieldOption>();

        for (Schema.SObjectField field : objectType.getDescribe().fields.getMap().values()) {

            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            String dataType = fieldDescribe.getType().name().toLowerCase();
            if (!fieldDescribe.isAccessible() || fieldDescribe.getName() == 'Id' || HIDDEN_FIELD_TYPES.contains(dataType)) continue;

            AIToolsDataStructure.FieldOption option = new AIToolsDataStructure.FieldOption();
            option.apiName = fieldDescribe.getName();
            option.label = fieldDescribe.getLabel();
            option.dataType = dataType;
            option.referenceTo = fieldDescribe.getReferenceTo().isEmpty() ? null : fieldDescribe.getReferenceTo()[0].getDescribe().getName();

            String sortKey = option.label.toLowerCase() + '|' + option.apiName;
            sortKeys.add(sortKey);
            optionBySortKey.put(sortKey, option);
        }

        // [3] Put them in label order
        sortKeys.sort();
        List<AIToolsDataStructure.FieldOption> options = new List<AIToolsDataStructure.FieldOption>();

        for (String sortKey : sortKeys) options.add(optionBySortKey.get(sortKey));

        return options;
    }

    // The Apex classes that implement IAIDataSourceExecutor, with the inputs each describes when it also implements IAIDataSourceInputDescriber.
    public static List<AIToolsDataStructure.ApexClassOption> getApexClassOptions() {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Find the concrete classes that implement the interface
        List<AIToolsDataStructure.ApexClassOption> options = new List<AIToolsDataStructure.ApexClassOption>();

        for (ApexTypeImplementor implementor : [SELECT ClassName, ClassNamespacePrefix, ApexClass.ApiVersion FROM ApexTypeImplementor WHERE InterfaceName = :AIAssistApplicationConstants.TOOLS_DATA_SOURCE_INTERFACE AND IsConcrete = TRUE WITH SYSTEM_MODE ORDER BY ClassName LIMIT :AIAssistApplicationConstants.TOOLS_LIST_MAX_RESULTS]) {

            AIToolsDataStructure.ApexClassOption option = new AIToolsDataStructure.ApexClassOption();
            option.className = implementor.ClassName;
            option.namespacePrefix = implementor.ClassNamespacePrefix;
            option.apiVersion = implementor.ApexClass.ApiVersion;
            setDeclaredInputs(option);
            options.add(option);
        }

        return options;
    }

    // Users the admin can run a test as.
    public static List<AIAssistSettingsDataStructure.OwnerOption> findUsers(String searchText) {

        // [1] The settings tab already knows how to search users
        return AIAssistSettingsEditorService.findOwners(AIAssistApplicationConstants.SETTINGS_SCOPE_USER, searchText);
    }

    // Checks a query.
    public static AIToolsDataStructure.SoqlValidation validateSoql(String soql, Boolean isBound, Integer maxRows) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Check it
        return AISoqlTemplateValidator.validate(soql, isBound, maxRows);
    }

    // Tests a definition, saved or not.
    public static AIToolsDataStructure.TestResult runTest(AIToolsDataStructure.DataSourceDetail detail, AIToolsDataStructure.TestRequest request) {

        // [1] Refuse a user who may not use the tab, and a definition with nothing to run
        AIAssistSettingsEditorService.requireManager();
        if (detail == null) throw new AIToolsEditorServiceException(Label.AI_Tools_Error_Not_Found);

        // [2] Run it
        return AIDataSourceTestService.runTest(detail, request);
    }

    // Saves a data source, creating it when it has no id. When a test request comes with it the data source is tested first, and a change to a data source that agents use is not saved when the test fails.
    public static AIToolsDataStructure.SaveResult saveDataSource(AIToolsDataStructure.DataSourceDetail detail, AIToolsDataStructure.TestRequest request) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();
        validateDetail(detail);

        // [2] Find the data source, or start a new one, and see how many agents use it
        AIDataSource__c record = detail.dataSourceId == null ? new AIDataSource__c() : findDataSource(detail.dataSourceId);
        Integer agentCount = record.Id == null ? 0 : getAgentUses(record.Id).size();

        // [3] A data source that agents use must be tested before a change goes live
        AIToolsDataStructure.SaveResult saveResult = new AIToolsDataStructure.SaveResult();
        if (agentCount > 0 && request == null) throw new AIToolsEditorServiceException(Label.AI_Tools_Error_Test_Required);

        if (request != null) saveResult.testResult = AIDataSourceTestService.runTest(detail, request);

        if (agentCount > 0 && saveResult.testResult.status == AIAssistApplicationConstants.TOOLS_TEST_STATUS_FAILED) {

            saveResult.isSaved = false;
            return saveResult;
        }

        // [4] Put the values on the record
        record.SourceName__c = detail.sourceName.trim();
        record.DeveloperName__c = detail.developerName.trim();
        record.Description__c = detail.description;
        record.OutputDescription__c = detail.outputDescription;
        record.SourceType__c = detail.sourceType;
        record.BindingType__c = detail.bindingType;
        record.MaxRows__c = detail.maxRows;
        record.InputSchema__c = detail.inputSchema;
        record.IsActive__c = detail.isActive == true;
        record.LastTestStatus__c = saveResult.testResult == null ? null : saveResult.testResult.status;
        record.LastTestedOn__c = saveResult.testResult == null ? null : Datetime.now();
        setSourceFields(record, detail);

        // [5] Save it and read it back
        try {

            upsert record;

        } catch (DmlException ex) {

            throw new AIToolsEditorServiceException(ex.getDmlMessage(0), ex);
        }

        saveResult.isSaved = true;
        saveResult.row = buildRow(findDataSource(record.Id), agentCount);

        return saveResult;
    }

    // Puts the SOQL or Apex fields on the record, and clears the other so the data source only ever holds one.
    private static void setSourceFields(AIDataSource__c record, AIToolsDataStructure.DataSourceDetail detail) {

        // [1] A SOQL data source: the query must be free of errors, and the object comes from it
        if (detail.sourceType == AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL) {

            Boolean isBound = detail.bindingType == AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
            AIToolsDataStructure.SoqlValidation validation = AISoqlTemplateValidator.validate(detail.soqlTemplate, isBound, detail.maxRows == null ? null : detail.maxRows.intValue());
            if (!validation.isValid) throw new AIToolsEditorServiceException(Label.AI_Tools_Error_Query_Invalid);

            record.SOQLTemplate__c = detail.soqlTemplate.trim();
            record.TargetObject__c = validation.objectApiName;
            record.ApexClassName__c = null;
            return;
        }

        // [2] An Apex data source: the class must be named, and the admin may say which object it returns
        record.ApexClassName__c = detail.apexClassName.trim();
        record.TargetObject__c = detail.targetObject;
        record.SOQLTemplate__c = null;
    }

    // Refuses a data source that is missing something every data source needs.
    private static void validateDetail(AIToolsDataStructure.DataSourceDetail detail) {

        // [1] Name, API name and type
        if (detail == null || String.isBlank(detail.sourceName) || String.isBlank(detail.description)) throw new AIToolsEditorServiceException(Label.AI_Tools_Error_Name_Required);
        if (String.isBlank(detail.developerName) || !DEVELOPER_NAME_PATTERN.matcher(detail.developerName.trim()).matches()) throw new AIToolsEditorServiceException(Label.AI_Tools_Error_Developer_Name);

        Boolean isKnownType = detail.sourceType == AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL || detail.sourceType == AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX;
        if (!isKnownType) throw new AIToolsEditorServiceException(Label.AI_Tools_Error_Source_Type);

        // [2] The query or the class
        if (detail.sourceType == AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL && String.isBlank(detail.soqlTemplate)) throw new AIToolsEditorServiceException(Label.AI_Tools_Error_No_Template);
        if (detail.sourceType == AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX && String.isBlank(detail.apexClassName)) throw new AIToolsEditorServiceException(Label.AI_Tools_Error_Apex_Class);
    }

    // Asks a class that implements the describer interface for its inputs. A class that does not, or that fails, simply declares none.
    private static void setDeclaredInputs(AIToolsDataStructure.ApexClassOption option) {

        // [1] Only a class that also implements the describer interface can be asked
        try {

            Type apexType = Type.forName(option.namespacePrefix == null ? '' : option.namespacePrefix, option.className);
            if (apexType == null || !IAIDataSourceInputDescriber.class.isAssignableFrom(apexType)) return;

            // [2] Read the schema it returns and list the input names
            String inputSchema = ((IAIDataSourceInputDescriber) apexType.newInstance()).describeInputs();
            if (String.isBlank(inputSchema)) return;

            Map<String, Object> schema = (Map<String, Object>) JSON.deserializeUntyped(inputSchema);
            Object properties = schema.get('properties');
            if (!(properties instanceof Map<String, Object>)) return;

            option.declaredInputSchema = inputSchema;
            option.declaredInputNames = String.join(new List<String>(((Map<String, Object>) properties).keySet()), ', ');

        } catch (Exception ex) {

            option.declaredInputSchema = null;
            option.declaredInputNames = null;
        }
    }

    // The number of active agents each data source is switched on for.
    private static Map<Id, Integer> getAgentCounts() {

        // [1] Collect the agents of each data source once
        Map<Id, Set<Id>> agentIdsByDataSourceId = new Map<Id, Set<Id>>();

        for (AIAgentDataSource__c link : [SELECT AIDataSource__c, AIAgent__c FROM AIAgentDataSource__c WHERE IsActive__c = TRUE AND AIAgent__r.IsActive__c = TRUE WITH SYSTEM_MODE LIMIT 50000]) {

            if (!agentIdsByDataSourceId.containsKey(link.AIDataSource__c)) agentIdsByDataSourceId.put(link.AIDataSource__c, new Set<Id>());
            agentIdsByDataSourceId.get(link.AIDataSource__c).add(link.AIAgent__c);
        }

        // [2] Count them
        Map<Id, Integer> agentCountByDataSourceId = new Map<Id, Integer>();

        for (Id dataSourceId : agentIdsByDataSourceId.keySet()) agentCountByDataSourceId.put(dataSourceId, agentIdsByDataSourceId.get(dataSourceId).size());

        return agentCountByDataSourceId;
    }

    // Reads one data source.
    private static AIDataSource__c findDataSource(Id dataSourceId) {

        // [1] Read it, or say it is gone
        List<AIDataSource__c> dataSources = [SELECT Id, SourceName__c, DeveloperName__c, Description__c, OutputDescription__c, SourceType__c, BindingType__c, TargetObject__c, MaxRows__c, SOQLTemplate__c, ApexClassName__c, InputSchema__c, IsActive__c, LastTestStatus__c, LastTestedOn__c FROM AIDataSource__c WHERE Id = :dataSourceId WITH SYSTEM_MODE LIMIT 1];
        if (dataSources.isEmpty()) throw new AIToolsEditorServiceException(Label.AI_Tools_Error_Not_Found);

        return dataSources[0];
    }

    // Builds one list row.
    private static AIToolsDataStructure.DataSourceRow buildRow(AIDataSource__c dataSource, Integer agentCount) {

        // [1] Copy the fields the list shows
        AIToolsDataStructure.DataSourceRow row = new AIToolsDataStructure.DataSourceRow();
        row.dataSourceId = dataSource.Id;
        row.sourceName = dataSource.SourceName__c;
        row.developerName = dataSource.DeveloperName__c;
        row.sourceType = dataSource.SourceType__c;
        row.targetObject = dataSource.TargetObject__c;
        row.bindingType = dataSource.BindingType__c;
        row.maxRows = dataSource.MaxRows__c;
        row.isActive = dataSource.IsActive__c;
        row.lastTestStatus = dataSource.LastTestStatus__c;
        row.lastTestedOn = dataSource.LastTestedOn__c;
        row.agentCount = agentCount == null ? 0 : agentCount;

        return row;
    }
}
