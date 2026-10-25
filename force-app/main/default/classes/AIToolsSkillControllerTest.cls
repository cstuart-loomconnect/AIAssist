/*
Class Name: AIToolsSkillControllerTest

=================================================================
=================================================================

Description: Testing utility for the AI Tools Skill Controller: each method hands the work to its service, and a refusal reaches the tab as a readable message.

=================================================================
=================================================================
Applicable Classes:

AIToolsSkillController: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIToolsSkillControllerTest {

    // testScenario1: A manager saves a skill, reads the list and the skill, lists tool options and agents, and tests it -> each call returns what the service returns.
    // testScenario2: A manager saves a skill with no name -> the tab gets the readable message.
    // testScenario3: A user without the permission calls every method -> each throws the access label as an AuraHandledException.

    private static final String SOQL_TEMPLATE = 'SELECT Id, Name FROM Account WHERE Id = :recordId';
    private static final String VALID_DESCRIPTION = 'Use this skill when the user asks for a summary of the open account and its recent activity.';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent and an unbound data source, and describe a skill holding it as the tab would send it
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, false)[0];
            dataSource.BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
            insert dataSource;
            Map<String, Object> tool = new Map<String, Object>{
                'kind' => AIAssistApplicationConstants.SKILL_TOOL_KIND_DATA_SOURCE,
                'recordId' => dataSource.Id,
                'isRequired' => true
            };
            Map<String, Object> skillDetail = new Map<String, Object>{
                'skillName' => 'Account summary',
                'developerName' => 'Account_Summary',
                'description' => VALID_DESCRIPTION,
                'instructions' => '1. Call @' + dataSource.DeveloperName__c + '.',
                'outputType' => AIAssistApplicationConstants.SKILL_OUTPUT_CHAT_ANSWER,
                'isActive' => true,
                'tools' => new List<Object>{ tool }
            };
            Map<String, Object> testRequest = new Map<String, Object>{
                'agentId' => agent.Id,
                'question' => 'Hello'
            };

            // [2] Call every method
            Test.startTest();
                AIToolsSkillDataStructure.SkillRow savedRow = AIToolsSkillController.saveSkill(skillDetail);
                List<AIToolsSkillDataStructure.SkillRow> rows = AIToolsSkillController.getSkills();
                AIToolsSkillDataStructure.SkillDetail detail = AIToolsSkillController.getSkill(savedRow.skillId);
                List<AIToolsSkillDataStructure.ToolOption> toolOptions = AIToolsSkillController.getToolOptions();
                List<AIToolsSkillDataStructure.AgentOption> agentOptions = AIToolsSkillController.getTestAgents();
                AIToolsSkillDataStructure.TestResult result = AIToolsSkillController.runTest(skillDetail, testRequest);
            Test.stopTest();

            // [3] Check each call returned what the service returns
            Assert.areEqual(true, savedRow.isActive, 'The skill should be saved active.');
            Assert.areEqual(1, rows.size(), 'The list should hold the skill.');
            Assert.areEqual(1, detail.tools.size(), 'The skill should hold its tool.');
            Assert.areEqual(1, toolOptions.size(), 'The data source should be offered.');
            Assert.areEqual(1, agentOptions.size(), 'The agent should be listed.');
            Assert.isNotNull(result.status, 'The test should report how it ended.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Describe a skill with no name
            Map<String, Object> skillDetail = new Map<String, Object>{
                'developerName' => 'Account_Summary',
                'description' => VALID_DESCRIPTION
            };
            String message;

            // [2] Save it
            Test.startTest();
                try { AIToolsSkillController.saveSkill(skillDetail); } catch (AuraHandledException ex) { message = ex.getMessage(); }
            Test.stopTest();

            // [3] Check the tab got the readable message
            Assert.areEqual(String.format(Label.AI_ToolsSk_Error_Required, new List<String>{ Schema.AISkill__c.Name.getDescribe().getLabel() }), message, 'The tab should get the readable message.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            List<String> refusals = new List<String>();

            // [2] Call each method as that user and keep each message
            Test.startTest();
                System.runAs(users[0]) {
                    try { AIToolsSkillController.getSkills(); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIToolsSkillController.getSkill(users[0].Id); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIToolsSkillController.getToolOptions(); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIToolsSkillController.getTestAgents(); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIToolsSkillController.saveSkill(new Map<String, Object>()); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIToolsSkillController.runTest(new Map<String, Object>(), new Map<String, Object>()); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                }
            Test.stopTest();

            // [3] Check every method was refused with the access label
            Assert.areEqual(6, refusals.size(), 'Every method should be refused.');
            Assert.areEqual(Label.AI_Settings_Error_Access, refusals[0], 'The access label should be shown.');
            Assert.areEqual(Label.AI_Settings_Error_Access, refusals[5], 'The access label should be shown for the test.');
        }
    }
}
