/*
Class Name: AIAgentWizardCheckServiceTest

=================================================================
=================================================================

Description: Testing utility for AIAgentWizardCheckService: the checks of a draft, the user check, the access counts, the check of many agents and the assignee search.

=================================================================
=================================================================
Applicable Classes:

AIAgentWizardCheckService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIAgentWizardCheckServiceTest {

    // testScenario1: A complete draft with an active model and a template is checked -> no blocker, the agent can be activated, and the users who would see it are counted.
    // testScenario2: An empty draft is checked -> every blocker is found with its step, and the missing template is a warning.
    // testScenario3: An API name with a bad shape, one that another agent uses, and one the agent being changed uses itself -> the first two are blockers and the third is fine.
    // testScenario4: A draft with a switched off model and a retention limit of zero -> the model is a warning and the limit is a blocker on the Conversations step.
    // testScenario5: Data sources and actions that are off, bound to another object or run a flow with no active version, with workflow actions switched off -> each is a warning for its item.
    // testScenario6: More than 64 data sources and 64 actions -> each is a warning, and a limit of zero in the Limits step is a blocker there.
    // testScenario7: Global conversations, a token limit over the policy and tool rounds over the org cap -> each is a warning.
    // testScenario8: An assigned only agent with nobody assigned and no active usage policy -> both are warnings.
    // testScenario9: Users are checked against an agent open to all, assigned by name, and assigned through a permission set -> each has access with its own reason.
    // testScenario10: A switched off user, a user with no permission set, a user who is not assigned and a user with no usage policy -> each has no access with its own reason.
    // testScenario11: A user who does not exist, no draft and a user without the Manage Settings permission -> each is refused.
    // testScenario12: The users and permission sets are searched with text that is too short, then with text that matches -> the first is empty and the second finds both kinds.
    // testScenario13: The access list has a user and a permission set that overlap, and a switched off line -> each user is counted once and the switched off line is not counted.
    // testScenario14: The active flow versions of no flows are read -> the map is empty.
    // testScenario15: A user holds the end user permission set only through a permission set group that is assigned to the agent -> the user has the agent and the group's holder is counted.
    // testScenario16: No agents, an empty list of agents and a user without the Manage Settings permission are checked together -> the first two give nothing and the third is refused.
    // testScenario17: Three saved agents are checked together: one ready, one with nothing, one with a switched off model, data source and action -> each gets the findings of checkDraft and its own user count.
    // testScenario18: The users of an agent open to all, an agent with a switched off line and an agent with overlapping lines are counted together -> each count is the count of that agent alone.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a complete draft with an active model and an active template
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIPromptTemplate__c promptTemplate = AIAssistTestDataFactory.createAIPromptTemplates(null, 1, true)[0];
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            draft.promptTemplateId = promptTemplate.Id;

            // [2] Check it
            Test.startTest();
                AIAgentWizardDataStructure.DraftCheck check = AIAgentWizardCheckService.checkDraft(draft);
            Test.stopTest();

            // [3] Check the outcome
            Assert.isTrue(check.findings.isEmpty(), 'A complete draft should have no finding.');
            Assert.isTrue(check.canActivate, 'It can be activated.');
            Assert.isFalse(check.isDeveloperNameTaken, 'The API name is free.');
            Assert.isTrue(check.accessUserCount >= 1, 'An agent open to all is seen by the AI Assist users.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an empty draft with a limit of zero
            AIAgentWizardDataStructure.AgentDraft draft = new AIAgentWizardDataStructure.AgentDraft();
            draft.maxTokensPerConversation = 0;

            // [2] Check it
            Test.startTest();
                AIAgentWizardDataStructure.DraftCheck check = AIAgentWizardCheckService.checkDraft(draft);
            Test.stopTest();

            // [3] Note each finding by its code
            Map<String, AIAgentWizardDataStructure.Finding> findingByCode = new Map<String, AIAgentWizardDataStructure.Finding>();

            for (AIAgentWizardDataStructure.Finding finding : check.findings) {

                findingByCode.put(finding.code, finding);
            }

            // [4] Check the outcome
            Assert.isFalse(check.canActivate, 'It cannot be activated.');
            Assert.areEqual(AIAssistApplicationConstants.WIZARD_SEVERITY_BLOCKER, findingByCode.get('NameRequired').severity, 'The name is a blocker.');
            Assert.areEqual(1, findingByCode.get('NameRequired').step, 'The name is fixed on the Basics step.');
            Assert.areEqual(Label.AI_Wizard_Finding_NameRequired_Title, findingByCode.get('NameRequired').title, 'The title is the label.');
            Assert.isTrue(findingByCode.containsKey('DeveloperNameRequired'), 'The API name is required.');
            Assert.isTrue(findingByCode.containsKey('ObjectsRequired'), 'An object is required.');
            Assert.areEqual(2, findingByCode.get('NoModel').step, 'The model is fixed on the Model step.');
            Assert.areEqual(6, findingByCode.get('ConversationLimitsMustBePositive').step, 'A token limit of zero is fixed on the Limits step.');
            Assert.areEqual(AIAssistApplicationConstants.WIZARD_SEVERITY_WARNING, findingByCode.get('NoTemplate').severity, 'A missing template is a warning.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent, and build drafts with a bad API name, the agent's API name, and the agent being changed
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIAgentWizardDataStructure.AgentDraft badDraft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            badDraft.developerName = '1 bad name';
            AIAgentWizardDataStructure.AgentDraft takenDraft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            takenDraft.developerName = agent.DeveloperName__c;
            AIAgentWizardDataStructure.AgentDraft ownDraft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            ownDraft.developerName = agent.DeveloperName__c;
            ownDraft.agentId = agent.Id;

            // [2] Check each
            Test.startTest();
                AIAgentWizardDataStructure.DraftCheck badCheck = AIAgentWizardCheckService.checkDraft(badDraft);
                AIAgentWizardDataStructure.DraftCheck takenCheck = AIAgentWizardCheckService.checkDraft(takenDraft);
                AIAgentWizardDataStructure.DraftCheck ownCheck = AIAgentWizardCheckService.checkDraft(ownDraft);
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual('DeveloperNameFormat', badCheck.findings[0].code, 'The shape is refused.');
            Assert.areEqual('DeveloperNameTaken', takenCheck.findings[0].code, 'A name another agent uses is refused.');
            Assert.isTrue(takenCheck.isDeveloperNameTaken, 'The check says the name is taken.');
            Assert.isFalse(ownCheck.isDeveloperNameTaken, 'An agent may keep its own name.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a draft that uses a model that is switched off, with a retention limit of zero
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.IsActive__c = false;
            insert model;
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            draft.conversationRetentionDays = 0;

            // [2] Check it
            Test.startTest();
                AIAgentWizardDataStructure.DraftCheck check = AIAgentWizardCheckService.checkDraft(draft);
            Test.stopTest();

            // [3] Note each finding by its code
            Map<String, AIAgentWizardDataStructure.Finding> findingByCode = new Map<String, AIAgentWizardDataStructure.Finding>();

            for (AIAgentWizardDataStructure.Finding finding : check.findings) {

                findingByCode.put(finding.code, finding);
            }

            // [4] Check the outcome
            Assert.areEqual(AIAssistApplicationConstants.WIZARD_SEVERITY_WARNING, findingByCode.get('ModelInactive').severity, 'A model that is off is a warning.');
            Assert.areEqual(AIAssistApplicationConstants.WIZARD_SEVERITY_BLOCKER, findingByCode.get('ConversationLimitsMustBePositive').severity, 'A limit of zero is a blocker.');
            Assert.areEqual(5, findingByCode.get('ConversationLimitsMustBePositive').step, 'A retention limit is fixed on the Conversations step.');
            Assert.isFalse(check.canActivate, 'It cannot be activated.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a data source that is off and bound to Contact, and two actions: a flow with no active version for Contact, and one that is off
            AIAssistTestDataFactory.upsertUiSettings(false);
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Contact', false)[0];
            dataSource.IsActive__c = false;
            dataSource.BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
            dataSource.TargetObject__c = 'Contact';
            insert dataSource;
            AIWorkflowAction__c flowAction = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'Missing_Flow_For_Wizard', false)[0];
            flowAction.TargetObject__c = 'Contact';
            insert flowAction;
            AIWorkflowAction__c offAction = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', false)[0];
            offAction.IsActive__c = false;
            insert offAction;

            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            draft.dataSourceIds = new List<Id>{dataSource.Id};
            draft.workflowActionIds = new List<Id>{flowAction.Id, offAction.Id};

            // [2] Check it
            Test.startTest();
                AIAgentWizardDataStructure.DraftCheck check = AIAgentWizardCheckService.checkDraft(draft);
            Test.stopTest();

            // [3] Note each finding by its code and item
            Set<String> codeAndItems = new Set<String>();

            for (AIAgentWizardDataStructure.Finding finding : check.findings) {

                codeAndItems.add(finding.code + '|' + finding.itemId);
            }

            // [4] Check the outcome
            Assert.isTrue(codeAndItems.contains('ItemInactive|' + dataSource.Id), 'The data source that is off is found.');
            Assert.isTrue(codeAndItems.contains('ObjectNotOnAgent|' + dataSource.Id), 'The data source bound to another object is found.');
            Assert.isTrue(codeAndItems.contains('FlowNoActiveVersion|' + flowAction.Id), 'The flow with no active version is found.');
            Assert.isTrue(codeAndItems.contains('ObjectNotOnAgent|' + flowAction.Id), 'The action for another object is found.');
            Assert.isTrue(codeAndItems.contains('ItemInactive|' + offAction.Id), 'The action that is off is found.');
            Assert.isTrue(codeAndItems.contains('WorkflowActionsDisabled|null'), 'The org setting that is off is found.');
            Assert.isTrue(check.canActivate, 'Warnings do not stop the agent being activated.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Link more than 64 data sources and actions to a draft, with a tool round limit of zero
            AIAssistTestDataFactory.upsertUiSettings(true);
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            List<AIDataSource__c> dataSources = AIAssistTestDataFactory.createAIDataSources(65, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true);
            List<AIWorkflowAction__c> actions = AIAssistTestDataFactory.createAIWorkflowActions(65, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', true);
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            draft.maxToolCallingIterations = 0;

            for (AIDataSource__c dataSource : dataSources) {

                draft.dataSourceIds.add(dataSource.Id);
            }

            for (AIWorkflowAction__c action : actions) {

                draft.workflowActionIds.add(action.Id);
            }

            // [2] Check it
            Test.startTest();
                AIAgentWizardDataStructure.DraftCheck check = AIAgentWizardCheckService.checkDraft(draft);
            Test.stopTest();

            // [3] Note each finding by its code
            Map<String, AIAgentWizardDataStructure.Finding> findingByCode = new Map<String, AIAgentWizardDataStructure.Finding>();

            for (AIAgentWizardDataStructure.Finding finding : check.findings) {

                findingByCode.put(finding.code, finding);
            }

            // [4] Check the outcome
            Assert.areEqual(3, findingByCode.get('TooManyDataSources').step, 'Too many data sources is found on the Data sources step.');
            Assert.areEqual(4, findingByCode.get('TooManyActions').step, 'Too many actions is found on the Workflow actions step.');
            Assert.isFalse(findingByCode.containsKey('WorkflowActionsDisabled'), 'The org has workflow actions on.');
            Assert.areEqual(6, findingByCode.get('ConversationLimitsMustBePositive').step, 'A tool round limit of zero is fixed on the Limits step.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Add a default policy with a daily token limit, and build a draft that is over it, over the org cap and global
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { insert new AIUsagePolicy__c(Name = 'Small default', IsActive__c = true, IsDefault__c = true, MaxTokensPer24Hours__c = 1000); }

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            draft.conversationVisibility = AIAssistApplicationConstants.AGENT_VISIBILITY_GLOBAL;
            draft.maxTokensPerConversation = 50000;
            draft.maxToolCallingIterations = 100000;

            // [2] Check it
            Test.startTest();
                AIAgentWizardDataStructure.DraftCheck check = AIAgentWizardCheckService.checkDraft(draft);
                AIAgentWizardDataStructure.PolicyInfo policy = AIAgentWizardCheckService.getPolicyInfo();
            Test.stopTest();

            // [3] Note each finding by its code
            Set<String> codes = new Set<String>();

            for (AIAgentWizardDataStructure.Finding finding : check.findings) {

                codes.add(finding.code);
            }

            // [4] Check the outcome
            Assert.isTrue(codes.contains('GlobalVisibility'), 'Global conversations are found.');
            Assert.isTrue(codes.contains('TokensOverPolicy'), 'A limit over the policy is found.');
            Assert.isTrue(codes.contains('ToolRoundsOverCap'), 'Tool rounds over the cap are found.');
            Assert.areEqual('Small default', policy.policyName, 'The strictest default policy is reported.');
            Assert.areEqual(1000, policy.maxTokensPer24Hours, 'Its token limit is reported.');
        }
    }

    @IsTest static void testScenario8() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Switch every usage policy off, and build an assigned only draft with nobody assigned
            AIAssistTestDataFactory.deactivateUsagePolicies();
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            draft.accessMode = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;

            // [2] Check it
            Test.startTest();
                AIAgentWizardDataStructure.DraftCheck check = AIAgentWizardCheckService.checkDraft(draft);
                AIAgentWizardDataStructure.PolicyInfo policy = AIAgentWizardCheckService.getPolicyInfo();
            Test.stopTest();

            // [3] Note each finding by its code
            Set<String> codes = new Set<String>();

            for (AIAgentWizardDataStructure.Finding finding : check.findings) {

                codes.add(finding.code);
            }

            // [4] Check the outcome
            Assert.isTrue(codes.contains('NoAssignments'), 'Nobody assigned is found.');
            Assert.isTrue(codes.contains('NoPolicy'), 'No usage policy is found.');
            Assert.isNull(policy, 'There is no policy to report.');
            Assert.areEqual(0, check.accessUserCount, 'Nobody would see the agent.');
        }
    }

    @IsTest static void testScenario9() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create three users with the end user permission set, and build drafts for each way in
            List<User> users = AIAssistTestDataFactory.createUsers(3, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgentWizardDataStructure.AgentDraft openDraft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            AIAgentWizardDataStructure.AgentDraft nameDraft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            nameDraft.accessMode = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
            nameDraft.assignments.add(AIAssistTestDataFactory.createAIAssignmentView(users[1].Id, null));
            AIAgentWizardDataStructure.AgentDraft setDraft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            setDraft.accessMode = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
            setDraft.assignments.add(AIAssistTestDataFactory.createAIAssignmentView(null, 'AIAssistUser'));
            setDraft.assignments[0].label = 'AI Assist User';

            // [2] Check each user
            Test.startTest();
                AIAgentWizardDataStructure.UserCheck openCheck = AIAgentWizardCheckService.checkUser(openDraft, users[0].Id);
                AIAgentWizardDataStructure.UserCheck nameCheck = AIAgentWizardCheckService.checkUser(nameDraft, users[1].Id);
                AIAgentWizardDataStructure.UserCheck setCheck = AIAgentWizardCheckService.checkUser(setDraft, users[2].Id);
            Test.stopTest();

            // [3] Check the outcome
            Assert.isTrue(openCheck.hasAccess, 'A user has an agent that is open to all.');
            Assert.areEqual(Label.AI_Wizard_User_Reason_All_Users, openCheck.reason, 'The reason says it is open to all.');
            Assert.areEqual(users[0].Id, openCheck.userId, 'The user is reported.');
            Assert.isTrue(nameCheck.hasAccess, 'A user assigned by name has the agent.');
            Assert.areEqual(Label.AI_Wizard_User_Reason_Assigned_User, nameCheck.reason, 'The reason says the user is assigned.');
            Assert.isTrue(setCheck.hasAccess, 'A holder of an assigned permission set has the agent.');
            Assert.areEqual(String.format(Label.AI_Wizard_User_Reason_Assigned_Set, new List<String>{'AI Assist User'}), setCheck.reason, 'The reason names the permission set by its label.');
        }
    }

    @IsTest static void testScenario10() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a switched off user, a user with no permission set, a user who is not assigned, and a user to check with no policy
            List<User> users = AIAssistTestDataFactory.createUsers(4, true);
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{users[0], users[2], users[3]}, 'AIAssistUser');
            users[0].IsActive = false;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update users[0]; }

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgentWizardDataStructure.AgentDraft openDraft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            AIAgentWizardDataStructure.AgentDraft assignedDraft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            assignedDraft.accessMode = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
            AIAgentWizardDataStructure.AgentDraft staleDraft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            staleDraft.accessMode = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
            staleDraft.assignments.add(AIAssistTestDataFactory.createAIAssignmentView(users[2].Id, null));
            staleDraft.assignments[0].isActive = false;

            // [2] Check each user, the last with every usage policy switched off
            Test.startTest();
                AIAgentWizardDataStructure.UserCheck offCheck = AIAgentWizardCheckService.checkUser(openDraft, users[0].Id);
                AIAgentWizardDataStructure.UserCheck bareCheck = AIAgentWizardCheckService.checkUser(openDraft, users[1].Id);
                AIAgentWizardDataStructure.UserCheck unassignedCheck = AIAgentWizardCheckService.checkUser(assignedDraft, users[2].Id);
                AIAgentWizardDataStructure.UserCheck staleCheck = AIAgentWizardCheckService.checkUser(staleDraft, users[2].Id);
                AIAssistTestDataFactory.deactivateUsagePolicies();
                AIAgentWizardDataStructure.UserCheck policyCheck = AIAgentWizardCheckService.checkUser(openDraft, users[3].Id);
            Test.stopTest();

            // [3] Check the outcome
            Assert.isFalse(offCheck.hasAccess, 'A switched off user has nothing.');
            Assert.areEqual(Label.AI_Wizard_User_Reason_Inactive, offCheck.reason, 'The reason says the user is switched off.');
            Assert.isFalse(bareCheck.hasAccess, 'A user with no permission set has nothing.');
            Assert.areEqual(Label.AI_Wizard_User_Reason_No_Permission_Set, bareCheck.reason, 'The reason says there is no permission set.');
            Assert.isFalse(unassignedCheck.hasAccess, 'A user who is not assigned has nothing.');
            Assert.areEqual(Label.AI_Wizard_User_Reason_Not_Assigned, unassignedCheck.reason, 'The reason says the user is not assigned.');
            Assert.isFalse(staleCheck.hasAccess, 'A line that is switched off does not count.');
            Assert.isFalse(policyCheck.hasAccess, 'A user with no usage policy cannot send.');
            Assert.areEqual(Label.AI_Wizard_User_Reason_No_Policy, policyCheck.reason, 'The reason says there is no policy.');
        }
    }

    @IsTest static void testScenario11() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set, and a draft
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(null);
            Id missingUserId = User.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
            String missingUserRefusal;
            String noDraftCheckRefusal;
            String noDraftUserRefusal;
            String accessRefusal;

            // [2] Make each call
            Test.startTest();
                try { AIAgentWizardCheckService.checkUser(draft, missingUserId); } catch (Exception ex) { missingUserRefusal = ex.getMessage(); }
                try { AIAgentWizardCheckService.checkDraft(null); } catch (Exception ex) { noDraftCheckRefusal = ex.getMessage(); }
                try { AIAgentWizardCheckService.checkUser(null, users[0].Id); } catch (Exception ex) { noDraftUserRefusal = ex.getMessage(); }

                System.runAs(users[0]) {
                    try { AIAgentWizardCheckService.checkDraft(draft); } catch (Exception ex) { accessRefusal = ex.getMessage(); }
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(Label.AI_Wizard_Error_User_Not_Found, missingUserRefusal, 'A user who is gone is refused.');
            Assert.areEqual(Label.AI_Wizard_Error_Draft_Required, noDraftCheckRefusal, 'A missing draft is refused.');
            Assert.areEqual(Label.AI_Wizard_Error_Draft_Required, noDraftUserRefusal, 'A missing draft is refused for the user check too.');
            Assert.areEqual(Label.AI_Settings_Error_Access, accessRefusal, 'The access label should be shown.');
        }
    }

    @IsTest static void testScenario12() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user to find
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);

            // [2] Search with too little text, then with text that matches both kinds
            Test.startTest();
                List<AIAgentWizardDataStructure.AssigneeOption> shortOptions = AIAgentWizardCheckService.searchAssignees('a');
                List<AIAgentWizardDataStructure.AssigneeOption> options = AIAgentWizardCheckService.searchAssignees('AIAssistUser');
                List<AIAgentWizardDataStructure.AssigneeOption> userOptions = AIAgentWizardCheckService.searchAssignees(users[0].Username);
            Test.stopTest();

            // [3] Find the permission set and the user in the results
            AIAgentWizardDataStructure.AssigneeOption permissionSetOption;
            AIAgentWizardDataStructure.AssigneeOption userOption;

            for (AIAgentWizardDataStructure.AssigneeOption option : options) {

                if (option.permissionSetName == 'AIAssistUser') permissionSetOption = option;
            }

            for (AIAgentWizardDataStructure.AssigneeOption option : userOptions) {

                if (option.userId == users[0].Id) userOption = option;
            }

            // [4] Check the outcome
            Assert.isTrue(shortOptions.isEmpty(), 'Text that is too short finds nothing.');
            Assert.isNotNull(permissionSetOption, 'The permission set is found.');
            Assert.areEqual(AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, permissionSetOption.assigneeType, 'It is a permission set.');
            Assert.isNotNull(permissionSetOption.userCount, 'The holders are counted.');
            Assert.isNotNull(userOption, 'The user is found by username.');
            Assert.areEqual(AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, userOption.assigneeType, 'It is a user.');
            Assert.areEqual(1, userOption.userCount, 'A user covers one user.');
        }
    }

    @IsTest static void testScenario13() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two holders of the permission set, and a draft that names one of them, a third user, the permission set, and a user whose line is off
            List<User> users = AIAssistTestDataFactory.createUsers(4, true);
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{users[0], users[1]}, 'AIAssistUser');
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(null);
            draft.accessMode = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
            draft.assignments.add(AIAssistTestDataFactory.createAIAssignmentView(users[0].Id, null));
            draft.assignments.add(AIAssistTestDataFactory.createAIAssignmentView(users[2].Id, null));
            draft.assignments.add(AIAssistTestDataFactory.createAIAssignmentView(users[3].Id, null));
            draft.assignments[2].isActive = false;
            AIAgentWizardDataStructure.AgentDraft namedDraft = AIAssistTestDataFactory.createAIAgentDraft(null);
            namedDraft.accessMode = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
            namedDraft.assignments = draft.assignments.clone();
            draft.assignments.add(AIAssistTestDataFactory.createAIAssignmentView(null, 'AIAssistUser'));

            // [2] Count them, and count the AI Assist users
            Test.startTest();
                Integer namedCount = AIAgentWizardCheckService.getAccessUserCount(namedDraft);
                Integer assignedCount = AIAgentWizardCheckService.getAccessUserCount(draft);
                Integer assistCount = AIAgentWizardCheckService.getAssistUserCount();
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(2, namedCount, 'Two active users are named and the third line is switched off.');
            Assert.isTrue(assignedCount >= 3, 'The named users and the holders are counted, each once.');
            Assert.isTrue(assistCount >= 3, 'The super user and the two holders are AI Assist users.');
        }
    }

    @IsTest static void testScenario14() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Read the active versions of no flows
            Test.startTest();
                Map<String, Integer> versions = AIAgentWizardCheckService.getActiveFlowVersions(new Set<String>());
            Test.stopTest();

            // [2] Check the outcome
            Assert.isTrue(versions.isEmpty(), 'No flows have no versions.');
        }
    }

    @IsTest static void testScenario15() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds the end user permission set only through a group, and a draft that assigns the group
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            PermissionSetGroup permissionSetGroup = new PermissionSetGroup(DeveloperName = 'AIWizardCheckGroup', MasterLabel = 'AI Wizard Check Group');
            Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'AIAssistUser' LIMIT 1].Id;

            System.runAs(AIAssistTestDataFactory.getSetupUser()) {

                insert permissionSetGroup;
                insert new PermissionSetGroupComponent(PermissionSetGroupId = permissionSetGroup.Id, PermissionSetId = permissionSetId);
                Test.calculatePermissionSetGroup(permissionSetGroup.Id);
                insert new PermissionSetAssignment(AssigneeId = users[0].Id, PermissionSetGroupId = permissionSetGroup.Id);
            }

            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(null);
            draft.accessMode = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
            draft.assignments.add(AIAssistTestDataFactory.createAIAssignmentView(null, 'AIWizardCheckGroup'));

            // [2] Check the user and count who has the agent
            Test.startTest();
                AIAgentWizardDataStructure.UserCheck check = AIAgentWizardCheckService.checkUser(draft, users[0].Id);
                Integer count = AIAgentWizardCheckService.getAccessUserCount(draft);
            Test.stopTest();

            // [3] Check the outcome
            Assert.isTrue(check.hasAccess, 'A holder of the assigned group has the agent.');
            Assert.areEqual(1, count, 'The holder of the group is counted.');
        }
    }

    @IsTest static void testScenario16() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            String accessRefusal;

            // [2] Check no agents and an empty list of agents, then check as the user
            Test.startTest();
                Map<Id, AIAgentWizardDataStructure.DraftCheck> nullChecks = AIAgentWizardCheckService.checkAgents(null);
                Map<Id, AIAgentWizardDataStructure.DraftCheck> emptyChecks = AIAgentWizardCheckService.checkAgents(new List<AIAgentWizardDataStructure.AgentDraft>());

                System.runAs(users[0]) {
                    try { AIAgentWizardCheckService.checkAgents(new List<AIAgentWizardDataStructure.AgentDraft>()); } catch (Exception ex) { accessRefusal = ex.getMessage(); }
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.isTrue(nullChecks.isEmpty(), 'No list gives no checks.');
            Assert.isTrue(emptyChecks.isEmpty(), 'An empty list gives no checks.');
            Assert.areEqual(Label.AI_Settings_Error_Access, accessRefusal, 'The access label should be shown.');
        }
    }

    @IsTest static void testScenario17() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a policy, an active and a switched off model, a template, a data source and an action, and two users
            AIAssistTestDataFactory.createDefaultUsagePolicy();
            AIAssistTestDataFactory.upsertUiSettings(true);
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{users[1]}, 'AIAssistUser');
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIModelConfiguration__c offModel = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            offModel.IsActive__c = false;
            insert offModel;
            AIPromptTemplate__c promptTemplate = AIAssistTestDataFactory.createAIPromptTemplates(null, 1, true)[0];
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Contact', false)[0];
            dataSource.IsActive__c = false;
            dataSource.BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
            dataSource.TargetObject__c = 'Contact';
            insert dataSource;
            AIWorkflowAction__c flowAction = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'Missing_Flow_For_Wizard', false)[0];
            flowAction.TargetObject__c = 'Contact';
            insert flowAction;
            List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(3, model.Id, true);

            // [2] Build three drafts: one that is ready, one with nothing, and one with a switched off model, data source and action
            AIAgentWizardDataStructure.AgentDraft readyDraft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            readyDraft.agentId = agents[0].Id;
            readyDraft.promptTemplateId = promptTemplate.Id;
            AIAgentWizardDataStructure.AgentDraft emptyDraft = new AIAgentWizardDataStructure.AgentDraft();
            emptyDraft.agentId = agents[1].Id;
            AIAgentWizardDataStructure.AgentDraft offDraft = AIAssistTestDataFactory.createAIAgentDraft(offModel.Id);
            offDraft.agentId = agents[2].Id;
            offDraft.promptTemplateId = promptTemplate.Id;
            offDraft.accessMode = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
            offDraft.dataSourceIds.add(dataSource.Id);
            offDraft.workflowActionIds.add(flowAction.Id);
            offDraft.assignments.add(AIAssistTestDataFactory.createAIAssignmentView(users[0].Id, null));
            offDraft.assignments.add(AIAssistTestDataFactory.createAIAssignmentView(null, 'AIAssistUser'));

            // [3] Check them together
            Test.startTest();
                Map<Id, AIAgentWizardDataStructure.DraftCheck> checks = AIAgentWizardCheckService.checkAgents(new List<AIAgentWizardDataStructure.AgentDraft>{readyDraft, emptyDraft, offDraft});
            Test.stopTest();

            // [4] Note each finding of the draft with the most findings by its code and item
            Set<String> readyCodes = new Set<String>();
            Set<String> emptyCodes = new Set<String>();
            Set<String> offCodes = new Set<String>();

            for (AIAgentWizardDataStructure.Finding finding : checks.get(agents[0].Id).findings) readyCodes.add(finding.code + '|' + finding.itemId);

            for (AIAgentWizardDataStructure.Finding finding : checks.get(agents[1].Id).findings) emptyCodes.add(finding.code + '|' + finding.itemId);

            for (AIAgentWizardDataStructure.Finding finding : checks.get(agents[2].Id).findings) offCodes.add(finding.code + '|' + finding.itemId);

            // [5] Check the outcome
            Assert.isTrue(readyCodes.isEmpty(), 'An agent that is ready has no finding.');
            Assert.isTrue(checks.get(agents[0].Id).canActivate, 'An agent that is ready can be activated.');
            Assert.isTrue(checks.get(agents[0].Id).accessUserCount >= 1, 'An agent open to all is seen by the AI Assist users.');
            Assert.isTrue(emptyCodes.contains('NoModel|null'), 'An agent with no model is found.');
            Assert.isTrue(emptyCodes.contains('ObjectsRequired|null'), 'An agent with no object is found.');
            Assert.isTrue(emptyCodes.contains('NoTemplate|null'), 'An agent with no template and no default is found.');
            Assert.isTrue(emptyCodes.contains('NoAssignments|null'), 'An assigned only agent with nobody is found.');
            Assert.isFalse(checks.get(agents[1].Id).canActivate, 'Blockers stop the activation.');
            Assert.isTrue(offCodes.contains('ModelInactive|null'), 'The switched off model is found.');
            Assert.isTrue(offCodes.contains('ItemInactive|' + dataSource.Id), 'The data source that is off is found.');
            Assert.isTrue(offCodes.contains('ObjectNotOnAgent|' + dataSource.Id), 'The data source bound to another object is found.');
            Assert.isTrue(offCodes.contains('FlowNoActiveVersion|' + flowAction.Id), 'The flow with no active version is found.');
            Assert.isTrue(offCodes.contains('ObjectNotOnAgent|' + flowAction.Id), 'The action for another object is found.');
            Assert.isTrue(checks.get(agents[2].Id).canActivate, 'Warnings do not stop the agent being activated.');
            Assert.isTrue(checks.get(agents[2].Id).accessUserCount >= 2, 'The named user and the holder of the permission set are counted.');
        }
    }

    @IsTest static void testScenario18() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two holders of the permission set, a user who is named, and three agents
            List<User> users = AIAssistTestDataFactory.createUsers(4, true);
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{users[0], users[1]}, 'AIAssistUser');
            List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(3, null, true);
            AIAgentWizardDataStructure.AgentDraft openDraft = AIAssistTestDataFactory.createAIAgentDraft(null);
            openDraft.agentId = agents[0].Id;
            AIAgentWizardDataStructure.AgentDraft namedDraft = AIAssistTestDataFactory.createAIAgentDraft(null);
            namedDraft.agentId = agents[1].Id;
            namedDraft.accessMode = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
            namedDraft.assignments.add(AIAssistTestDataFactory.createAIAssignmentView(users[2].Id, null));
            namedDraft.assignments.add(AIAssistTestDataFactory.createAIAssignmentView(users[3].Id, null));
            namedDraft.assignments[1].isActive = false;
            AIAgentWizardDataStructure.AgentDraft overlapDraft = AIAssistTestDataFactory.createAIAgentDraft(null);
            overlapDraft.agentId = agents[2].Id;
            overlapDraft.accessMode = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
            overlapDraft.assignments.add(AIAssistTestDataFactory.createAIAssignmentView(users[0].Id, null));
            overlapDraft.assignments.add(AIAssistTestDataFactory.createAIAssignmentView(null, 'AIAssistUser'));

            // [2] Count them together, and count each on its own
            Test.startTest();
                Map<Id, Integer> counts = AIAgentWizardCheckService.getAccessUserCounts(new List<AIAgentWizardDataStructure.AgentDraft>{openDraft, namedDraft, overlapDraft});
                Integer openCount = AIAgentWizardCheckService.getAccessUserCount(openDraft);
                Integer overlapCount = AIAgentWizardCheckService.getAccessUserCount(overlapDraft);
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(openCount, counts.get(agents[0].Id), 'An agent open to all counts every AI Assist user.');
            Assert.areEqual(1, counts.get(agents[1].Id), 'One user is named and the other line is switched off.');
            Assert.areEqual(overlapCount, counts.get(agents[2].Id), 'The count of many agents is the count of one.');
            Assert.isTrue(counts.get(agents[2].Id) >= 2, 'The named user and the other holder are counted, each once.');
        }
    }
}
