/*
Class Name: AIChatContextServiceTest

=================================================================
=================================================================

Description: Testing utility for AIChatContextService: the record strip and the agents offered for it.

=================================================================
=================================================================
Applicable Classes:

AIChatContextService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIChatContextServiceTest {

    // testScenario1: A record gives its object labels and name, and a blank or invalid Id gives no context.
    // testScenario2: An object covered by a synced, active PII registry is marked protected.
    // testScenario3: Agents for the object come before general agents, inactive agents and agents for another object are left out.
    // testScenario4: An Assigned Users Only agent is offered only to an assigned user.
    // testScenario5: selectAgent takes a 15 or 18 character Id or a Developer Name, and falls back to the first agent.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Create an account
        Account record = AIAssistTestDataFactory.createAccounts(1, true)[0];

        // [2] Build the record context for a valid, blank and invalid Id
        AIChatDataStructure.RecordContext context;
        AIChatDataStructure.RecordContext blank;
        AIChatDataStructure.RecordContext invalid;

        Test.startTest();
            context = AIChatContextService.buildRecordContext(String.valueOf(record.Id), null);
            blank = AIChatContextService.buildRecordContext(null, null);
            invalid = AIChatContextService.buildRecordContext('not an id', null);
        Test.stopTest();

        // [3] Check the three contexts
        Assert.areEqual('Account', context.objectApiName, 'The context should name the record\'s object.');
        Assert.areEqual('Accounts', context.objectLabelPlural, 'The context should carry the plural label.');
        Assert.areEqual(record.Name, context.recordName, 'The context should carry the record name.');
        Assert.isFalse(context.piiProtected, 'An object with no PII registry should not be protected.');

        Assert.isNull(blank.recordId, 'A blank Id should give no context.');
        Assert.isNull(invalid.recordId, 'An invalid Id should give no context.');
    }

    @IsTest static void testScenario2() {

        // [1] Create an account and an active, synced PII registry for it
        Account record = AIAssistTestDataFactory.createAccounts(1, true)[0];

        AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, 'Account', false)[0];
        registry.IsActive__c = true;
        registry.SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED;
        insert registry;

        // [2] Build the record context
        AIChatDataStructure.RecordContext context;

        Test.startTest();
            context = AIChatContextService.buildRecordContext(String.valueOf(record.Id), 'Account');
        Test.stopTest();

        // [3] Check the object is protected
        Assert.isTrue(context.piiProtected, 'An object with a synced, active PII registry should be protected.');
    }

    @IsTest static void testScenario3() {

        // [1] Create general, Account, Contact and inactive agents
        AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
        List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(4, model.Id, false);
        for (AIAgent__c agent : agents)
        agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;

        agents[0].Name = 'A General';
        agents[1].Name = 'B Account';
        agents[2].Name = 'C Contact';

        agents[3].IsActive__c = false;

        agents[1].ObjectApiNames__c = 'Account';
        agents[2].ObjectApiNames__c = 'Contact';

        insert agents;

        // [2] Get the agents available for Account
        List<AIChatDataStructure.AgentOption> options;

        Test.startTest();
            options = AIChatContextService.getAvailableAgents('Account');
        Test.stopTest();

        // [3] Check which agents are offered and in what order
        Assert.areEqual(2, options.size(), 'Only the Account agent and the general agent should be offered.');
        Assert.areEqual('B Account', options[0].name, 'The agent for the object should come first.');
        Assert.areEqual('A General', options[1].name, 'The general agent should come after.');
    }

    @IsTest static void testScenario4() {

        // [1] Create an Assigned Users Only agent
        AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];

        AIAgent__c closed = AIAssistTestDataFactory.createAIAgents(1, model.Id, false)[0];
        closed.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
        insert closed;

        // [2] Check the agent is not offered while the user is unassigned
        Assert.areEqual(0, AIChatContextService.getAvailableAgents(null).size(), 'An Assigned Users Only agent should not be offered while the user is unassigned.');

        // [3] Assign the current user to the agent
        AIAssistTestDataFactory.createAIAgentAssignments(closed.Id, new List<User>{ new User(Id = UserInfo.getUserId()) }, null, true);

        // [4] Get the available agents
        List<AIChatDataStructure.AgentOption> after;

        Test.startTest();
            after = AIChatContextService.getAvailableAgents(null);
        Test.stopTest();

        // [5] Check the agent is offered
        Assert.areEqual(1, after.size(), 'An Assigned Users Only agent should be offered once the user is assigned.');
    }

    @IsTest static void testScenario5() {

        // [1] Create two agents open to all users
        AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
        List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, model.Id, false);
        for (AIAgent__c agent : agents)
        agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;

        agents[0].Name = 'First';
        agents[1].Name = 'Second';

        insert agents;

        // [2] Get the available agents and the second agent's developer name
        List<AIChatDataStructure.AgentOption> options = AIChatContextService.getAvailableAgents(null);
        String secondDeveloperName = [SELECT DeveloperName__c FROM AIAgent__c WHERE Id = :agents[1].Id].DeveloperName__c;

        // [3] Select an agent by each kind of key
        AIChatDataStructure.AgentOption byId;
        AIChatDataStructure.AgentOption byShortId;
        AIChatDataStructure.AgentOption byName;
        AIChatDataStructure.AgentOption fallback;
        AIChatDataStructure.AgentOption none;

        Test.startTest();
            byId = AIChatContextService.selectAgent(options, String.valueOf(agents[1].Id));
            byShortId = AIChatContextService.selectAgent(options, String.valueOf(agents[1].Id).left(15));
            byName = AIChatContextService.selectAgent(options, secondDeveloperName);
            fallback = AIChatContextService.selectAgent(options, 'nothing');
            none = AIChatContextService.selectAgent(new List<AIChatDataStructure.AgentOption>(), 'x');
        Test.stopTest();

        // [4] Check each selection
        Assert.areEqual(agents[1].Id, byId.id, 'An 18 character Id should pick its agent.');
        Assert.areEqual(agents[1].Id, byShortId.id, 'A 15 character Id should pick its agent.');
        Assert.areEqual(agents[1].Id, byName.id, 'A Developer Name should pick its agent.');

        Assert.areEqual(agents[0].Id, fallback.id, 'An unknown key should fall back to the first agent.');
        Assert.isNull(none, 'No agents should give no selection.');
    }
}
