/*
Class Name: AIToolsSkillTestServiceTest

=================================================================
=================================================================

Description: Testing utility for the AI Tools Skill Test Service: asking an agent's model one question with an unsaved or saved skill offered on its own, and how the test is reported.

=================================================================
=================================================================
Applicable Classes:

AIToolsSkillTestService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIToolsSkillTestServiceTest {

    // testScenario1: The model picks a saved skill, calls its data source and answers -> the test passes, the steps include the skill and the data source, and the skill keeps the result.
    // testScenario2: The model answers without picking the skill -> the test is Not Picked with the reason.
    // testScenario3: The provider refuses the request -> the test fails with the run failed message.
    // testScenario4: A test with no agent, no question, or a bound skill and no record -> each is refused with its message.

    private static final String SOQL_TEMPLATE = 'SELECT Id, Name FROM Account WHERE Id = :recordId';
    private static final String VALID_DESCRIPTION = 'Use this skill when the user asks for a summary of the open account and its recent activity.';

    // Plays back a script of responses, one per callout.
    private class ScriptedMock implements HttpCalloutMock {

        List<HttpResponse> script = new List<HttpResponse>();

        public HttpResponse respond(HttpRequest request) {

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
            // [1] Create an agent, an account, and a saved inactive skill whose data source reads the account. No agent has the skill
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, false)[0];
            dataSource.BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
            dataSource.TargetObject__c = 'Account';
            insert dataSource;
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];

            AIToolsSkillDataStructure.SkillTool tool = new AIToolsSkillDataStructure.SkillTool();
            tool.kind = AIAssistApplicationConstants.SKILL_TOOL_KIND_DATA_SOURCE;
            tool.recordId = dataSource.Id;
            AIToolsSkillDataStructure.SkillDetail detail = new AIToolsSkillDataStructure.SkillDetail();
            detail.skillId = skill.Id;
            detail.skillName = skill.Name;
            detail.developerName = skill.DeveloperName__c;
            detail.description = VALID_DESCRIPTION;
            detail.instructions = '1. Call @' + dataSource.DeveloperName__c + '.';
            detail.tools = new List<AIToolsSkillDataStructure.SkillTool>{ tool };
            AIToolsSkillDataStructure.TestRequest testRequest = new AIToolsSkillDataStructure.TestRequest();
            testRequest.agentId = agent.Id;
            testRequest.recordId = account.Id;
            testRequest.question = 'Summarise this account.';

            // [2] Script the model picking the skill, calling its data source, then answering
            HttpResponse pickResponse = new HttpResponse();
            pickResponse.setStatusCode(200);
            pickResponse.setBody('{"content":[{"type":"tool_use","id":"toolu_1","name":"use_skill","input":{"skill":"' + skill.DeveloperName__c + '"}}],"usage":{"input_tokens":4,"output_tokens":2}}');
            HttpResponse toolResponse = new HttpResponse();
            toolResponse.setStatusCode(200);
            toolResponse.setBody('{"content":[{"type":"tool_use","id":"toolu_2","name":"' + dataSource.DeveloperName__c + '","input":{}}],"usage":{"input_tokens":4,"output_tokens":2}}');
            HttpResponse replyResponse = new HttpResponse();
            replyResponse.setStatusCode(200);
            replyResponse.setBody('{"content":[{"type":"text","text":"Here is the summary."}],"usage":{"input_tokens":10,"output_tokens":5}}');
            ScriptedMock mock = new ScriptedMock();
            mock.script.add(pickResponse);
            mock.script.add(toolResponse);
            mock.script.add(replyResponse);
            Test.setMock(HttpCalloutMock.class, mock);

            // [3] Run the test
            Test.startTest();
                AIToolsSkillDataStructure.TestResult result = AIToolsSkillTestService.runTest(detail, testRequest);
            Test.stopTest();

            // [4] Read the skill back and collect the step types
            AISkill__c savedSkill = [SELECT LastTestStatus__c, LastTestedOn__c FROM AISkill__c WHERE Id = :skill.Id];
            Set<String> stepTypes = new Set<String>();
            for (AIToolsSkillDataStructure.TestStep testStep : result.steps) stepTypes.add(testStep.stepType);

            // [5] Check the test passed and was kept on the skill
            Assert.areEqual(AIAssistApplicationConstants.SKILL_TEST_STATUS_PASSED, result.status, 'The test should pass.');
            Assert.areEqual('Here is the summary.', result.replyText, 'The reply should be returned.');
            Assert.isTrue(stepTypes.contains(AIAssistApplicationConstants.STEP_TYPE_SKILL), 'The steps should include the skill being picked.');
            Assert.isTrue(stepTypes.contains(AIAssistApplicationConstants.STEP_TYPE_DATA_SOURCE), 'The steps should include the data source.');
            Assert.areEqual(AIAssistApplicationConstants.SKILL_TEST_STATUS_PASSED, savedSkill.LastTestStatus__c, 'The skill should keep the result.');
            Assert.isNotNull(savedSkill.LastTestedOn__c, 'The skill should keep when it was tested.');
            Assert.areEqual(0, AIDataSourceDispatcher.previewGrantedDataSourceIds.size(), 'The test grant should be cleared after the test.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent and describe an unsaved unbound skill, with a model that only answers
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIToolsSkillDataStructure.SkillDetail detail = new AIToolsSkillDataStructure.SkillDetail();
            detail.skillName = 'Draft skill';
            detail.developerName = 'Draft_Skill';
            detail.description = VALID_DESCRIPTION;
            AIToolsSkillDataStructure.TestRequest testRequest = new AIToolsSkillDataStructure.TestRequest();
            testRequest.agentId = agent.Id;
            testRequest.question = 'Hello';

            // [2] Run the test
            Test.startTest();
                AIToolsSkillDataStructure.TestResult result = AIToolsSkillTestService.runTest(detail, testRequest);
            Test.stopTest();

            // [3] Check the test was not picked
            Assert.areEqual(AIAssistApplicationConstants.SKILL_TEST_STATUS_NOT_PICKED, result.status, 'An answer without the skill should be Not Picked.');
            Assert.areEqual(Label.AI_ToolsSk_Test_Not_Picked, result.message, 'The reason should be given.');
            Assert.areEqual(AIAssistTestProviderMock.REPLY_TEXT, result.replyText, 'The reply should still be returned.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent and describe an unsaved skill, with a provider that refuses
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_FAIL);
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIToolsSkillDataStructure.SkillDetail detail = new AIToolsSkillDataStructure.SkillDetail();
            detail.skillName = 'Draft skill';
            detail.developerName = 'Draft_Skill';
            detail.description = VALID_DESCRIPTION;
            AIToolsSkillDataStructure.TestRequest testRequest = new AIToolsSkillDataStructure.TestRequest();
            testRequest.agentId = agent.Id;
            testRequest.question = 'Hello';

            // [2] Run the test
            Test.startTest();
                AIToolsSkillDataStructure.TestResult result = AIToolsSkillTestService.runTest(detail, testRequest);
            Test.stopTest();

            // [3] Check the test failed
            Assert.areEqual(AIAssistApplicationConstants.SKILL_TEST_STATUS_FAILED, result.status, 'A refused request should fail the test.');
            Assert.areEqual(Label.AI_ToolsSk_Error_Run_Failed, result.message, 'The run failed message should be given.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent, a bound data source, and describe a skill holding it
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, false)[0];
            dataSource.BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
            dataSource.TargetObject__c = 'Account';
            insert dataSource;
            AIToolsSkillDataStructure.SkillTool tool = new AIToolsSkillDataStructure.SkillTool();
            tool.kind = AIAssistApplicationConstants.SKILL_TOOL_KIND_DATA_SOURCE;
            tool.recordId = dataSource.Id;
            AIToolsSkillDataStructure.SkillDetail detail = new AIToolsSkillDataStructure.SkillDetail();
            detail.developerName = 'Draft_Skill';
            detail.description = VALID_DESCRIPTION;
            detail.tools = new List<AIToolsSkillDataStructure.SkillTool>{ tool };
            AIToolsSkillDataStructure.TestRequest testRequest = new AIToolsSkillDataStructure.TestRequest();
            List<String> refusals = new List<String>();

            // [2] Run it with no agent, then no question, then no record
            Test.startTest();
                try { AIToolsSkillTestService.runTest(detail, testRequest); } catch (AIToolsSkillTestService.AIToolsSkillTestServiceException ex) { refusals.add(ex.getMessage()); }
                testRequest.agentId = agent.Id;
                try { AIToolsSkillTestService.runTest(detail, testRequest); } catch (AIToolsSkillTestService.AIToolsSkillTestServiceException ex) { refusals.add(ex.getMessage()); }
                testRequest.question = 'Summarise this account.';
                try { AIToolsSkillTestService.runTest(detail, testRequest); } catch (AIToolsSkillTestService.AIToolsSkillTestServiceException ex) { refusals.add(ex.getMessage()); }
            Test.stopTest();

            // [3] Check each was refused with its message
            Assert.areEqual(3, refusals.size(), 'Every test should be refused.');
            Assert.areEqual(Label.AI_ToolsSk_Error_Agent_Required, refusals[0], 'A test with no agent should be refused.');
            Assert.areEqual(Label.AI_ToolsSk_Error_Question_Required, refusals[1], 'A test with no question should be refused.');
            Assert.areEqual(String.format(Label.AI_ToolsSk_Error_Record_Required, new List<String>{ 'Account' }), refusals[2], 'A bound skill with no record should be refused.');
        }
    }
}
