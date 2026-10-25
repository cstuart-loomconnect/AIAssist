/*
Class Name: AIAgentWizardEditorServiceTest

=================================================================
=================================================================

Description: Testing utility for AIAgentWizardEditorService: the page, the list of agents, a saved agent as a draft, a copy, the object search and the model test.

=================================================================
=================================================================
Applicable Classes:

AIAgentWizardEditorService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIAgentWizardEditorServiceTest {

    // testScenario1: A manager opens the page for a new agent with a model, templates, data sources, actions, an agent, and a PII registry -> every list is filled, only active models and templates are offered, and there is no draft.
    // testScenario2: A manager opens the page for an agent that uses a switched off model and template -> the draft is that agent, and the model and template it uses are still offered.
    // testScenario3: A saved agent with links, an inactive link and an access list is read -> the draft holds the settings, only active links, and each line of the access list with its label and count.
    // testScenario4: An agent is copied -> the copy has no id, a copy name, no API name and is switched off.
    // testScenario5: Objects are searched with text that is too short, then with text that matches -> the first is empty and the second finds Account in label order, at most 25.
    // testScenario6: A model is tested, and a model that does not exist is tested -> the first reports the result and the second is refused.
    // testScenario7: An agent that does not exist is read, and a user without the Manage Settings permission opens the page -> each is refused.
    // testScenario8: Three agents are listed: a ready active one with a data source, an action and two objects, a switched off one with no model and a named user, and one with no template -> the active one comes first and each row has its labels, model, users, counts and worst finding.
    // testScenario9: The list is read with no agents, then the row of one agent is read -> the first is empty and the second is that agent.
    // testScenario10: An agent that does not exist is read as a row, and a user without the Manage Settings permission reads the list and a row -> each is refused.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an active and a switched off model, a template, a switched off template, an agent with a link and a PII registry
            AIAssistTestDataFactory.upsertUiSettings(true);
            AIModelConfiguration__c activeModel = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIModelConfiguration__c offModel = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            offModel.IsActive__c = false;
            insert offModel;
            AIPromptTemplate__c promptTemplate = AIAssistTestDataFactory.createAIPromptTemplates(null, 1, false)[0];
            promptTemplate.Description__c = 'Plain wording';
            insert promptTemplate;
            AIPromptTemplate__c offTemplate = AIAssistTestDataFactory.createAIPromptTemplates(null, 1, false)[0];
            offTemplate.IsActive__c = false;
            insert offTemplate;
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, activeModel.Id, true)[0];
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', false)[0];
            dataSource.TargetObject__c = 'Account';
            insert dataSource;
            AIAssistTestDataFactory.createAIAgentDataSources(agent.Id, new List<AIDataSource__c>{dataSource}, true);
            AIWorkflowAction__c apexAction = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', true)[0];
            AIWorkflowAction__c flowAction = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'Missing_Flow_For_Wizard', false)[0];
            flowAction.TargetObject__c = 'Contact';
            insert flowAction;
            AIAssistTestDataFactory.createAIPIIRegistries(1, 'Account', true);

            // [2] Open the page for a new agent
            Test.startTest();
                AIAgentWizardDataStructure.WizardPage page = AIAgentWizardEditorService.getWizardPage(null);
            Test.stopTest();

            // [3] Find the options by Id
            Map<Id, AIAgentWizardDataStructure.DataSourceOption> dataSourceById = new Map<Id, AIAgentWizardDataStructure.DataSourceOption>();
            Map<Id, AIAgentWizardDataStructure.WorkflowActionOption> actionById = new Map<Id, AIAgentWizardDataStructure.WorkflowActionOption>();
            Map<String, String> labelByApiName = new Map<String, String>();

            for (AIAgentWizardDataStructure.DataSourceOption option : page.dataSources) {

                dataSourceById.put(option.dataSourceId, option);
            }

            for (AIAgentWizardDataStructure.WorkflowActionOption option : page.workflowActions) {

                actionById.put(option.actionId, option);
            }

            for (AIAgentWizardDataStructure.ObjectOption option : page.objects) {

                labelByApiName.put(option.apiName, option.label);
            }

            // [4] Check the outcome
            Assert.isNull(page.draft, 'A new agent has no draft.');
            Assert.areEqual(1, page.copyOptions.size(), 'The agent can be copied.');
            Assert.areEqual(agent.Id, page.copyOptions[0].agentId, 'The agent to copy is the one saved.');
            Assert.areEqual(1, page.models.size(), 'Only the active model is offered.');
            Assert.areEqual(activeModel.Id, page.models[0].modelId, 'The active model is offered.');
            Assert.areEqual(1, page.models[0].agentCount, 'The agent that uses the model is counted.');
            Assert.areEqual(1, page.promptTemplates.size(), 'Only the active template is offered.');
            Assert.areEqual('Plain wording', page.promptTemplates[0].description, 'The description is carried.');
            Assert.areEqual(1, dataSourceById.get(dataSource.Id).agentCount, 'The active link is counted.');
            Assert.isTrue(dataSourceById.get(dataSource.Id).isPiiProtected, 'The object has a PII registry.');
            Assert.isTrue(actionById.get(apexAction.Id).hasActiveFlowVersion, 'An Apex action has no flow to be missing.');
            Assert.isFalse(actionById.get(flowAction.Id).hasActiveFlowVersion, 'A flow with no active version is reported.');
            Assert.isNull(actionById.get(flowAction.Id).activeFlowVersion, 'There is no version number.');
            Assert.isFalse(actionById.get(flowAction.Id).isWrite, 'The action is read only.');
            Assert.areEqual(0, actionById.get(apexAction.Id).agentCount, 'No agent uses the action.');
            Assert.areEqual('Account', labelByApiName.get('Account'), 'Every object mentioned has a label.');
            Assert.isTrue(labelByApiName.containsKey('Contact'), 'The object of an action is labelled.');
            Assert.isTrue(page.isWorkflowActionsEnabled, 'The org setting is carried.');
            Assert.isNotNull(page.orgToolCallingCap, 'The org cap is carried.');
            Assert.isNotNull(page.policy, 'The default policy is carried.');
            Assert.isTrue(page.assistUserCount >= 1, 'The AI Assist users are counted.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent that uses a model and a template that are then switched off
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIPromptTemplate__c promptTemplate = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, true)[0];
            promptTemplate.IsActive__c = false;
            update promptTemplate;
            model.IsActive__c = false;
            update model;

            // [2] Open the page for the agent
            Test.startTest();
                AIAgentWizardDataStructure.WizardPage page = AIAgentWizardEditorService.getWizardPage(agent.Id);
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(agent.Id, page.draft.agentId, 'The draft is the agent.');
            Assert.areEqual(1, page.models.size(), 'The model the agent uses is still offered.');
            Assert.isFalse(page.models[0].isActive, 'It is reported as switched off.');
            Assert.areEqual(1, page.promptTemplates.size(), 'The template the agent uses is still offered.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent with an active link, an inactive link, a user line and a permission set line that is off
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, false)[0];
            agent.ObjectApiNames__c = 'Account, Contact';
            agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
            insert agent;
            List<AIDataSource__c> dataSources = AIAssistTestDataFactory.createAIDataSources(2, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true);
            List<AIAgentDataSource__c> dataSourceLinks = AIAssistTestDataFactory.createAIAgentDataSources(agent.Id, dataSources, false);
            dataSourceLinks[1].IsActive__c = false;
            insert dataSourceLinks;
            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', true)[0];
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{action}, true);
            List<AIAgentAssignment__c> assignments = AIAssistTestDataFactory.createAIAgentAssignments(agent.Id, users, 'AIAssistUser', false);
            assignments[1].IsActive__c = false;
            insert assignments;

            // [2] Read the agent as a draft
            Test.startTest();
                AIAgentWizardDataStructure.AgentDraft draft = AIAgentWizardEditorService.getAgentDraft(agent.Id);
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(agent.Name, draft.agentName, 'The name is copied.');
            Assert.areEqual(agent.DeveloperName__c, draft.developerName, 'The API name is copied.');
            Assert.areEqual(2, draft.objectApiNames.size(), 'Both objects are listed.');
            Assert.areEqual('Contact', draft.objectApiNames[1], 'The names are trimmed.');
            Assert.areEqual(model.Id, draft.modelConfigurationId, 'The model is copied.');
            Assert.areEqual(1, draft.dataSourceIds.size(), 'Only the active data source link is carried.');
            Assert.areEqual(dataSources[0].Id, draft.dataSourceIds[0], 'It is the data source of the active link.');
            Assert.areEqual(1, draft.workflowActionIds.size(), 'The action link is carried.');
            Assert.isTrue(draft.isActive, 'The agent is live.');
            Assert.isNotNull(draft.lastModifiedDate, 'The time of the last change is carried.');
            Assert.areEqual(2, draft.assignments.size(), 'Both lines of the access list are carried.');
            Assert.areEqual('A', draft.assignments[0].label.left(1), 'The user line is labelled with the name.');
            Assert.areEqual(1, draft.assignments[0].userCount, 'A user covers one user.');
            Assert.areEqual('AIAssistUser', draft.assignments[1].permissionSetName, 'The permission set line is carried.');
            Assert.isFalse(draft.assignments[1].isActive, 'The line that is off stays off.');
            Assert.isNotNull(draft.assignments[1].label, 'The permission set has a label.');
            Assert.areEqual(1, draft.userCount, 'Only the user who is named has the agent now.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a live agent
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];

            // [2] Copy it
            Test.startTest();
                AIAgentWizardDataStructure.AgentDraft draft = AIAgentWizardEditorService.getCopyDraft(agent.Id);
            Test.stopTest();

            // [3] Check the outcome
            Assert.isNull(draft.agentId, 'The copy is a new agent.');
            Assert.areEqual('Copy of ' + agent.Name, draft.agentName, 'The name says it is a copy.');
            Assert.isNull(draft.developerName, 'The API name is left for the admin to type.');
            Assert.isFalse(draft.isActive, 'The copy is switched off.');
            Assert.isNull(draft.lastModifiedDate, 'The copy has no change time.');
            Assert.isNull(draft.userCount, 'The copy has no users yet.');
            Assert.areEqual(model.Id, draft.modelConfigurationId, 'The settings are copied.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Search with too little text, then with text that matches
            Test.startTest();
                List<AIAgentWizardDataStructure.ObjectOption> shortOptions = AIAgentWizardEditorService.searchObjects('a');
                List<AIAgentWizardDataStructure.ObjectOption> options = AIAgentWizardEditorService.searchObjects('account');
                List<AIAgentWizardDataStructure.ObjectOption> manyOptions = AIAgentWizardEditorService.searchObjects('co');
            Test.stopTest();

            // [2] Find Account in the results
            Boolean isAccountFound = false;

            for (AIAgentWizardDataStructure.ObjectOption option : options) {

                if (option.apiName == 'Account' && option.label == 'Account') isAccountFound = true;
            }

            // [3] Check the outcome
            Assert.isTrue(shortOptions.isEmpty(), 'Text that is too short finds nothing.');
            Assert.isTrue(isAccountFound, 'Account is found.');
            Assert.isTrue(manyOptions.size() <= 25, 'At most 25 objects are offered.');
            Assert.isFalse(manyOptions.isEmpty(), 'Objects match the text.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a model and a provider that answers, and the Id of a model that was never saved
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            Id missingId = AIModelConfiguration__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);
            String refusal;

            // [2] Test each
            Test.startTest();
                AIModelsDataStructure.TestResult result = AIAgentWizardEditorService.testModel(model.Id);
                try { AIAgentWizardEditorService.testModel(missingId); } catch (Exception ex) { refusal = ex.getMessage(); }
            Test.stopTest();

            // [3] Check the outcome
            Assert.isTrue(result.isSuccessful, 'The test passes.');
            Assert.areEqual(Label.AI_Wizard_Error_Model_Not_Found, refusal, 'A model that is gone is refused.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the Id of an agent that was never saved, and a user who holds only the end user permission set
            Id missingId = AIAgent__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            String missingRefusal;
            String accessRefusal;

            // [2] Read the missing agent, and open the page as the user
            Test.startTest();
                try { AIAgentWizardEditorService.getAgentDraft(missingId); } catch (Exception ex) { missingRefusal = ex.getMessage(); }

                System.runAs(users[0]) {
                    try { AIAgentWizardEditorService.getWizardPage(null); } catch (Exception ex) { accessRefusal = ex.getMessage(); }
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(Label.AI_Wizard_Error_Not_Found, missingRefusal, 'An agent that is gone is refused.');
            Assert.areEqual(Label.AI_Settings_Error_Access, accessRefusal, 'The access label should be shown.');
        }
    }

    @IsTest static void testScenario8() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a policy, a model, a template, an active agent with a data source and an action, a switched off agent with no model and a named user, and a switched off agent with no template
            AIAssistTestDataFactory.createDefaultUsagePolicy();
            AIAssistTestDataFactory.upsertUiSettings(true);
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIPromptTemplate__c promptTemplate = AIAssistTestDataFactory.createAIPromptTemplates(null, 1, true)[0];
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true)[0];
            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', true)[0];
            AIAgent__c readyAgent = AIAssistTestDataFactory.createAIAgents(1, model.Id, false)[0];
            readyAgent.ObjectApiNames__c = 'Account, Contact';
            readyAgent.AIPromptTemplate__c = promptTemplate.Id;
            insert readyAgent;
            AIAssistTestDataFactory.createAIAgentDataSources(readyAgent.Id, new List<AIDataSource__c>{dataSource}, true);
            AIAssistTestDataFactory.createAIAgentWorkflowActions(readyAgent.Id, new List<AIWorkflowAction__c>{action}, true);
            AIAgent__c noModelAgent = AIAssistTestDataFactory.createAIAgents(1, null, false)[0];
            noModelAgent.ObjectApiNames__c = 'Account';
            insert noModelAgent;
            AIAssistTestDataFactory.createAIAgentAssignments(noModelAgent.Id, users, null, true);
            AIAgent__c noTemplateAgent = AIAssistTestDataFactory.createAIAgents(1, model.Id, false)[0];
            noTemplateAgent.IsActive__c = false;
            noTemplateAgent.ObjectApiNames__c = 'Account';
            insert noTemplateAgent;

            // [2] Read the list
            Test.startTest();
                List<AIAgentWizardDataStructure.AgentRow> rows = AIAgentWizardEditorService.getAgentList();
            Test.stopTest();

            // [3] Find each row
            Map<Id, AIAgentWizardDataStructure.AgentRow> rowById = new Map<Id, AIAgentWizardDataStructure.AgentRow>();

            for (AIAgentWizardDataStructure.AgentRow row : rows) rowById.put(row.agentId, row);

            // [4] Check the outcome
            Assert.areEqual(3, rows.size(), 'Every agent should be listed.');
            Assert.areEqual(readyAgent.Id, rows[0].agentId, 'The active agent should come first.');
            Assert.isTrue(rowById.get(readyAgent.Id).isActive, 'The agent should be active.');
            Assert.areEqual(new List<String>{'Account', 'Contact'}, rowById.get(readyAgent.Id).objectApiNames, 'The object names should be split.');
            Assert.areEqual(new List<String>{'Account', 'Contact'}, rowById.get(readyAgent.Id).objectLabels, 'The labels should follow the object names.');
            Assert.areEqual(model.Name, rowById.get(readyAgent.Id).modelName, 'The model name should be shown.');
            Assert.isTrue(rowById.get(readyAgent.Id).isAllUsers, 'An agent open to all should say so.');
            Assert.isTrue(rowById.get(readyAgent.Id).userCount >= 1, 'The AI Assist users should be counted.');
            Assert.areEqual(0, rowById.get(readyAgent.Id).blockerCount, 'The ready agent has no blocker.');
            Assert.areEqual(0, rowById.get(readyAgent.Id).warningCount, 'The ready agent has no warning.');
            Assert.isNull(rowById.get(readyAgent.Id).topFindingTitle, 'The ready agent has no worst finding.');
            Assert.isNotNull(rowById.get(readyAgent.Id).lastModifiedDate, 'The date of the last change should be shown.');
            Assert.isNull(rowById.get(noModelAgent.Id).modelName, 'An agent with no model has no model name.');
            Assert.isFalse(rowById.get(noModelAgent.Id).isAllUsers, 'An agent for named users is not open to all.');
            Assert.areEqual(1, rowById.get(noModelAgent.Id).userCount, 'The named user should be counted.');
            Assert.areEqual(1, rowById.get(noModelAgent.Id).blockerCount, 'The missing model is a blocker.');
            Assert.areEqual(1, rowById.get(noModelAgent.Id).warningCount, 'The missing template is a warning.');
            Assert.areEqual(AIAssistApplicationConstants.WIZARD_SEVERITY_BLOCKER, rowById.get(noModelAgent.Id).topFindingSeverity, 'A blocker is worse than a warning found before it.');
            Assert.areEqual(Label.AI_Wizard_Finding_NoModel_Title, rowById.get(noModelAgent.Id).topFindingTitle, 'The title of the blocker should be shown.');
            Assert.areEqual(0, rowById.get(noTemplateAgent.Id).blockerCount, 'The agent with no template has no blocker.');
            Assert.areEqual(1, rowById.get(noTemplateAgent.Id).warningCount, 'The missing template is a warning.');
            Assert.areEqual(AIAssistApplicationConstants.WIZARD_SEVERITY_WARNING, rowById.get(noTemplateAgent.Id).topFindingSeverity, 'The warning is the worst finding.');
        }
    }

    @IsTest static void testScenario9() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create one agent, and read the list before and after it exists
            Test.startTest();
                List<AIAgentWizardDataStructure.AgentRow> emptyRows = AIAgentWizardEditorService.getAgentList();
            Test.stopTest();

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];

            // [2] Read the row of the agent
            AIAgentWizardDataStructure.AgentRow row = AIAgentWizardEditorService.getAgentRow(agent.Id);

            // [3] Check the outcome
            Assert.isTrue(emptyRows.isEmpty(), 'No agents should give no rows.');
            Assert.areEqual(agent.Id, row.agentId, 'The row should be the agent asked for.');
            Assert.areEqual(1, row.blockerCount, 'An agent with no object has a blocker.');
        }
    }

    @IsTest static void testScenario10() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the Id of an agent that was never saved, and a user who holds only the end user permission set
            Id missingId = AIAgent__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            String missingRefusal;
            String listRefusal;
            String rowRefusal;

            // [2] Read the missing row, and read the list and a row as the user
            Test.startTest();
                try { AIAgentWizardEditorService.getAgentRow(missingId); } catch (Exception ex) { missingRefusal = ex.getMessage(); }

                System.runAs(users[0]) {
                    try { AIAgentWizardEditorService.getAgentList(); } catch (Exception ex) { listRefusal = ex.getMessage(); }
                    try { AIAgentWizardEditorService.getAgentRow(missingId); } catch (Exception ex) { rowRefusal = ex.getMessage(); }
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(Label.AI_Wizard_Error_Not_Found, missingRefusal, 'An agent that is gone is refused.');
            Assert.areEqual(Label.AI_Settings_Error_Access, listRefusal, 'The access label should be shown for the list.');
            Assert.areEqual(Label.AI_Settings_Error_Access, rowRefusal, 'The access label should be shown for the row.');
        }
    }
}
