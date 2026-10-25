/*
Class Name: AISkillServiceTest

=================================================================
=================================================================

Description: Testing utility for AI Skills at run time: loading an agent's skills for the open record, the data source and workflow action grants a skill gives, and the model picking a skill in the AI Agent Manager.

=================================================================
=================================================================
Applicable Classes:

AISkillService: Coverage TBC
AIAgentManager: Coverage TBC
AIDataSourceDispatcher: Coverage TBC
AIWorkflowActionDispatcher: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AISkillServiceTest {

    // testScenario1: An agent with an unbound skill, a skill bound to Account and an inactive skill -> on a Contact only the unbound skill is loaded, on an Account both active skills are.
    // testScenario2: A skill holding an active and an inactive data source and a workflow action -> the bundle holds the active data source and the action in order, and a null Id gives no bundle.
    // testScenario3: A data source and a workflow action held by a skill the agent has -> both are granted through the skill, and no longer once the agent's skill link is switched off.
    // testScenario4: The model picks a skill, then calls its data source -> the second request carries the skill's instructions and data source, the data source runs through the skill grant, and the result names the skill.
    // testScenario5: The model picks a skill that was not offered, and a turn has no skills -> the unknown pick changes nothing and is answered, and with no skills the skill tool is not offered.

    private static final String SOQL_TEMPLATE = 'SELECT Id, Name FROM Account WHERE Id = :recordId';

    // Plays back a script of responses, one per callout, and remembers what it was sent.
    private class ScriptedMock implements HttpCalloutMock {

        List<HttpResponse> script = new List<HttpResponse>();
        List<HttpRequest> requests = new List<HttpRequest>();

        public HttpResponse respond(HttpRequest request) {

            requests.add(request);
            return script.remove(0);
        }
    }

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an unbound data source and one bound to Account
            List<AIDataSource__c> dataSources = AIAssistTestDataFactory.createAIDataSources(2, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, false);
            dataSources[0].BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
            dataSources[1].BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
            dataSources[1].TargetObject__c = 'Account';
            insert dataSources;

            // [2] Create three skills: unbound, bound to Account, and one left inactive
            List<AISkill__c> skills = AIAssistTestDataFactory.createAISkills(3, true);
            AIAssistTestDataFactory.createAISkillTools(skills[0].Id, new List<AIDataSource__c>{ dataSources[0] }, null, true);
            AIAssistTestDataFactory.createAISkillTools(skills[1].Id, new List<AIDataSource__c>{ dataSources[1] }, null, true);
            AIAssistTestDataFactory.createAISkillTools(skills[2].Id, new List<AIDataSource__c>{ dataSources[0] }, null, true);
            skills[0].IsActive__c = true;
            skills[1].IsActive__c = true;
            update new List<AISkill__c>{ skills[0], skills[1] };

            // [3] Give all three to an agent
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIAssistTestDataFactory.createAIAgentSkills(agent.Id, skills, true);

            // [4] Load the skills on a Contact and on an Account
            Test.startTest();
                List<AISkillService.SkillBundle> contactSkills = AISkillService.getAssignedSkills(agent.Id, 'Contact');
                List<AISkillService.SkillBundle> accountSkills = AISkillService.getAssignedSkills(agent.Id, 'Account');
                List<AISkillService.SkillBundle> noAgentSkills = AISkillService.getAssignedSkills(null, 'Account');
            Test.stopTest();

            // [5] Check only the skills that fit the record were loaded
            Assert.areEqual(1, contactSkills.size(), 'Only the unbound skill should be offered on a Contact.');
            Assert.areEqual(skills[0].Id, contactSkills[0].skill.Id, 'The unbound skill should be offered on a Contact.');
            Assert.areEqual(2, accountSkills.size(), 'The unbound and the Account skill should be offered on an Account.');
            Assert.areEqual(0, noAgentSkills.size(), 'No agent should mean no skills.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a skill holding an active data source, an inactive data source and a workflow action
            List<AIDataSource__c> dataSources = AIAssistTestDataFactory.createAIDataSources(2, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, false);
            dataSources[1].IsActive__c = false;
            insert dataSources;
            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'Some_Flow', true)[0];
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            AIAssistTestDataFactory.createAISkillTools(skill.Id, dataSources, new List<AIWorkflowAction__c>{ action }, true);

            // [2] Load the skill by its Id, and with no Id
            Test.startTest();
                AISkillService.SkillBundle skillBundle = AISkillService.getSkillBundle(skill.Id);
                AISkillService.SkillBundle missingBundle = AISkillService.getSkillBundle(null);
            Test.stopTest();

            // [3] Check the bundle holds the active tools only
            Assert.areEqual(skill.Id, skillBundle.skill.Id, 'The bundle should hold the skill.');
            Assert.areEqual(1, skillBundle.dataSources.size(), 'Only the active data source should be in the bundle.');
            Assert.areEqual(dataSources[0].Id, skillBundle.dataSources[0].Id, 'The active data source should be in the bundle.');
            Assert.areEqual(1, skillBundle.workflowActions.size(), 'The workflow action should be in the bundle.');
            Assert.isNull(missingBundle, 'A null Id should give no bundle.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an active skill holding a data source and a workflow action, and give it to an agent
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, true)[0];
            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'Some_Flow', true)[0];
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            AIAssistTestDataFactory.createAISkillTools(skill.Id, new List<AIDataSource__c>{ dataSource }, new List<AIWorkflowAction__c>{ action }, true);
            skill.IsActive__c = true;
            update skill;
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIAgentSkill__c agentSkill = AIAssistTestDataFactory.createAIAgentSkills(agent.Id, new List<AISkill__c>{ skill }, true)[0];

            // [2] Ask for the grants, then switch the agent's skill link off and ask again
            Test.startTest();
                Boolean isDataSourceGranted = AISkillService.isDataSourceGrantedThroughSkill(dataSource.Id, agent.Id);
                Boolean isActionGranted = AISkillService.isWorkflowActionGrantedThroughSkill(action.Id, agent.Id);
                update new AIAgentSkill__c(Id = agentSkill.Id, IsActive__c = false);
                Boolean isDataSourceGrantedAfter = AISkillService.isDataSourceGrantedThroughSkill(dataSource.Id, agent.Id);
                Boolean isActionGrantedAfter = AISkillService.isWorkflowActionGrantedThroughSkill(action.Id, agent.Id);
            Test.stopTest();

            // [3] Check the grants follow the agent's skill link
            Assert.areEqual(true, isDataSourceGranted, 'The data source should be granted through the skill.');
            Assert.areEqual(true, isActionGranted, 'The workflow action should be granted through the skill.');
            Assert.areEqual(false, isDataSourceGrantedAfter, 'The data source should not be granted once the link is off.');
            Assert.areEqual(false, isActionGrantedAfter, 'The workflow action should not be granted once the link is off.');
            Assert.areEqual(false, AISkillService.isDataSourceGrantedThroughSkill(null, agent.Id), 'No data source should mean no grant.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Anthropic model, an agent, and a conversation about an account
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC;
            insert model;
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, false)[0];
            conversation.RelatedRecordId__c = String.valueOf(account.Id);
            conversation.RelatedObjectAPIName__c = 'Account';
            insert conversation;
            List<AIConversationMessage__c> history = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 1, false);

            // [2] Give the agent an active skill whose only data source reads the account. The data source is not linked to the agent directly
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, false)[0];
            dataSource.TargetObject__c = 'Account';
            insert dataSource;
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            AIAssistTestDataFactory.createAISkillTools(skill.Id, new List<AIDataSource__c>{ dataSource }, null, true);
            skill.Instructions__c = '1. Call @' + dataSource.DeveloperName__c + ' to read the account.';
            skill.IsActive__c = true;
            update skill;
            AIAssistTestDataFactory.createAIAgentSkills(agent.Id, new List<AISkill__c>{ skill }, true);
            List<AISkillService.SkillBundle> skills = AISkillService.getAssignedSkills(agent.Id, 'Account');

            // [3] Script the model picking the skill, calling its data source, then answering
            HttpResponse pickResponse = new HttpResponse();
            pickResponse.setStatusCode(200);
            pickResponse.setBody('{"content":[{"type":"tool_use","id":"toolu_1","name":"use_skill","input":{"skill":"' + skill.DeveloperName__c + '"}}],"usage":{"input_tokens":4,"output_tokens":2}}');

            HttpResponse toolResponse = new HttpResponse();
            toolResponse.setStatusCode(200);
            toolResponse.setBody('{"content":[{"type":"tool_use","id":"toolu_2","name":"' + dataSource.DeveloperName__c + '","input":{}}],"usage":{"input_tokens":4,"output_tokens":2}}');

            HttpResponse replyResponse = new HttpResponse();
            replyResponse.setStatusCode(200);
            replyResponse.setBody('{"content":[{"type":"text","text":' + JSON.serialize('Here is the account.') + '}],"usage":{"input_tokens":10,"output_tokens":5}}');

            ScriptedMock mock = new ScriptedMock();
            mock.script.add(pickResponse);
            mock.script.add(toolResponse);
            mock.script.add(replyResponse);
            Test.setMock(HttpCalloutMock.class, mock);

            AIAgentManager.AgentResult result;
            AIExecutionStepTracker trace = new AIExecutionStepTracker(conversation.Id, null, false, false);

            // [4] Run one turn with the skill offered and no data sources linked directly
            Test.startTest();
                result = AIAgentManager.executeAiMessage(agent, model, null, null, conversation, history, null, null, skills, 1, trace);
            Test.stopTest();

            // [5] Read back what was sent to the provider
            String firstBody = mock.requests[0].getBody();
            String secondBody = mock.requests[1].getBody();
            String thirdBody = mock.requests[2].getBody();

            // [6] Check the skill was offered, picked, its tool ran, and the result names it
            Assert.areEqual(true, result.isSuccessful, 'The turn should succeed after the skill is picked.');
            Assert.areEqual(3, mock.requests.size(), 'There should be three provider calls.');
            Assert.isTrue(firstBody.contains('use_skill') && firstBody.contains(skill.DeveloperName__c), 'The first request should offer the skill.');
            Assert.isFalse(firstBody.contains('"name":"' + dataSource.DeveloperName__c + '"'), 'The skill\'s data source should not be offered before the skill is picked.');
            Assert.isTrue(secondBody.contains('"name":"' + dataSource.DeveloperName__c + '"'), 'The second request should offer the skill\'s data source.');
            Assert.isTrue(secondBody.contains('to read the account'), 'The second request should carry the skill\'s instructions.');
            Assert.isTrue(thirdBody.contains('toolu_2') && !thirdBody.contains('This tool failed to run'), 'The data source should run through the skill grant and its result go back to the model.');
            Assert.areEqual(skill.Id, result.selectedSkillId, 'The result should name the skill.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Anthropic model, an agent, a conversation and an active unbound skill
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC;
            insert model;
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
            List<AIConversationMessage__c> history = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 1, false);
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, false)[0];
            dataSource.BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
            insert dataSource;
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            AIAssistTestDataFactory.createAISkillTools(skill.Id, new List<AIDataSource__c>{ dataSource }, null, true);
            skill.IsActive__c = true;
            update skill;
            AIAssistTestDataFactory.createAIAgentSkills(agent.Id, new List<AISkill__c>{ skill }, true);
            List<AISkillService.SkillBundle> skills = AISkillService.getAssignedSkills(agent.Id, null);

            // [2] Script the model picking a skill that was not offered, then answering, then a plain answer for the turn with no skills
            HttpResponse pickResponse = new HttpResponse();
            pickResponse.setStatusCode(200);
            pickResponse.setBody('{"content":[{"type":"tool_use","id":"toolu_1","name":"use_skill","input":{"skill":"Not_A_Skill"}}],"usage":{"input_tokens":4,"output_tokens":2}}');

            HttpResponse replyResponse = new HttpResponse();
            replyResponse.setStatusCode(200);
            replyResponse.setBody('{"content":[{"type":"text","text":' + JSON.serialize('Answered without a skill.') + '}],"usage":{"input_tokens":10,"output_tokens":5}}');

            HttpResponse plainResponse = new HttpResponse();
            plainResponse.setStatusCode(200);
            plainResponse.setBody('{"content":[{"type":"text","text":' + JSON.serialize('Plain answer.') + '}],"usage":{"input_tokens":10,"output_tokens":5}}');

            ScriptedMock mock = new ScriptedMock();
            mock.script.add(pickResponse);
            mock.script.add(replyResponse);
            mock.script.add(plainResponse);
            Test.setMock(HttpCalloutMock.class, mock);

            AIAgentManager.AgentResult unknownResult;
            AIAgentManager.AgentResult noSkillsResult;

            // [3] Run one turn with the skill offered, and one with no skills
            Test.startTest();
                unknownResult = AIAgentManager.executeAiMessage(agent, model, null, null, conversation, history, null, null, skills, 1, null);
                noSkillsResult = AIAgentManager.executeAiMessage(agent, model, null, null, conversation, history, null, null, 1, null);
            Test.stopTest();

            // [4] Read back what was sent to the provider
            String secondBody = mock.requests[1].getBody();
            String thirdBody = mock.requests[2].getBody();

            // [5] Check the unknown pick changed nothing, and no skill tool was offered without skills
            Assert.areEqual(true, unknownResult.isSuccessful, 'The turn should still be answered after an unknown pick.');
            Assert.isNull(unknownResult.selectedSkillId, 'An unknown pick should not name a skill.');
            Assert.isTrue(secondBody.contains('That is not one of the listed skills'), 'The model should be told the skill is not offered.');
            Assert.isFalse(secondBody.contains('"name":"' + dataSource.DeveloperName__c + '"'), 'No skill tool should be added after an unknown pick.');
            Assert.areEqual(true, noSkillsResult.isSuccessful, 'The turn with no skills should be answered.');
            Assert.isFalse(thirdBody.contains('use_skill'), 'With no skills the skill tool should not be offered.');
        }
    }
}
