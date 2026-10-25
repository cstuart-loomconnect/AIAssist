/*
Class Name: AIToolsSkillEditorServiceTest

=================================================================
=================================================================

Description: Testing utility for the AI Tools Skill Editor Service: listing, reading and saving skills built from existing data sources and workflow actions, and the lists the wizard picks from.

=================================================================
=================================================================
Applicable Classes:

AIToolsSkillEditorService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIToolsSkillEditorServiceTest {

    // testScenario1: A manager saves a new active skill with a data source and a write action -> it is saved active, its tools are in order and its output is Record Change.
    // testScenario2: A manager saves a skill again with a tool removed and the order swapped, and an agent has it -> the removed tool is gone, the order follows the save and the agent is named.
    // testScenario3: A manager saves a skill with no name, a bad API name, a deleted tool, and a skill switched on with no tools -> each is refused and the refused new skill is not saved.
    // testScenario4: A manager lists skills, tool options and test agents -> a skill with a switched off required tool and one with no tools are flagged, both kinds of tool are offered, and the agent with a model is listed.
    // testScenario5: A user without the Manage Settings permission calls every method -> each is refused with the access label.

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
            // [1] Create a data source and a write workflow action, and describe a skill holding both
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, true)[0];
            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'Some_Flow', false)[0];
            action.ExecutionType__c = AIAssistApplicationConstants.WORKFLOW_EXECUTION_WRITE;
            action.RequiresConfirmation__c = true;
            action.ConfirmationMessage__c = 'Go ahead?';
            insert action;

            AIToolsSkillDataStructure.SkillTool dataSourceTool = new AIToolsSkillDataStructure.SkillTool();
            dataSourceTool.kind = AIAssistApplicationConstants.SKILL_TOOL_KIND_DATA_SOURCE;
            dataSourceTool.recordId = dataSource.Id;
            AIToolsSkillDataStructure.SkillTool actionTool = new AIToolsSkillDataStructure.SkillTool();
            actionTool.kind = AIAssistApplicationConstants.SKILL_TOOL_KIND_ACTION;
            actionTool.recordId = action.Id;

            AIToolsSkillDataStructure.SkillDetail detail = new AIToolsSkillDataStructure.SkillDetail();
            detail.skillName = 'Account summary';
            detail.developerName = 'Account_Summary';
            detail.description = VALID_DESCRIPTION;
            detail.instructions = '1. Call @' + dataSource.DeveloperName__c + '.\n2. Suggest @' + action.DeveloperName__c + '.';
            detail.outputType = AIAssistApplicationConstants.SKILL_OUTPUT_CHAT_ANSWER;
            detail.isActive = true;
            detail.tools = new List<AIToolsSkillDataStructure.SkillTool>{ dataSourceTool, actionTool };

            // [2] Save it
            Test.startTest();
                AIToolsSkillDataStructure.SkillRow row = AIToolsSkillEditorService.saveSkill(detail);
            Test.stopTest();

            // [3] Read the skill and its tools back
            AISkill__c savedSkill = [SELECT IsActive__c, OutputType__c FROM AISkill__c WHERE Id = :row.skillId];
            List<AISkillTool__c> savedTools = [SELECT AIDataSource__c, AIWorkflowAction__c, StepOrder__c FROM AISkillTool__c WHERE AISkill__c = :row.skillId ORDER BY StepOrder__c];

            // [4] Check it was saved active, with both tools in order, as a Record Change skill
            Assert.areEqual(true, savedSkill.IsActive__c, 'The skill should be saved active.');
            Assert.areEqual(AIAssistApplicationConstants.SKILL_OUTPUT_RECORD_CHANGE, savedSkill.OutputType__c, 'A skill with a write action should change records.');
            Assert.areEqual(2, savedTools.size(), 'Both tools should be saved.');
            Assert.areEqual(dataSource.Id, savedTools[0].AIDataSource__c, 'The data source should come first.');
            Assert.areEqual(action.Id, savedTools[1].AIWorkflowAction__c, 'The action should come second.');
            Assert.areEqual(1, row.dataSourceCount, 'The row should count one data source.');
            Assert.areEqual(1, row.actionCount, 'The row should count one action.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a skill with three data sources and give it to an active agent
            List<AIDataSource__c> dataSources = AIAssistTestDataFactory.createAIDataSources(3, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, true);
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            AIAssistTestDataFactory.createAISkillTools(skill.Id, dataSources, null, true);
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            agent.IsActive__c = true;
            insert agent;
            AIAssistTestDataFactory.createAIAgentSkills(agent.Id, new List<AISkill__c>{ skill }, true);

            // [2] Read it, drop the first tool and swap the other two, then save it
            Test.startTest();
                AIToolsSkillDataStructure.SkillDetail detail = AIToolsSkillEditorService.getSkill(skill.Id);
                detail.tools = new List<AIToolsSkillDataStructure.SkillTool>{ detail.tools[2], detail.tools[1] };
                AIToolsSkillEditorService.saveSkill(detail);
                AIToolsSkillDataStructure.SkillDetail savedDetail = AIToolsSkillEditorService.getSkill(skill.Id);
            Test.stopTest();

            // [3] Check the tools and the agent
            Assert.areEqual(2, savedDetail.tools.size(), 'The removed tool should be gone.');
            Assert.areEqual(dataSources[2].Id, savedDetail.tools[0].recordId, 'The third data source should now come first.');
            Assert.areEqual(dataSources[1].Id, savedDetail.tools[1].recordId, 'The second data source should now come second.');
            Assert.areEqual(1, savedDetail.agentCount, 'One agent should have the skill.');
            Assert.areEqual(agent.Name, savedDetail.agentNames[0], 'The agent should be named.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a data source and delete it, and describe a skill
            AIDataSource__c deletedSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, true)[0];
            delete deletedSource;

            AIToolsSkillDataStructure.SkillTool deletedTool = new AIToolsSkillDataStructure.SkillTool();
            deletedTool.kind = AIAssistApplicationConstants.SKILL_TOOL_KIND_DATA_SOURCE;
            deletedTool.recordId = deletedSource.Id;

            AIToolsSkillDataStructure.SkillDetail detail = new AIToolsSkillDataStructure.SkillDetail();
            detail.skillName = 'Account summary';
            detail.developerName = 'Account_Summary';
            detail.description = VALID_DESCRIPTION;
            detail.instructions = '1. Answer.';
            List<String> refusals = new List<String>();

            // [2] Save it with no name, a bad API name, a deleted tool, and switched on with no tools
            Test.startTest();
                detail.skillName = '';
                try { AIToolsSkillEditorService.saveSkill(detail); } catch (AIToolsSkillEditorService.AIToolsSkillEditorServiceException ex) { refusals.add(ex.getMessage()); }
                detail.skillName = 'Account summary';
                detail.developerName = '1 bad name';
                try { AIToolsSkillEditorService.saveSkill(detail); } catch (AIToolsSkillEditorService.AIToolsSkillEditorServiceException ex) { refusals.add(ex.getMessage()); }
                detail.developerName = 'Account_Summary';
                detail.tools = new List<AIToolsSkillDataStructure.SkillTool>{ deletedTool };
                try { AIToolsSkillEditorService.saveSkill(detail); } catch (AIToolsSkillEditorService.AIToolsSkillEditorServiceException ex) { refusals.add(ex.getMessage()); }
                detail.tools = new List<AIToolsSkillDataStructure.SkillTool>();
                detail.isActive = true;
                try { AIToolsSkillEditorService.saveSkill(detail); } catch (AIToolsSkillEditorService.AIToolsSkillEditorServiceException ex) { refusals.add(ex.getMessage()); }
            Test.stopTest();

            // [3] Check each was refused with its message and nothing was saved
            Assert.areEqual(4, refusals.size(), 'Every save should be refused.');
            Assert.areEqual(String.format(Label.AI_ToolsSk_Error_Required, new List<String>{ Schema.AISkill__c.Name.getDescribe().getLabel() }), refusals[0], 'A skill with no name should be refused.');
            Assert.areEqual(String.format(Label.AI_ToolsSk_Error_Required, new List<String>{ Schema.AISkill__c.DeveloperName__c.getDescribe().getLabel() }), refusals[1], 'A bad API name should be refused.');
            Assert.areEqual(Label.AI_ToolsSk_Error_Tool_Not_Found, refusals[2], 'A deleted tool should be refused.');
            Assert.areEqual(Label.AI_Error_Skill_No_Tools, refusals[3], 'A skill switched on with no tools should be refused by the trigger.');
            Assert.areEqual(0, [SELECT COUNT() FROM AISkill__c], 'No refused skill should be saved.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a skill with a switched off required data source, a skill with no tools, a workflow action and an agent with a model
            AIDataSource__c offSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, false)[0];
            offSource.IsActive__c = false;
            insert offSource;
            AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'Some_Flow', true);
            List<AISkill__c> skills = AIAssistTestDataFactory.createAISkills(2, true);
            AIAssistTestDataFactory.createAISkillTools(skills[0].Id, new List<AIDataSource__c>{ offSource }, null, true);
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            // [2] List the skills, the tool options and the test agents
            Test.startTest();
                List<AIToolsSkillDataStructure.SkillRow> rows = AIToolsSkillEditorService.getSkills();
                List<AIToolsSkillDataStructure.ToolOption> toolOptions = AIToolsSkillEditorService.getToolOptions();
                List<AIToolsSkillDataStructure.AgentOption> agentOptions = AIToolsSkillEditorService.getTestAgents();
            Test.stopTest();

            // [3] Sort what came back
            Map<Id, AIToolsSkillDataStructure.SkillRow> rowBySkillId = new Map<Id, AIToolsSkillDataStructure.SkillRow>();
            for (AIToolsSkillDataStructure.SkillRow row : rows) rowBySkillId.put(row.skillId, row);
            Set<String> toolKinds = new Set<String>();
            for (AIToolsSkillDataStructure.ToolOption option : toolOptions) toolKinds.add(option.kind);

            // [4] Check the flags, the tool options and the agent
            Assert.areEqual(AIAssistApplicationConstants.SKILL_ATTENTION_TOOL_INACTIVE, rowBySkillId.get(skills[0].Id).attention, 'A switched off required tool should be flagged.');
            Assert.areEqual(AIAssistApplicationConstants.SKILL_ATTENTION_NO_TOOLS, rowBySkillId.get(skills[1].Id).attention, 'A skill with no tools should be flagged.');
            Assert.isTrue(toolKinds.contains(AIAssistApplicationConstants.SKILL_TOOL_KIND_DATA_SOURCE) && toolKinds.contains(AIAssistApplicationConstants.SKILL_TOOL_KIND_ACTION), 'Both kinds of tool should be offered.');
            Assert.areEqual(1, agentOptions.size(), 'The agent with a model should be listed.');
            Assert.areEqual(agent.Id, agentOptions[0].agentId, 'The agent should be the one created.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            List<String> refusals = new List<String>();

            // [2] Call each method as that user and keep each message
            Test.startTest();
                System.runAs(users[0]) {
                    try { AIToolsSkillEditorService.getSkills(); } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) { refusals.add(ex.getMessage()); }
                    try { AIToolsSkillEditorService.getSkill(users[0].Id); } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) { refusals.add(ex.getMessage()); }
                    try { AIToolsSkillEditorService.getToolOptions(); } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) { refusals.add(ex.getMessage()); }
                    try { AIToolsSkillEditorService.getTestAgents(); } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) { refusals.add(ex.getMessage()); }
                    try { AIToolsSkillEditorService.saveSkill(new AIToolsSkillDataStructure.SkillDetail()); } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) { refusals.add(ex.getMessage()); }
                }
            Test.stopTest();

            // [3] Check every method was refused with the access label
            Assert.areEqual(5, refusals.size(), 'Every method should be refused.');
            Assert.areEqual(Label.AI_Settings_Error_Access, refusals[0], 'The access label should be shown.');
        }
    }
}
