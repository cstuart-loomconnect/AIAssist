/*
Class Name: AIDataSourceDispatcherTest

=================================================================
=================================================================

Description: Testing utility for AIDataSourceDispatcher: running a data source for the model only if it is active and assigned to the agent, as the user, and returning masked results.

=================================================================
=================================================================
Applicable Classes:

AIDataSourceDispatcher: Coverage TBC
IAIDataSourceExecutor: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIDataSourceDispatcherTest {

    // testScenario1: A SOQL data source assigned to the agent runs -> the flattened records are returned.
    // testScenario2: A data source that is inactive, missing or blank is run -> it is refused with one message that does not reveal which.
    // testScenario3: A data source assigned to a different agent is run -> it is refused as not assigned.
    // testScenario4: A bound data source is run with no record and an unbound one is run with no record -> the bound one is refused and the unbound one returns records.
    // testScenario5: Apex data sources are run -> the executor runs, and a class that is not an executor or does not exist is refused before any of its code runs.
    // testScenario6: A data source with a row cap is run -> only that many records reach the model.

    private static final String SOQL_ACCOUNT_BY_RECORD = 'SELECT Id, Name FROM Account WHERE Id = :recordId';
    private static final String SOQL_ACCOUNT_ALL = 'SELECT Id FROM Account';
    private static final String SOQL_ACCOUNT_ONE = 'SELECT Id FROM Account LIMIT 1';
    private static final String APEX_EXECUTOR = 'AIDataSourceDispatcherTest.NoRecordsExecutor';
    private static final String APEX_NOT_AN_EXECUTOR = 'AIDataSourceDispatcherTest.NotAnExecutor';
    private static final String APEX_MISSING = 'AIDataSourceDispatcherTest.DoesNotExist';

    private static Boolean wasNotAnExecutorConstructed = false;

    // Stands in for a subscriber's Apex data source.
    public class NoRecordsExecutor implements IAIDataSourceExecutor {
        public AIDataSourceResponse execute(AIDataSourceRequest request) {
            return new AIDataSourceResponse(new List<SObject>());
        }
    }

    // A class a subscriber named by mistake: it exists but is not an executor.
    public class NotAnExecutor {
        public NotAnExecutor() {
            AIDataSourceDispatcherTest.wasNotAnExecutorConstructed = true;
        }
    }

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Create an agent with a SOQL data source assigned and an account
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_ACCOUNT_BY_RECORD, true)[0];
        AIAssistTestDataFactory.createAIAgentDataSources(agent.Id, new List<AIDataSource__c>{ dataSource }, true);

        Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];

        List<Object> results;

        // [2] Run the data source for the account
        Test.startTest();
            results = AIDataSourceDispatcher.runDataSource(dataSource.Id, agent.Id, account.Id, null, null);
        Test.stopTest();

        // [3] Check the account was returned
        Assert.areEqual(1, results.size(), 'One record is returned.');
        Assert.areEqual(account.Id, ((Map<String, Object>) results[0]).get('Id'), 'It is the account the chat is about.');
    }

    @IsTest static void testScenario2() {

        // [1] Create an agent with an inactive source, a deleted source and a blank Id to run
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        List<AIDataSource__c> dataSources = AIAssistTestDataFactory.createAIDataSources(2, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_ACCOUNT_ALL, true);
        AIAssistTestDataFactory.createAIAgentDataSources(agent.Id, new List<AIDataSource__c>{ dataSources[0] }, true);
        dataSources[0].IsActive__c = false;
        update dataSources[0];

        Id deletedId = dataSources[1].Id;
        delete dataSources[1];

        List<String> messages = new List<String>();

        // [2] Run each data source and collect the refusals
        Test.startTest();
            for (Id dataSourceId : new List<Id>{ dataSources[0].Id, deletedId, null }) {
                try {
                    AIDataSourceDispatcher.runDataSource(dataSourceId, agent.Id, null, null, null);
                } catch (AIDataSourceDispatcher.AIDataSourceExecutorException ex) {
                    messages.add(ex.getMessage());
                }
            }
        Test.stopTest();

        // [3] Check each was refused with the same message
        Assert.areEqual(3, messages.size(), 'Each data source that cannot be run is refused.');
        Assert.isTrue(messages[0].contains('not found, is not active, or is not assigned'), 'An inactive source is refused without saying which of the three it is.');
        Assert.areEqual(messages[0], messages[1], 'A missing source gets the same message.');
        Assert.isTrue(messages[2].contains('required'), 'A blank Id is refused.');
    }

    @IsTest static void testScenario3() {

        // [1] Create two agents with the data source assigned to the first only
        AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];

        List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, model.Id, true);

        AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_ACCOUNT_ALL, true)[0];
        AIAssistTestDataFactory.createAIAgentDataSources(agents[0].Id, new List<AIDataSource__c>{ dataSource }, true);

        String message;

        // [2] Run the data source as the second agent
        Test.startTest();
            try {
                AIDataSourceDispatcher.runDataSource(dataSource.Id, agents[1].Id, null, null, null);
            } catch (AIDataSourceDispatcher.AIDataSourceExecutorException ex) {
                message = ex.getMessage();
            }
        Test.stopTest();

        // [3] Check it was refused as not assigned
        Assert.isNotNull(message, 'Another agents data source is refused.');
        Assert.isTrue(message.contains('not assigned'), 'The refusal covers assignment.');
    }

    @IsTest static void testScenario4() {

        // [1] Create an agent with a bound and an unbound data source and an account
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        List<AIDataSource__c> dataSources = AIAssistTestDataFactory.createAIDataSources(2, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_ACCOUNT_ONE, false);
        dataSources[0]
            .BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
        dataSources[1]
            .BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
        insert dataSources;
        AIAssistTestDataFactory.createAIAgentDataSources(agent.Id, dataSources, true);
        AIAssistTestDataFactory.createAccounts(1, true);

        String boundMessage;
        List<Object> unboundResults;

        // [2] Run both data sources with no record
        Test.startTest();
            try {
                AIDataSourceDispatcher.runDataSource(dataSources[0].Id, agent.Id, null, null, null);
            } catch (AIDataSourceDispatcher.AIDataSourceExecutorException ex) {
                boundMessage = ex.getMessage();
            }
            unboundResults = AIDataSourceDispatcher.runDataSource(dataSources[1].Id, agent.Id, null, null, null);
        Test.stopTest();

        // [3] Check the bound one was refused and the unbound one returned records
        Assert.isNotNull(boundMessage, 'A bound data source with no record is refused.');
        Assert.isTrue(boundMessage.contains('needs the record'), 'The bound source says what it needs.');
        Assert.areEqual(1, unboundResults.size(), 'The unbound source runs without a record.');
    }

    @IsTest static void testScenario5() {

        // [1] Create an agent with an executor, a non-executor and a missing Apex data source
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        List<AIDataSource__c> dataSources = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX, APEX_EXECUTOR, false);
        dataSources.addAll(AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX, APEX_NOT_AN_EXECUTOR, false));
        dataSources.addAll(AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX, APEX_MISSING, false));
        for (AIDataSource__c dataSource : dataSources)
            dataSource.BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
        insert dataSources;
        AIAssistTestDataFactory.createAIAgentDataSources(agent.Id, dataSources, true);

        List<Object> goodResults;
        List<String> refusals = new List<String>();

        // [2] Run each Apex data source and collect the refusals
        Test.startTest();
            goodResults = AIDataSourceDispatcher.runDataSource(dataSources[0].Id, agent.Id, null, null, null);

            for (Integer i = 1; i < 3; i++) {
                try {
                    AIDataSourceDispatcher.runDataSource(dataSources[i].Id, agent.Id, null, null, null);
                } catch (AIDataSourceDispatcher.AIDataSourceExecutorException ex) {
                    refusals.add(ex.getMessage());
                }
            }
        Test.stopTest();

        // [3] Check the executor ran and the other two were refused
        Assert.isTrue(goodResults.isEmpty(), 'The executor ran and returned no records.');
        Assert.areEqual(2, refusals.size(), 'Both classes that cannot be run are refused.');
        Assert.isTrue(refusals[0].contains('does not implement IAIDataSourceExecutor'), 'A class that does not implement the interface is refused.');
        Assert.isTrue(refusals[1].contains('was not found or does not implement'), 'A class that does not exist is refused the same way.');
        Assert.isFalse(wasNotAnExecutorConstructed, 'Not even the constructor of the refused class ran.');
    }

    @IsTest static void testScenario6() {

        // [1] Create an agent with a data source capped at five rows and twenty accounts
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_ACCOUNT_ALL, false)[0];
        dataSource.BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
        dataSource.MaxRows__c = 5;
        insert dataSource;
        AIAssistTestDataFactory.createAIAgentDataSources(agent.Id, new List<AIDataSource__c>{ dataSource }, true);
        AIAssistTestDataFactory.createAccounts(20, true);

        List<Object> results;

        // [2] Run the data source
        Test.startTest();
            results = AIDataSourceDispatcher.runDataSource(dataSource.Id, agent.Id, null, null, null);
        Test.stopTest();

        // [3] Check only five records were returned
        Assert.areEqual(5, results.size(), 'Only the first five records are given to the model.');
    }
}
