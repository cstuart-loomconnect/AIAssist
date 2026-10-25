/*
Class Name: AIAgentWizardSkillsTest

=================================================================
=================================================================

Description: Testing utility for the Skills step of the AI Agent Wizard: the skills the page offers, the skills a saved agent has, and the warnings the checks give about them.

=================================================================
=================================================================
Applicable Classes:

AIAgentWizardEditorService: Coverage TBC
AIAgentWizardCheckService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIAgentWizardSkillsTest {

    // testScenario1: A skill with a data source and an action is given to a live agent -> the page offers it with its tools counted and one agent, and the agent's draft holds it.
    // testScenario2: A draft for an agent on Account is given a switched off skill that needs a Contact -> both are warnings on the Skills step naming the skill, and the agent can still be activated.

    private static final String SOQL_TEMPLATE = 'SELECT Id, Name FROM Contact WHERE Id = :recordId';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a skill with a data source and an action, and give it to a live agent
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, true)[0];
            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'Some_Flow', true)[0];
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            AIAssistTestDataFactory.createAISkillTools(skill.Id, new List<AIDataSource__c>{ dataSource }, new List<AIWorkflowAction__c>{ action }, true);
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            agent.IsActive__c = true;
            insert agent;
            AIAssistTestDataFactory.createAIAgentSkills(agent.Id, new List<AISkill__c>{ skill }, true);

            // [2] Read the page and the agent's draft
            Test.startTest();
                AIAgentWizardDataStructure.WizardPage page = AIAgentWizardEditorService.getWizardPage(agent.Id);
            Test.stopTest();

            // [3] Check the skill is offered with its tools and agent, and the draft holds it
            Assert.areEqual(1, page.skills.size(), 'The skill should be offered.');
            Assert.areEqual(skill.Id, page.skills[0].skillId, 'The offered skill should be the one created.');
            Assert.areEqual(1, page.skills[0].dataSourceCount, 'Its data source should be counted.');
            Assert.areEqual(1, page.skills[0].actionCount, 'Its action should be counted.');
            Assert.areEqual(1, page.skills[0].agentCount, 'The live agent should be counted.');
            Assert.areEqual(1, page.draft.skillIds.size(), 'The agent draft should hold the skill.');
            Assert.areEqual(skill.Id, page.draft.skillIds[0], 'The agent draft should hold the skill created.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a switched off skill bound to Contact, and a draft for an agent on Account that has it
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, false)[0];
            dataSource.BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
            dataSource.TargetObject__c = 'Contact';
            insert dataSource;
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            AIAssistTestDataFactory.createAISkillTools(skill.Id, new List<AIDataSource__c>{ dataSource }, null, true);
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIPromptTemplate__c promptTemplate = AIAssistTestDataFactory.createAIPromptTemplates(null, 1, true)[0];
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            draft.promptTemplateId = promptTemplate.Id;
            draft.objectApiNames = new List<String>{ 'Account' };
            draft.skillIds.add(skill.Id);

            // [2] Check the draft
            Test.startTest();
                AIAgentWizardDataStructure.DraftCheck check = AIAgentWizardCheckService.checkDraft(draft);
            Test.stopTest();

            // [3] Sort the findings by code
            Map<String, AIAgentWizardDataStructure.Finding> findingByCode = new Map<String, AIAgentWizardDataStructure.Finding>();
            for (AIAgentWizardDataStructure.Finding finding : check.findings) findingByCode.put(finding.code, finding);

            // [4] Check both warnings are on the Skills step and name the skill
            Assert.isTrue(findingByCode.containsKey(AIAssistApplicationConstants.WIZARD_CODE_ITEM_INACTIVE), 'A switched off skill should be a finding.');
            Assert.isTrue(findingByCode.containsKey(AIAssistApplicationConstants.WIZARD_CODE_OBJECT_NOT_ON_AGENT), 'A skill on another object should be a finding.');
            Assert.areEqual(AIAssistApplicationConstants.WIZARD_STEP_SKILLS, findingByCode.get(AIAssistApplicationConstants.WIZARD_CODE_ITEM_INACTIVE).step, 'The switched off skill is fixed on the Skills step.');
            Assert.areEqual(skill.Id, findingByCode.get(AIAssistApplicationConstants.WIZARD_CODE_OBJECT_NOT_ON_AGENT).itemId, 'The finding should name the skill.');
            Assert.areEqual(AIAssistApplicationConstants.WIZARD_SEVERITY_WARNING, findingByCode.get(AIAssistApplicationConstants.WIZARD_CODE_ITEM_INACTIVE).severity, 'A switched off skill should only warn.');
            Assert.isTrue(check.canActivate, 'Skill warnings should not stop the agent being activated.');
        }
    }
}
