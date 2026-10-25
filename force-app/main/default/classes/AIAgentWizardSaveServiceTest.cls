/*
Class Name: AIAgentWizardSaveServiceTest

=================================================================
=================================================================

Description: Testing utility for AIAgentWizardSaveService: saving the whole draft of the AI Agent Wizard, and switching an agent on or off from the list.

=================================================================
=================================================================
Applicable Classes:

AIAgentWizardSaveService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIAgentWizardSaveServiceTest {

    // testScenario1: A new agent with a skill, a data source, an action, a user and a permission set is saved and activated -> the agent is live with active links and both access lines, and the result counts them.
    // testScenario2: A new agent is saved as a draft with repeated ids and object names -> it is saved switched off with each id and name once.
    // testScenario3: A live agent is changed: a link removed, one added, a switched off link brought back, an access line removed, added and switched -> the links and lines match the draft, kept ones keep their records, and the agent stays live.
    // testScenario4: A live agent is saved without activating -> it is switched off and keeps its links.
    // testScenario5: A draft with no model is activated, and a draft with a blank name, a taken API name or a limit of zero is saved -> activation is refused with the blocker label and each save is refused with the finding's message, and nothing is saved.
    // testScenario6: A draft with an id that belongs to nothing, a link to a data source that was deleted, an access line with nobody, a choice the pick list does not offer, and no draft -> each is refused.
    // testScenario7: A user without the Manage Settings permission saves -> the access label is shown.
    // testScenario8: A switched off agent that is ready is switched on, off, on again and off with no value -> each change is saved and each call returns the agent's new row.
    // testScenario9: An agent with no model is switched on -> the text of the blocker is shown and the agent stays off.
    // testScenario10: An agent that does not exist is switched off, and a user without the Manage Settings permission does it -> each is refused.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a draft with a skill, a data source, an action, a user and a permission set
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true)[0];
            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', true)[0];
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            draft.accessMode = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
            draft.dataSourceIds.add(dataSource.Id);
            draft.workflowActionIds.add(action.Id);
            draft.skillIds.add(skill.Id);
            draft.assignments.add(AIAssistTestDataFactory.createAIAssignmentView(users[0].Id, null));
            draft.assignments.add(AIAssistTestDataFactory.createAIAssignmentView(null, 'AIAssistUser'));

            // [2] Save and activate it
            Test.startTest();
                AIAgentWizardDataStructure.SaveResult result = AIAgentWizardSaveService.saveAgent(draft, true);
            Test.stopTest();

            // [3] Read what was saved
            AIAgent__c agent = [SELECT Name, DeveloperName__c, ObjectApiNames__c, AIModelConfiguration__c, IsActive__c, AccessMode__c, MaxTokensPerConversation__c, GreetingMessage__c FROM AIAgent__c WHERE Id = :result.agentId];
            List<AIAgentDataSource__c> dataSourceLinks = [SELECT IsActive__c FROM AIAgentDataSource__c WHERE AIAgent__c = :agent.Id];
            List<AIAgentWorkflowAction__c> actionLinks = [SELECT IsActive__c FROM AIAgentWorkflowAction__c WHERE AIAgent__c = :agent.Id];
            List<AIAgentSkill__c> skillLinks = [SELECT AISkill__c, IsActive__c FROM AIAgentSkill__c WHERE AIAgent__c = :agent.Id];
            List<AIAgentAssignment__c> assignments = [SELECT AssigneeType__c, IsActive__c FROM AIAgentAssignment__c WHERE AIAgent__c = :agent.Id];

            // [4] Check the outcome
            Assert.isTrue(result.isCreated, 'The agent is new.');
            Assert.isTrue(result.isActive, 'The agent is live.');
            Assert.areEqual(draft.agentName, result.agentName, 'The name is reported.');
            Assert.areEqual(model.Name, result.modelName, 'The model name is reported.');
            Assert.areEqual(1, result.dataSourceCount, 'The data source is counted.');
            Assert.areEqual(1, result.workflowActionCount, 'The action is counted.');
            Assert.areEqual(1, result.skillCount, 'The skill is counted.');
            Assert.areEqual(1, skillLinks.size(), 'The skill is linked.');
            Assert.isTrue(skillLinks[0].IsActive__c, 'The skill link is active.');
            Assert.areEqual(2, result.assignmentCount, 'Both lines are counted.');
            Assert.isTrue(result.userCount >= 1, 'The users who have the agent are counted.');
            Assert.isTrue(agent.IsActive__c, 'The agent is saved live.');
            Assert.areEqual('Account', agent.ObjectApiNames__c, 'The object is saved.');
            Assert.areEqual(model.Id, agent.AIModelConfiguration__c, 'The model is saved.');
            Assert.areEqual(AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY, agent.AccessMode__c, 'The access mode is saved.');
            Assert.areEqual(50000, agent.MaxTokensPerConversation__c, 'The limits are saved.');
            Assert.areEqual('Hello.', agent.GreetingMessage__c, 'The greeting is saved.');
            Assert.areEqual(1, dataSourceLinks.size(), 'The data source is linked.');
            Assert.isTrue(dataSourceLinks[0].IsActive__c, 'The link is active.');
            Assert.areEqual(1, actionLinks.size(), 'The action is linked.');
            Assert.isTrue(actionLinks[0].IsActive__c, 'The link is active.');
            Assert.areEqual(2, assignments.size(), 'Both lines are saved.');
            Assert.isTrue(assignments[0].IsActive__c && assignments[1].IsActive__c, 'Both lines are active.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a draft that repeats a data source and an object name
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true)[0];
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            draft.dataSourceIds = new List<Id>{dataSource.Id, dataSource.Id};
            draft.objectApiNames = new List<String>{' Account ', 'Account', 'Contact', ''};
            draft.description = '   ';

            // [2] Save it as a draft
            Test.startTest();
                AIAgentWizardDataStructure.SaveResult result = AIAgentWizardSaveService.saveAgent(draft, false);
            Test.stopTest();

            // [3] Read what was saved
            AIAgent__c agent = [SELECT ObjectApiNames__c, IsActive__c, Description__c FROM AIAgent__c WHERE Id = :result.agentId];
            Integer linkCount = [SELECT COUNT() FROM AIAgentDataSource__c WHERE AIAgent__c = :result.agentId];

            // [4] Check the outcome
            Assert.isFalse(result.isActive, 'The agent is saved switched off.');
            Assert.isFalse(agent.IsActive__c, 'The agent is switched off.');
            Assert.areEqual('Account,Contact', agent.ObjectApiNames__c, 'Each object is saved once.');
            Assert.isNull(agent.Description__c, 'A blank text is saved as empty.');
            Assert.areEqual(1, linkCount, 'The data source is linked once.');
            Assert.areEqual(1, result.dataSourceCount, 'It is counted once.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a live agent with two data sources, an action, a data source link that is off, a user line and a permission set line
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            List<AIDataSource__c> dataSources = AIAssistTestDataFactory.createAIDataSources(4, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true);
            List<AIAgentDataSource__c> dataSourceLinks = AIAssistTestDataFactory.createAIAgentDataSources(agent.Id, new List<AIDataSource__c>{dataSources[0], dataSources[1], dataSources[3]}, false);
            dataSourceLinks[2].IsActive__c = false;
            insert dataSourceLinks;
            List<AIWorkflowAction__c> actions = AIAssistTestDataFactory.createAIWorkflowActions(3, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', true);
            List<AIAgentWorkflowAction__c> actionLinks = AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{actions[0], actions[2]}, false);
            actionLinks[1].IsActive__c = false;
            insert actionLinks;
            AIAssistTestDataFactory.createAIAgentAssignments(agent.Id, new List<User>{users[0]}, 'AIAssistUser', true);

            // [2] Change the draft: drop data source 0 and the action, add data source 2 and the other action, bring back link 3, drop user 0, add user 1, and switch the permission set line off
            AIAgentWizardDataStructure.AgentDraft draft = AIAgentWizardEditorService.getAgentDraft(agent.Id);
            draft.agentName = 'Renamed agent';
            draft.objectApiNames = new List<String>{'Account'};
            draft.dataSourceIds = new List<Id>{dataSources[1].Id, dataSources[2].Id, dataSources[3].Id};
            draft.workflowActionIds = new List<Id>{actions[1].Id, actions[2].Id};
            draft.accessMode = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
            draft.assignments = new List<AIAgentWizardDataStructure.AssignmentView>{AIAssistTestDataFactory.createAIAssignmentView(users[1].Id, null), AIAssistTestDataFactory.createAIAssignmentView(null, 'AIAssistUser')};
            draft.assignments[1].isActive = false;

            // [3] Save it, keeping it live
            Test.startTest();
                AIAgentWizardDataStructure.SaveResult result = AIAgentWizardSaveService.saveAgent(draft, true);
            Test.stopTest();

            // [4] Read what is saved
            AIAgent__c savedAgent = [SELECT Name, IsActive__c FROM AIAgent__c WHERE Id = :agent.Id];
            Map<Id, AIAgentDataSource__c> dataSourceLinkById = new Map<Id, AIAgentDataSource__c>();

            for (AIAgentDataSource__c link : [SELECT Id, AIDataSource__c, IsActive__c FROM AIAgentDataSource__c WHERE AIAgent__c = :agent.Id]) {

                dataSourceLinkById.put(link.AIDataSource__c, link);
            }

            List<AIAgentWorkflowAction__c> savedActionLinks = [SELECT AIWorkflowAction__c, IsActive__c FROM AIAgentWorkflowAction__c WHERE AIAgent__c = :agent.Id AND IsActive__c = TRUE ORDER BY AIWorkflowAction__c];
            Map<String, AIAgentAssignment__c> assignmentByType = new Map<String, AIAgentAssignment__c>();

            for (AIAgentAssignment__c assignment : [SELECT AssigneeType__c, User__c, IsActive__c FROM AIAgentAssignment__c WHERE AIAgent__c = :agent.Id]) {

                assignmentByType.put(assignment.AssigneeType__c, assignment);
            }

            // [5] Check the outcome
            Assert.isFalse(result.isCreated, 'The agent was changed, not created.');
            Assert.areEqual(agent.Id, result.agentId, 'The same agent is saved.');
            Assert.areEqual('Renamed agent', savedAgent.Name, 'The name is changed.');
            Assert.isTrue(savedAgent.IsActive__c, 'The agent stays live.');
            Assert.areEqual(3, dataSourceLinkById.size(), 'The removed link is gone and the new one is added.');
            Assert.isFalse(dataSourceLinkById.containsKey(dataSources[0].Id), 'The removed link is gone.');
            Assert.isTrue(dataSourceLinkById.get(dataSources[3].Id).IsActive__c, 'The link that was off is on again.');
            Assert.isTrue(dataSourceLinkById.get(dataSources[2].Id).IsActive__c, 'The new link is on.');
            Assert.areEqual(dataSourceLinks[1].Id, dataSourceLinkById.get(dataSources[1].Id).Id, 'The link that stays keeps its record.');
            Assert.areEqual(2, savedActionLinks.size(), 'The new action and the one brought back are linked.');
            Assert.isFalse(new Set<Id>{savedActionLinks[0].AIWorkflowAction__c, savedActionLinks[1].AIWorkflowAction__c}.contains(actions[0].Id), 'The removed action is no longer active.');
            Assert.areEqual(2, assignmentByType.size(), 'The access list matches the draft.');
            Assert.isFalse(assignmentByType.get(AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET).IsActive__c, 'The permission set line stays and is switched off.');
            Assert.areEqual(users[1].Id, assignmentByType.get(AIAssistApplicationConstants.ASSIGNEE_TYPE_USER).User__c, 'The new user replaces the old one on the list.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a live agent with a data source
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true)[0];
            AIAssistTestDataFactory.createAIAgentDataSources(agent.Id, new List<AIDataSource__c>{dataSource}, true);
            AIAgentWizardDataStructure.AgentDraft draft = AIAgentWizardEditorService.getAgentDraft(agent.Id);
            draft.objectApiNames = new List<String>{'Account'};

            // [2] Save it without activating
            Test.startTest();
                AIAgentWizardDataStructure.SaveResult result = AIAgentWizardSaveService.saveAgent(draft, false);
            Test.stopTest();

            // [3] Read what is saved
            AIAgent__c savedAgent = [SELECT IsActive__c FROM AIAgent__c WHERE Id = :agent.Id];
            Integer linkCount = [SELECT COUNT() FROM AIAgentDataSource__c WHERE AIAgent__c = :agent.Id AND IsActive__c = TRUE];

            // [4] Check the outcome
            Assert.isFalse(result.isActive, 'The result says it is switched off.');
            Assert.isFalse(savedAgent.IsActive__c, 'The agent is switched off.');
            Assert.areEqual(1, linkCount, 'The links are kept.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a draft with no model, and drafts with a blank name, a taken API name and a limit of zero
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c existingAgent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIAgentWizardDataStructure.AgentDraft noModelDraft = AIAssistTestDataFactory.createAIAgentDraft(null);
            AIAgentWizardDataStructure.AgentDraft noNameDraft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            noNameDraft.agentName = ' ';
            AIAgentWizardDataStructure.AgentDraft takenDraft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            takenDraft.developerName = existingAgent.DeveloperName__c;
            AIAgentWizardDataStructure.AgentDraft zeroDraft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            zeroDraft.maxMessagesPerConversation = 0;
            String activationRefusal;
            String nameRefusal;
            String takenRefusal;
            String zeroRefusal;

            // [2] Save each
            Test.startTest();
                try { AIAgentWizardSaveService.saveAgent(noModelDraft, true); } catch (Exception ex) { activationRefusal = ex.getMessage(); }
                try { AIAgentWizardSaveService.saveAgent(noNameDraft, false); } catch (Exception ex) { nameRefusal = ex.getMessage(); }
                try { AIAgentWizardSaveService.saveAgent(takenDraft, false); } catch (Exception ex) { takenRefusal = ex.getMessage(); }
                try { AIAgentWizardSaveService.saveAgent(zeroDraft, false); } catch (Exception ex) { zeroRefusal = ex.getMessage(); }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(Label.AI_Wizard_Error_Cannot_Activate, activationRefusal, 'Activation is refused with a blocker.');
            Assert.areEqual(Label.AI_Wizard_Finding_NameRequired_Message, nameRefusal, 'A blank name is refused.');
            Assert.areEqual(Label.AI_Wizard_Finding_DeveloperNameTaken_Message, takenRefusal, 'A taken API name is refused.');
            Assert.areEqual(Label.AI_Wizard_Finding_ConversationLimitsMustBePositive_Message, zeroRefusal, 'A limit of zero is refused.');
            Assert.areEqual(1, [SELECT COUNT() FROM AIAgent__c], 'Nothing was saved.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an id that belongs to nothing, a link to a data source that was deleted, a line with nobody, and a bad choice
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIDataSource__c deletedDataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true)[0];
            delete deletedDataSource;
            AIAgentWizardDataStructure.AgentDraft missingDraft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            missingDraft.agentId = AIAgent__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() + '000000000001AAA';
            AIAgentWizardDataStructure.AgentDraft itemDraft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            itemDraft.dataSourceIds = new List<Id>{deletedDataSource.Id};
            AIAgentWizardDataStructure.AgentDraft assigneeDraft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            assigneeDraft.assignments.add(new AIAgentWizardDataStructure.AssignmentView());
            AIAgentWizardDataStructure.AgentDraft choiceDraft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            choiceDraft.conversationVisibility = 'Nobody';
            String missingRefusal;
            String itemRefusal;
            String assigneeRefusal;
            String choiceRefusal;
            String noDraftRefusal;

            // [2] Save each
            Test.startTest();
                try { AIAgentWizardSaveService.saveAgent(missingDraft, false); } catch (Exception ex) { missingRefusal = ex.getMessage(); }
                try { AIAgentWizardSaveService.saveAgent(itemDraft, false); } catch (Exception ex) { itemRefusal = ex.getMessage(); }
                try { AIAgentWizardSaveService.saveAgent(assigneeDraft, false); } catch (Exception ex) { assigneeRefusal = ex.getMessage(); }
                try { AIAgentWizardSaveService.saveAgent(choiceDraft, false); } catch (Exception ex) { choiceRefusal = ex.getMessage(); }
                try { AIAgentWizardSaveService.saveAgent(null, false); } catch (Exception ex) { noDraftRefusal = ex.getMessage(); }
            Test.stopTest();

            // [3] Check the outcome
            String visibilityLabel = AIAgent__c.ConversationVisibility__c.getDescribe().getLabel();
            Assert.areEqual(Label.AI_Wizard_Error_Not_Found, missingRefusal, 'An id that belongs to nothing is refused.');
            Assert.areEqual(Label.AI_Wizard_Error_Item_Missing, itemRefusal, 'A data source that is gone is refused.');
            Assert.areEqual(Label.AI_Wizard_Error_Assignee, assigneeRefusal, 'A line with nobody is refused.');
            Assert.areEqual(String.format(Label.AI_Settings_Error_Choice, new List<String>{visibilityLabel}), choiceRefusal, 'A choice the pick list does not offer is refused.');
            Assert.areEqual(Label.AI_Wizard_Error_Draft_Required, noDraftRefusal, 'A missing draft is refused.');
            Assert.areEqual(0, [SELECT COUNT() FROM AIAgent__c], 'Nothing was saved.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set, and a draft
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(null);
            String refusal;

            // [2] Save as that user
            Test.startTest();
                System.runAs(users[0]) {
                    try { AIAgentWizardSaveService.saveAgent(draft, false); } catch (Exception ex) { refusal = ex.getMessage(); }
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(Label.AI_Settings_Error_Access, refusal, 'The access label should be shown.');
        }
    }

    @IsTest static void testScenario8() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a switched off agent that is ready to be activated
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, false)[0];
            agent.IsActive__c = false;
            agent.ObjectApiNames__c = 'Account';
            insert agent;
            AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, true);

            // [2] Switch it on, then off, then on again and off with no value
            Test.startTest();
                AIAgentWizardDataStructure.AgentRow onRow = AIAgentWizardSaveService.setAgentActive(agent.Id, true);
                Boolean isActiveAfterOn = [SELECT IsActive__c FROM AIAgent__c WHERE Id = :agent.Id].IsActive__c;
                AIAgentWizardDataStructure.AgentRow offRow = AIAgentWizardSaveService.setAgentActive(agent.Id, false);
                Boolean isActiveAfterOff = [SELECT IsActive__c FROM AIAgent__c WHERE Id = :agent.Id].IsActive__c;
                AIAgentWizardSaveService.setAgentActive(agent.Id, true);
                AIAgentWizardDataStructure.AgentRow nullRow = AIAgentWizardSaveService.setAgentActive(agent.Id, null);
            Test.stopTest();

            // [3] Check the outcome
            Assert.isTrue(isActiveAfterOn, 'The agent should be live after it is switched on.');
            Assert.isTrue(onRow.isActive, 'The row should say the agent is live.');
            Assert.areEqual(agent.Name, onRow.name, 'The row should be the agent that was changed.');
            Assert.isFalse(isActiveAfterOff, 'The agent should be off after it is switched off.');
            Assert.isFalse(offRow.isActive, 'The row should say the agent is off.');
            Assert.isFalse(nullRow.isActive, 'No value switches the agent off.');
        }
    }

    @IsTest static void testScenario9() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a switched off agent that has an object and no model
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, null, false)[0];
            agent.ObjectApiNames__c = 'Account';
            insert agent;
            String refusal;

            // [2] Try to switch it on
            Test.startTest();
                try { AIAgentWizardSaveService.setAgentActive(agent.Id, true); } catch (Exception ex) { refusal = ex.getMessage(); }
            Test.stopTest();

            // [3] Read the agent
            Boolean isActive = [SELECT IsActive__c FROM AIAgent__c WHERE Id = :agent.Id].IsActive__c;

            // [4] Check the outcome
            Assert.areEqual(Label.AI_Wizard_Finding_NoModel_Message, refusal, 'The text of the blocker should be shown.');
            Assert.isFalse(isActive, 'The agent should stay off.');
        }
    }

    @IsTest static void testScenario10() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the Id of an agent that was never saved, and a user who holds only the end user permission set
            Id missingId = AIAgent__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() + '000000000001AAA';
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            String missingRefusal;
            String accessRefusal;

            // [2] Switch off the missing agent, and switch one off as the user
            Test.startTest();
                try { AIAgentWizardSaveService.setAgentActive(missingId, false); } catch (Exception ex) { missingRefusal = ex.getMessage(); }

                System.runAs(users[0]) {
                    try { AIAgentWizardSaveService.setAgentActive(missingId, false); } catch (Exception ex) { accessRefusal = ex.getMessage(); }
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(Label.AI_Wizard_Error_Not_Found, missingRefusal, 'An agent that is gone is refused.');
            Assert.areEqual(Label.AI_Settings_Error_Access, accessRefusal, 'The access label should be shown.');
        }
    }
}
