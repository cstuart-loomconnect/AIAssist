/*
Class Name: AIWorkflowActionDispatcherTest

=================================================================
=================================================================

Description: Testing utility for AIWorkflowActionDispatcher: every gate before a Workflow Action runs, what is shown when it cannot, the evidence recorded on the reply for each outcome, and the record checks made before an action runs: the user's access to every record handed to a Flow, and recordId always being the server's. Flow versions cannot be created in a test, so a Flow that passes the checks goes on to fail at start (Action Failed), which is how "allowed" is told from "refused" (Action Not Permitted).

=================================================================
=================================================================
Applicable Classes:

AIWorkflowActionDispatcher: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIWorkflowActionDispatcherTest {

    // testScenario1: An assigned, active action runs as the user, returns its output, and a Success step records the target and the time -> output returned, Success step recorded.
    // testScenario2: A user without the actions setting, or with no settings at all, is refused -> Action Not Permitted both times.
    // testScenario3: An action that is inactive, not assigned to the agent, or not found is refused the same way, and says nothing about which -> Action Not Permitted for all four.
    // testScenario4: An action that changes data runs only when confirmed, and the step then records who confirmed it and when -> Blocked step then Success step with confirmer and date.
    // testScenario5: A class that does not implement the interface, one that cannot be found, and one that throws all give the Action Failed label with no class name or detail -> label only, a Failed step each.
    // testScenario6: A Flow action whose flow cannot be started fails the same way -> Action Failed and the target record on the step.
    // testScenario7: cancel records that the user declined, and a missing message or action records nothing -> one Cancelled step.
    // testScenario8: Switched off, nothing runs -> Application Inactive.
    // testScenario9: Only inputs the action declares reach it; an undeclared key, and every key when the schema is blank or malformed, is dropped -> only the declared key reaches the action, others empty.
    // testScenario10: A user removed from an Assigned Users Only agent, and a user of an inactive agent, cannot run an action it suggested earlier; restoring the assignment lets it run -> refused, runs, refused.
    // testScenario11: The request carries the action, agent, user, conversation and confirmation, so the class need not look them up -> output holds all five.
    // testScenario12: A Flow handed the Id of a record the user cannot read is refused, a Blocked step is recorded, and the same Flow handed the user's own record gets past the check -> Action Not Permitted, one Blocked step, then Action Failed.
    // testScenario13: A Write Flow needs edit access: a record the user can only read is refused, and a Read Only Flow handed the same record gets past the check -> Action Not Permitted for Write, Action Failed for Read Only.
    // testScenario14: The conversation's own record is checked too: a Flow is refused when the user cannot read it -> Action Not Permitted.
    // testScenario15: A recordId sent by the browser is ignored even when the schema declares it; the action receives the server's record -> output holds the server's record Id and only the targetId input.
    // testScenario16: An input that is not a record Id is not checked -> Action Failed because only the Flow is missing.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    // An action class, one that throws, and one that is not an action at all.
    public class EchoExecutor implements IAIWorkflowActionExecutor {
        public AIWorkflowActionResponse execute(AIWorkflowActionRequest request) {
            return new AIWorkflowActionResponse('echo:' + request.inputParameters.get('x'));
        }
    }

    public class KeysExecutor implements IAIWorkflowActionExecutor {
        public AIWorkflowActionResponse execute(AIWorkflowActionRequest request) {
            List<String> keys = new List<String>(request.inputParameters.keySet());
            keys.sort();
            return new AIWorkflowActionResponse(String.join(keys, ','));
        }
    }

    public class ContextExecutor implements IAIWorkflowActionExecutor {
        public AIWorkflowActionResponse execute(AIWorkflowActionRequest request) {
            return new AIWorkflowActionResponse(String.join(new List<Object>{
                request.actionName,
                request.agentId,
                request.userId,
                request.conversationId,
                request.isConfirmed
            }, '|'));
        }
    }

    public class ThrowingExecutor implements IAIWorkflowActionExecutor {
        public AIWorkflowActionResponse execute(AIWorkflowActionRequest request) {
            throw new CalloutException('Secret internal detail');
        }
    }

    public class NotAnExecutor {
        public Object execute(Id recordId, Map<String, Object> inputParameters) {
            return 'should never run';
        }
    }

    // Hands back the record and input names it received, for the record-access scenarios.
    public class RecordExecutor implements IAIWorkflowActionExecutor {
        public AIWorkflowActionResponse execute(AIWorkflowActionRequest request) {
            return new AIWorkflowActionResponse(request.recordId + '|' + String.join(new List<String>(request.inputParameters.keySet()), ','));
        }
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the data the scenario needs
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, 'AIAssistUser');

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            AIAssistTestDataFactory.upsertUiSettings(true);
            insert userSettings;

            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', true)[0];
            action.InputSchema__c = '{"type":"object","properties":{"x":{"type":"string"}}}';
            update action;
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ action }, true);

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            Object output;

            // [2] Run the action under test as the user
            System.runAs(chatUser) {
                Test.startTest();
                    output = AIWorkflowActionDispatcher.runWorkflowAction(action.Id, agent.Id, reply.Id, null, new Map<String, Object>{ 'x' => 'hello' }, false);
                Test.stopTest();
            }

            // [3] Read the results back
            AIExecutionStep__c step = [SELECT StepType__c, Status__c, AIWorkflowAction__c, RequiredConfirmation__c, DurationMilliseconds__c FROM AIExecutionStep__c WHERE AIConversationMessage__c = :reply.Id];

            // [4] Check the outcome
            Assert.areEqual('echo:hello', output, 'The action\'s output.');

            Assert.areEqual(AIAssistApplicationConstants.STEP_TYPE_WORKFLOW_ACTION, step.StepType__c, 'A Workflow Action step.');
            Assert.areEqual(AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS, step.Status__c, 'Success.');
            Assert.areEqual(action.Id, step.AIWorkflowAction__c, 'The action.');
            Assert.isFalse(step.RequiredConfirmation__c, 'It did not need confirmation.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the data the scenario needs
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, 'AIAssistUser');

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            AIAssistTestDataFactory.upsertUiSettings(true);
            insert userSettings;

            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', true)[0];
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ action }, true);

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            AIAssistTestDataFactory.upsertUiSettings(false);

            List<String> codes = new List<String>();

            // [2] Run the action under test as the user
            System.runAs(chatUser) {
                Test.startTest();
                    try {
                        AIWorkflowActionDispatcher.runWorkflowAction(action.Id, agent.Id, reply.Id, null, null, false);
                    } catch (AIWorkflowActionDispatcher.AIWorkflowActionDispatcherException ex) {
                        codes.add(ex.getMessage());
                    }
                Test.stopTest();
            }

            // [3] Remove the user's settings and run the action again
            delete userSettings;
            System.runAs(chatUser) {
                try {
                    AIWorkflowActionDispatcher.runWorkflowAction(action.Id, agent.Id, reply.Id, null, null, false);
                } catch (AIWorkflowActionDispatcher.AIWorkflowActionDispatcherException ex) {
                    codes.add(ex.getMessage());
                }
            }

            // [4] Check the outcome
            Assert.areEqual(new List<String>{
                Label.AI_Error_Action_Not_Permitted,
                Label.AI_Error_Action_Not_Permitted
            }, codes, 'Refused both times.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the data the scenario needs
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, 'AIAssistUser');

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            AIAssistTestDataFactory.upsertUiSettings(true);
            insert userSettings;

            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', true)[0];
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ action }, true);

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            AIWorkflowAction__c unassigned = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', true)[0];

            AIWorkflowAction__c inactive = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', true)[0];
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ inactive }, true);
            inactive.IsActive__c = false;
            update inactive;

            List<String> codes = new List<String>();

            // [2] Run the action under test as the user
            System.runAs(chatUser) {
                Test.startTest();
                    for (Id actionId : new List<Id>{ unassigned.Id, inactive.Id, agent.Id, null }) {
                        try {
                            AIWorkflowActionDispatcher.runWorkflowAction(actionId, agent.Id, reply.Id, null, null, false);
                        } catch (AIWorkflowActionDispatcher.AIWorkflowActionDispatcherException ex) {
                            codes.add(ex.getMessage());
                        }
                    }
                Test.stopTest();
            }

            // [3] Check the outcome
            for (String code : codes) {
                Assert.areEqual(Label.AI_Error_Action_Not_Permitted, code, 'Not permitted, whatever the reason.');
            }
            Assert.areEqual(4, codes.size(), 'All four were refused.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the data the scenario needs
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, 'AIAssistUser');

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            AIAssistTestDataFactory.upsertUiSettings(true);
            insert userSettings;

            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', true)[0];
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ action }, true);

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            action.ExecutionType__c = AIAssistApplicationConstants.WORKFLOW_EXECUTION_WRITE;
            action.RequiresConfirmation__c = true;
            action.ConfirmationMessage__c = 'This changes data. Are you sure?';
            action.InputSchema__c = '{"properties":{"x":{}}}';
            update action;

            String code;
            Object output;

            // [2] Run the action under test as the user
            System.runAs(chatUser) {
                Test.startTest();
                    try {
                        AIWorkflowActionDispatcher.runWorkflowAction(action.Id, agent.Id, reply.Id, null, null, false);
                    } catch (AIWorkflowActionDispatcher.AIWorkflowActionDispatcherException ex) {
                        code = ex.getMessage();
                    }

                    output = AIWorkflowActionDispatcher.runWorkflowAction(action.Id, agent.Id, reply.Id, null, new Map<String, Object>{ 'x' => 'ok' }, true);
                Test.stopTest();
            }

            // [3] Read the results back
            List<AIExecutionStep__c> steps = [SELECT Status__c, RequiredConfirmation__c, ConfirmedBy__c, ConfirmedDate__c FROM AIExecutionStep__c WHERE AIConversationMessage__c = :reply.Id ORDER BY StepOrder__c];

            // [4] Check the outcome
            Assert.areEqual(Label.AI_Error_Action_Confirmation_Required, code, 'The text is the Custom Label.');
            Assert.areEqual('echo:ok', output, 'Ran once confirmed.');

            Assert.areEqual(AIAssistApplicationConstants.EXECUTION_STEP_STATUS_BLOCKED, steps[0].Status__c, 'The first attempt is evidence too.');
            Assert.areEqual(AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS, steps[1].Status__c, 'The second succeeded.');

            Assert.isTrue(steps[1].RequiredConfirmation__c, 'It required confirmation.');
            Assert.areEqual(chatUser.Id, steps[1].ConfirmedBy__c, 'Who confirmed.');
            Assert.isNotNull(steps[1].ConfirmedDate__c, 'And when.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the data the scenario needs
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, 'AIAssistUser');

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            AIAssistTestDataFactory.upsertUiSettings(true);
            insert userSettings;

            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', true)[0];
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ action }, true);

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            List<AIWorkflowAction__c> actions = AIAssistTestDataFactory.createAIWorkflowActions(3, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.NotAnExecutor', false);
            actions[1].ApexClassName__c = 'AIWorkflowActionDispatcherTest.NoSuchClass';
            actions[2].ApexClassName__c = 'AIWorkflowActionDispatcherTest.ThrowingExecutor';
            insert actions;
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, actions, true);

            List<String> shown = new List<String>();

            // [2] Run the action under test as the user
            System.runAs(chatUser) {
                Test.startTest();
                    for (AIWorkflowAction__c each : actions) {
                        try {
                            AIWorkflowActionDispatcher.runWorkflowAction(each.Id, agent.Id, reply.Id, null, null, false);
                        } catch (AIWorkflowActionDispatcher.AIWorkflowActionDispatcherException ex) {
                            shown.add(ex.getMessage());
                        }
                    }
                Test.stopTest();
            }

            // [3] Read the results back
            Integer failedSteps = [SELECT COUNT() FROM AIExecutionStep__c WHERE AIConversationMessage__c = :reply.Id AND Status__c = :AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED];

            // [4] Check the outcome
            Assert.areEqual(3, shown.size(), 'Every one of the three was refused.');

            for (String text : shown) {
                Assert.areEqual(Label.AI_Error_Action_Failed, text, 'Only the label is shown: nothing about classes or errors.');
            }
            Assert.areEqual(3, failedSteps, 'A Failed step each.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the data the scenario needs
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, 'AIAssistUser');

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            AIAssistTestDataFactory.upsertUiSettings(true);
            insert userSettings;

            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', true)[0];
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ action }, true);

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            List<AIWorkflowAction__c> actions = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'No_Such_Flow', true);
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, actions, true);

            String code;

            // [2] Run the action under test as the user
            System.runAs(chatUser) {
                Test.startTest();
                    try {
                        AIWorkflowActionDispatcher.runWorkflowAction(actions[0].Id, agent.Id, reply.Id, conversation.Id, null, false);
                    } catch (AIWorkflowActionDispatcher.AIWorkflowActionDispatcherException ex) {
                        code = ex.getMessage();
                    }
                Test.stopTest();
            }

            // [3] Read the results back
            Integer targetSteps = [SELECT COUNT() FROM AIExecutionStep__c WHERE AIConversationMessage__c = :reply.Id AND TargetRecordId__c = :String.valueOf(conversation.Id)];

            // [4] Check the outcome
            Assert.areEqual(Label.AI_Error_Action_Failed, code, 'Action Failed.');
            Assert.areEqual(1, targetSteps, 'The target record is on the step.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the data the scenario needs
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, 'AIAssistUser');

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            AIAssistTestDataFactory.upsertUiSettings(true);
            insert userSettings;

            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', true)[0];
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ action }, true);

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            // [2] Run the action under test as the user
            System.runAs(chatUser) {
                Test.startTest();
                    AIWorkflowActionDispatcher.recordDeclinedAction(action.Id, agent.Id, reply.Id, null);
                    AIWorkflowActionDispatcher.recordDeclinedAction(action.Id, agent.Id, null, null);
                    AIWorkflowActionDispatcher.recordDeclinedAction(null, agent.Id, reply.Id, null);
                Test.stopTest();
            }

            // [3] Read the results back
            List<AIExecutionStep__c> steps = [SELECT Status__c FROM AIExecutionStep__c WHERE AIConversationMessage__c = :reply.Id];

            // [4] Check the outcome
            Assert.areEqual(1, steps.size(), 'Only the real cancellation.');
            Assert.areEqual(AIAssistApplicationConstants.EXECUTION_STEP_STATUS_CANCELLED, steps[0].Status__c, 'Cancelled.');
        }
    }

    @IsTest static void testScenario8() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the data the scenario needs
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.IsEnabled__c = false;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, 'AIAssistUser');

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            AIAssistTestDataFactory.upsertUiSettings(true);
            insert userSettings;

            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', true)[0];
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ action }, true);

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            String code;

            // [2] Run the action under test as the user
            System.runAs(chatUser) {
                Test.startTest();
                    try {
                        AIWorkflowActionDispatcher.runWorkflowAction(action.Id, agent.Id, reply.Id, null, null, false);
                    } catch (AIWorkflowActionDispatcher.AIWorkflowActionDispatcherException ex) {
                        code = ex.getMessage();
                    }
                Test.stopTest();
            }

            // [3] Check the outcome
            Assert.areEqual(Label.AI_Error_Application_Inactive, code, 'Application inactive.');
        }
    }

    @IsTest static void testScenario9() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the data the scenario needs
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, 'AIAssistUser');

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            AIAssistTestDataFactory.upsertUiSettings(true);
            insert userSettings;

            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.KeysExecutor', true)[0];
            action.InputSchema__c = '{"type":"object","properties":{"a":{"type":"string"}}}';
            update action;
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ action }, true);

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            Map<String, Object> submitted = new Map<String, Object>{
                'a' => '1',
                'b' => '2',
                'recordId' => '001000000000000AAA'
            };
            Object declared;

            // [2] Run the action under test as the user
            System.runAs(chatUser) {
                Test.startTest();
                    declared = AIWorkflowActionDispatcher.runWorkflowAction(action.Id, agent.Id, reply.Id, null, submitted, true);
                Test.stopTest();
            }

            // [3] Filter the inputs directly for the malformed, blank and empty cases
            Map<String, Object> noneDeclared = AIWorkflowActionDispatcher.filterDeclaredInputs('{ not json', submitted, action.Id);
            Map<String, Object> blankSchema = AIWorkflowActionDispatcher.filterDeclaredInputs(null, submitted, action.Id);
            Map<String, Object> noInputs = AIWorkflowActionDispatcher.filterDeclaredInputs('{"properties":{"a":{}}}', null, action.Id);

            // [4] Check the outcome
            Assert.areEqual('a', declared, 'Only the declared key reaches the action.');
            Assert.isTrue(noneDeclared.isEmpty(), 'A malformed schema declares nothing.');
            Assert.isTrue(blankSchema.isEmpty(), 'A blank schema declares nothing.');
            Assert.isTrue(noInputs.isEmpty(), 'No inputs, none passed.');
        }
    }

    @IsTest static void testScenario10() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the data the scenario needs
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, 'AIAssistUser');

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            AIAssistTestDataFactory.upsertUiSettings(true);
            insert userSettings;

            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', true)[0];
            action.InputSchema__c = '{"properties":{"x":{}}}';
            update action;
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ action }, true);

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
            update agent;

            Map<String, Object> inputs = new Map<String, Object>{ 'x' => 'a' };
            String removed;
            String inactive;
            Object output;

            // [2] Run the action under test as the user
            System.runAs(chatUser) {
                Test.startTest();
                    try {
                        AIWorkflowActionDispatcher.runWorkflowAction(action.Id, agent.Id, reply.Id, null, inputs, true);
                    } catch (AIWorkflowActionDispatcher.AIWorkflowActionDispatcherException ex) {
                        removed = ex.getMessage();
                    }
                Test.stopTest();
            }

            // [3] Assign the user to the agent again and run the action
            AIAssistTestDataFactory.createAIAgentAssignments(agent.Id, new List<User>{ chatUser }, null, true);

            System.runAs(chatUser) {
                output = AIWorkflowActionDispatcher.runWorkflowAction(action.Id, agent.Id, reply.Id, null, inputs, true);
            }
            // [4] Deactivate the agent and run the action again
            agent.IsActive__c = false;
            update agent;

            System.runAs(chatUser) {
                try {
                    AIWorkflowActionDispatcher.runWorkflowAction(action.Id, agent.Id, reply.Id, null, inputs, true);
                } catch (AIWorkflowActionDispatcher.AIWorkflowActionDispatcherException ex) {
                    inactive = ex.getMessage();
                }
            }

            // [5] Check the outcome
            Assert.areEqual(Label.AI_Error_Action_Not_Permitted, removed, 'A user the agent does not admit cannot run its action.');
            Assert.areEqual('echo:a', output, 'Once assigned again it runs.');
            Assert.areEqual(Label.AI_Error_Action_Not_Permitted, inactive, 'An inactive agent runs nothing.');
        }
    }

    @IsTest static void testScenario11() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the data the scenario needs
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, 'AIAssistUser');

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            AIAssistTestDataFactory.upsertUiSettings(true);
            insert userSettings;

            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.ContextExecutor', true)[0];
            action.InputSchema__c = '{"properties":{}}';
            update action;
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ action }, true);

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            Object output;

            // [2] Run the action under test as the user
            System.runAs(chatUser) {
                Test.startTest();
                    output = AIWorkflowActionDispatcher.runWorkflowAction(action.Id, agent.Id, reply.Id, null, null, true);
                Test.stopTest();
            }

            // [3] Read the results back
            AIWorkflowAction__c saved = [SELECT DeveloperName__c FROM AIWorkflowAction__c WHERE Id = :action.Id];

            // [4] Check the outcome
            Assert.areEqual(saved.DeveloperName__c + '|' + agent.Id + '|' + chatUser.Id + '|' + conversation.Id + '|true', output, 'The request carries who, what and where.');
        }
    }

    @IsTest static void testScenario12() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the data the scenario needs
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);

            User chatUser = users[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, AIAssistApplicationConstants.PERMISSION_SET_USER);

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            AIAssistTestDataFactory.upsertUiSettings(true);
            insert userSettings;

            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'No_Such_Flow', false)[0];
            action.InputSchema__c = '{"properties":{"targetId":{"type":"string"},"recordId":{"type":"string"}}}';
            action.ExecutionType__c = AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY;
            action.RequiresConfirmation__c = false;
            insert action;
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ action }, true);

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIConversation__c othersConversation = AIAssistTestDataFactory.createAIConversations(agent.Id, users[1].Id, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            String withoutAccess;
            String withAccess;
            Integer blockedSteps;

            // [2] Run the action under test as the user
            System.runAs(chatUser) {
                Test.startTest();
                    try {
                        AIWorkflowActionDispatcher.runWorkflowAction(action.Id, agent.Id, reply.Id, null, new Map<String, Object>{ 'targetId' => othersConversation.Id }, true);
                    } catch (AIWorkflowActionDispatcher.AIWorkflowActionDispatcherException ex) {
                        withoutAccess = ex.getMessage();
                    }
                    try {
                        AIWorkflowActionDispatcher.runWorkflowAction(action.Id, agent.Id, reply.Id, null, new Map<String, Object>{
                            'targetId' => String.valueOf(conversation.Id)
                        }, true);
                    } catch (AIWorkflowActionDispatcher.AIWorkflowActionDispatcherException ex) {
                        withAccess = ex.getMessage();
                    }
                Test.stopTest();
            }

            // [3] Read the results back
            blockedSteps = [SELECT COUNT() FROM AIExecutionStep__c WHERE AIConversationMessage__c = :reply.Id AND Status__c = :AIAssistApplicationConstants.EXECUTION_STEP_STATUS_BLOCKED];

            // [4] Check the outcome
            Assert.areEqual(1, blockedSteps, 'The refusal is recorded as Blocked.');
            Assert.areEqual(Label.AI_Error_Action_Not_Permitted, withoutAccess, 'A record the user cannot read is not handed to a Flow.');
            Assert.areEqual(Label.AI_Error_Action_Failed, withAccess, 'The user\'s own record passes the check; only the missing Flow fails.');
        }
    }

    @IsTest static void testScenario13() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the data the scenario needs
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);

            User chatUser = users[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, AIAssistApplicationConstants.PERMISSION_SET_USER);

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            AIAssistTestDataFactory.upsertUiSettings(true);
            insert userSettings;

            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'No_Such_Flow', false)[0];
            action.InputSchema__c = '{"properties":{"targetId":{"type":"string"},"recordId":{"type":"string"}}}';
            action.ExecutionType__c = AIAssistApplicationConstants.WORKFLOW_EXECUTION_WRITE;
            action.RequiresConfirmation__c = true;
            action.ConfirmationMessage__c = 'Change this record?';
            insert action;
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ action }, true);

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIConversation__c othersConversation = AIAssistTestDataFactory.createAIConversations(agent.Id, users[1].Id, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            // The User permission set reads agents and cannot edit them.
            Map<String, Object> inputs = new Map<String, Object>{
                'targetId' => agent.Id
            };
            String asWrite;
            String asReadOnly;

            // [2] Run the action under test as the user
            System.runAs(chatUser) {
                Test.startTest();
                    try {
                        AIWorkflowActionDispatcher.runWorkflowAction(action.Id, agent.Id, reply.Id, null, inputs, true);
                    } catch (AIWorkflowActionDispatcher.AIWorkflowActionDispatcherException ex) {
                        asWrite = ex.getMessage();
                    }
                Test.stopTest();
            }

            // [3] Make the action Read Only and run it again
            action.ExecutionType__c = AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY;
            update action;

            System.runAs(chatUser) {
                try {
                    AIWorkflowActionDispatcher.runWorkflowAction(action.Id, agent.Id, reply.Id, null, inputs, true);
                } catch (AIWorkflowActionDispatcher.AIWorkflowActionDispatcherException ex) {
                    asReadOnly = ex.getMessage();
                }
            }

            // [4] Check the outcome
            Assert.areEqual(Label.AI_Error_Action_Not_Permitted, asWrite, 'A Write action needs edit access to the record.');
            Assert.areEqual(Label.AI_Error_Action_Failed, asReadOnly, 'Read access is enough for a Read Only action.');
        }
    }

    @IsTest static void testScenario14() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the data the scenario needs
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);

            User chatUser = users[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, AIAssistApplicationConstants.PERMISSION_SET_USER);

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            AIAssistTestDataFactory.upsertUiSettings(true);
            insert userSettings;

            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'No_Such_Flow', false)[0];
            action.InputSchema__c = '{"properties":{"targetId":{"type":"string"},"recordId":{"type":"string"}}}';
            action.ExecutionType__c = AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY;
            action.RequiresConfirmation__c = false;
            insert action;
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ action }, true);

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIConversation__c othersConversation = AIAssistTestDataFactory.createAIConversations(agent.Id, users[1].Id, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            String code;

            // [2] Run the action under test as the user
            System.runAs(chatUser) {
                Test.startTest();
                    try {
                        AIWorkflowActionDispatcher.runWorkflowAction(action.Id, agent.Id, reply.Id, othersConversation.Id, null, true);
                    } catch (AIWorkflowActionDispatcher.AIWorkflowActionDispatcherException ex) {
                        code = ex.getMessage();
                    }
                Test.stopTest();
            }

            // [3] Check the outcome
            Assert.areEqual(Label.AI_Error_Action_Not_Permitted, code, 'The conversation\'s record is checked like any other.');
        }
    }

    @IsTest static void testScenario15() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the data the scenario needs
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);

            User chatUser = users[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, AIAssistApplicationConstants.PERMISSION_SET_USER);

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            AIAssistTestDataFactory.upsertUiSettings(true);
            insert userSettings;

            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.RecordExecutor', false)[0];
            action.InputSchema__c = '{"properties":{"targetId":{"type":"string"},"recordId":{"type":"string"}}}';
            action.ExecutionType__c = AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY;
            action.RequiresConfirmation__c = false;
            insert action;
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ action }, true);

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIConversation__c othersConversation = AIAssistTestDataFactory.createAIConversations(agent.Id, users[1].Id, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            Object output;

            // [2] Run the action under test as the user
            System.runAs(chatUser) {
                Test.startTest();
                    output = AIWorkflowActionDispatcher.runWorkflowAction(action.Id, agent.Id, reply.Id, conversation.Id, new Map<String, Object>{
                        'recordId' => othersConversation.Id,
                        'RecordID' => othersConversation.Id,
                        'targetId' => 'kept'
                    }, true);
                Test.stopTest();
            }

            // [3] Check the outcome
            Assert.areEqual(conversation.Id + '|targetId', output, 'The record is the server\'s, and the browser\'s recordId never reaches the action.');
        }
    }

    @IsTest static void testScenario16() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the data the scenario needs
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);

            User chatUser = users[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, AIAssistApplicationConstants.PERMISSION_SET_USER);

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            AIAssistTestDataFactory.upsertUiSettings(true);
            insert userSettings;

            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'No_Such_Flow', false)[0];
            action.InputSchema__c = '{"properties":{"targetId":{"type":"string"},"recordId":{"type":"string"}}}';
            action.ExecutionType__c = AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY;
            action.RequiresConfirmation__c = false;
            insert action;
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ action }, true);

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIConversation__c othersConversation = AIAssistTestDataFactory.createAIConversations(agent.Id, users[1].Id, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            String code;

            // [2] Run the action under test as the user
            System.runAs(chatUser) {
                Test.startTest();
                    try {
                        AIWorkflowActionDispatcher.runWorkflowAction(action.Id, agent.Id, reply.Id, null, new Map<String, Object>{ 'targetId' => 'Call the customer back' }, true);
                    } catch (AIWorkflowActionDispatcher.AIWorkflowActionDispatcherException ex) {
                        code = ex.getMessage();
                    }
                Test.stopTest();
            }

            // [3] Check the outcome
            Assert.areEqual(Label.AI_Error_Action_Failed, code, 'Plain text is passed on; only the missing Flow fails.');
        }
    }
}
