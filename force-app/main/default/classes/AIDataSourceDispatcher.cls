/*
Class Name: AIDataSourceDispatcher

=================================================================
=================================================================

Description: Runs a data source when the model calls it as a tool, and returns the masked result.

Step 1: Load the data source definition, only if it is active and assigned to the agent
Step 2: Check a bound data source has the record the chat is about
Step 3: Run the SOQL template, or the Apex class if it implements IAIDataSourceExecutor
Step 4: Flatten and mask the records and return them

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIDataSourceDispatcher {

    public class AIDataSourceExecutorException extends Exception {}

    // Data sources an admin may run for one transaction without them being given to the agent. Only the skill test on the AI Tools tab adds to it, after checking the user manages AI Assist, so an admin can test a skill before any agent has it.
    public static Set<Id> previewGrantedDataSourceIds = new Set<Id>();

    // Runs one data source for the model. recordId may be null for an unbound data source. The caller logs a failure: this class throws and does not.
    public static List<Object> runDataSource(Id dataSourceId, Id agentId, Id recordId, Map<String, Object> inputParameters, Id conversationId) {

        // [1] Refuse the call when there is no data source or no agent
        if (dataSourceId == null || agentId == null) throw new AIDataSourceExecutorException('A data source and an agent are required.');

        // [2] Load the definition in system mode, because the end user cannot read it, but only if it is active and assigned to this agent
        List<AIDataSource__c> dataSources = [SELECT Id, DeveloperName__c, SourceType__c, BindingType__c, SOQLTemplate__c, ApexClassName__c, MaxRows__c, InputSchema__c FROM AIDataSource__c WHERE Id = :dataSourceId AND IsActive__c = TRUE AND Id IN (SELECT AIDataSource__c FROM AIAgentDataSource__c WHERE AIAgent__c = :agentId AND IsActive__c = TRUE) WITH SYSTEM_MODE LIMIT 1];

        // [3] Not assigned directly, so load it when it reaches the agent through one of its active AI Skills, or an admin is testing a skill that holds it
        if (dataSources.isEmpty() && (previewGrantedDataSourceIds.contains(dataSourceId) || AISkillService.isDataSourceGrantedThroughSkill(dataSourceId, agentId))) dataSources = [SELECT Id, DeveloperName__c, SourceType__c, BindingType__c, SOQLTemplate__c, ApexClassName__c, MaxRows__c, InputSchema__c FROM AIDataSource__c WHERE Id = :dataSourceId AND IsActive__c = TRUE WITH SYSTEM_MODE LIMIT 1];

        // [4] Refuse with one message that does not say whether it was missing, inactive or assigned elsewhere
        if (dataSources.isEmpty()) throw new AIDataSourceExecutorException('The data source was not found, is not active, or is not assigned to this agent.');

        AIDataSource__c dataSource = dataSources[0];
        Map<String, Object> parameters = inputParameters == null ? new Map<String, Object>() : inputParameters;
        List<SObject> rawResults;

        // [5] A bound data source needs the record the chat is about
        if (dataSource.BindingType__c == AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND && recordId == null) {

            throw new AIDataSourceExecutorException('Data source "' + dataSource.DeveloperName__c + '" needs the record the conversation is about.');
        }

        if (dataSource.SourceType__c == AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL) {

            // [6] A SOQL source must have a template to run
            if (String.isBlank(dataSource.SOQLTemplate__c)) throw new AIDataSourceExecutorException('Data source "' + dataSource.DeveloperName__c + '" has no SOQL template.');

            // [7] Bind the inputs the data source declares, plus the record id when there is one, and run the template as the user
            Map<String, Object> bindValues = AIDataSourceInputBinder.getBindValues(dataSource.InputSchema__c, parameters);
            if (recordId != null) bindValues.put('recordId', recordId);

            rawResults = AISoqlTemplateRunner.runTemplate(dataSource.SOQLTemplate__c, bindValues, dataSource.MaxRows__c == null ? null : dataSource.MaxRows__c.intValue());
        } else if (dataSource.SourceType__c == AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX) {

            // [8] An Apex source must name a class to run
            if (String.isBlank(dataSource.ApexClassName__c)) throw new AIDataSourceExecutorException('Data source "' + dataSource.DeveloperName__c + '" has no Apex class.');

            // [9] Check the class implements the interface before any of its code runs, because the name was typed by a subscriber and even building the class runs its code. The empty namespace finds the subscriber's own classes; the one-argument form looks only in the package's namespace once this is managed code
            Type apexType = Type.forName('', dataSource.ApexClassName__c.trim());

            if (apexType == null || !IAIDataSourceExecutor.class.isAssignableFrom(apexType)) throw new AIDataSourceExecutorException('Apex class "' + dataSource.ApexClassName__c + '" was not found or does not implement IAIDataSourceExecutor.');

            // [10] Build the request that tells the class who is asking and for what
            AIDataSourceRequest request = new AIDataSourceRequest();
            request.recordId = recordId;
            request.inputParameters = AIDataSourceInputBinder.getBindValues(dataSource.InputSchema__c, parameters);
            request.conversationId = conversationId;
            request.agentId = agentId;
            request.userId = UserInfo.getUserId();
            request.dataSourceName = dataSource.DeveloperName__c;
            request.maxRows = dataSource.MaxRows__c == null ? null : dataSource.MaxRows__c.intValue();

            // [11] Run the class and take its records, treating no response as no records
            Object executor = apexType.newInstance();
            AIDataSourceResponse response = ((IAIDataSourceExecutor) executor).execute(request);
            rawResults = response == null ? new List<SObject>() : response.records;
        } else {

            // [12] Refuse a source type this class does not know
            throw new AIDataSourceExecutorException('Data source "' + dataSource.DeveloperName__c + '" has an unsupported source type.');
        }

        // [13] Flatten and mask the records before they reach the model
        return AIDataSourceResultProcessor.processResults(rawResults, conversationId);
    }
}
