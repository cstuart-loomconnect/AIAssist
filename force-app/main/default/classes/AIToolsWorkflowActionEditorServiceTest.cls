/*
Class Name: AIToolsWorkflowActionEditorServiceTest

=================================================================
=================================================================

Description: Testing utility for AIToolsWorkflowActionEditorService: reading, checking and saving workflow actions, and describing Apex classes and flows.

=================================================================
=================================================================
Applicable Classes:

AIToolsWorkflowActionEditorService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIToolsWorkflowActionEditorServiceTest {

    private static final String PLAIN_EXECUTOR = 'AIToolsWorkflowActionEditorServiceTest.PlainExecutor';
    private static final String DESCRIBED_EXECUTOR = 'AIToolsWorkflowActionEditorServiceTest.DescribedExecutor';
    private static final String BROKEN_EXECUTOR = 'AIToolsWorkflowActionEditorServiceTest.BrokenExecutor';
    private static final String MISSING_FLOW = 'AI_Tools_Missing_Flow_For_Test';

    // Executors the platform calls by name: one that says nothing about itself, one that describes its inputs and a callout, and one whose description is not a schema.
    public class PlainExecutor implements IAIWorkflowActionExecutor {
        public AIWorkflowActionResponse execute(AIWorkflowActionRequest request) {
            return new AIWorkflowActionResponse('plain');
        }
    }

    public class DescribedExecutor implements IAIWorkflowActionExecutor, IAIWorkflowActionInputDescriber {
        public AIWorkflowActionResponse execute(AIWorkflowActionRequest request) {
            return new AIWorkflowActionResponse('described');
        }
        public String describeInputs() {
            return '{"type":"object","properties":{"recordId":{"type":"string"},"body":{"type":"string"}},"x-callouts":["Sends email"]}';
        }
    }

    public class BrokenExecutor implements IAIWorkflowActionExecutor, IAIWorkflowActionInputDescriber {
        public AIWorkflowActionResponse execute(AIWorkflowActionRequest request) {
            return new AIWorkflowActionResponse('broken');
        }
        public String describeInputs() {
            return 'this is not json';
        }
    }

    // testScenario1: A manager lists actions, one with an active agent and one whose flow is not active -> the agent count and the Flow inactive flag show.
    // testScenario2: A manager saves a new Apex action and a Write flow action and reads them back -> the values are saved, a Write flow action is made to confirm and the other type's field is blank.
    // testScenario3: A manager saves actions with no name, a bad API name, a bad type, a class that is not an executor, a Write action with no message, a bad schema and a repeated API name -> each is refused.
    // testScenario4: A manager saves a tested action, then saves it again with no test result -> the test result and date are kept, then cleared.
    // testScenario5: A manager describes Apex classes and lists flows -> a described class shows its inputs and callouts, a broken one shows nothing, and the lists come back.
    // testScenario6: A user without the Manage Settings permission calls every method -> each is refused with the access label.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent with an active action, and an action whose flow does not exist
            List<AIModelConfiguration__c> configurations = AIAssistTestDataFactory.createAIModelConfigurations(1, true);
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, configurations[0].Id, true)[0];
            AIWorkflowAction__c apexAction = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, PLAIN_EXECUTOR, true)[0];
            AIWorkflowAction__c flowAction = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, MISSING_FLOW, true)[0];
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{apexAction}, true);

            // [2] Read the list
            Test.startTest();
                List<AIToolsWorkflowActionDataStructure.ActionRow> rows = AIToolsWorkflowActionEditorService.getActions();
            Test.stopTest();

            // [3] Find the two rows
            AIToolsWorkflowActionDataStructure.ActionRow apexRow;
            AIToolsWorkflowActionDataStructure.ActionRow flowRow;

            for (AIToolsWorkflowActionDataStructure.ActionRow row : rows) {

                if (row.actionId == apexAction.Id) apexRow = row;
                if (row.actionId == flowAction.Id) flowRow = row;
            }

            // [4] Check the counts and flags
            Assert.areEqual(1, apexRow.agentCount, 'The action has one active agent.');
            Assert.isNull(apexRow.attention, 'An Apex action never needs flow attention.');
            Assert.areEqual(0, flowRow.agentCount, 'The unassigned action has no agents.');
            Assert.areEqual(AIAssistApplicationConstants.WORKFLOW_ATTENTION_FLOW_INACTIVE, flowRow.attention, 'A flow with no active version is flagged.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Apex action and a Write flow action that forgets to ask for confirmation
            AIToolsWorkflowActionDataStructure.ActionDetail apexDetail = new AIToolsWorkflowActionDataStructure.ActionDetail();
            apexDetail.actionName = 'Check case status';
            apexDetail.developerName = 'Check_Case_Status';
            apexDetail.description = 'Looks up a case.';
            apexDetail.actionType = AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX;
            apexDetail.executionType = AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY;
            apexDetail.apexClassName = PLAIN_EXECUTOR;
            apexDetail.targetObject = 'Case';
            apexDetail.inputSchema = '{"type":"object","properties":{"caseNumber":{"type":"string"}}}';
            apexDetail.isActive = true;

            AIToolsWorkflowActionDataStructure.ActionDetail flowDetail = new AIToolsWorkflowActionDataStructure.ActionDetail();
            flowDetail.actionName = 'Create follow-up task';
            flowDetail.developerName = 'Create_Follow_Up_Task';
            flowDetail.description = 'Creates a task.';
            flowDetail.actionType = AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW;
            flowDetail.executionType = AIAssistApplicationConstants.WORKFLOW_EXECUTION_WRITE;
            flowDetail.flowApiName = MISSING_FLOW;
            flowDetail.requiresConfirmation = false;
            flowDetail.confirmationMessage = 'Create a follow-up task?';
            flowDetail.isActive = false;

            // [2] Save both and read them back
            Test.startTest();
                AIToolsWorkflowActionDataStructure.ActionRow apexRow = AIToolsWorkflowActionEditorService.saveAction(apexDetail);
                AIToolsWorkflowActionDataStructure.ActionRow flowRow = AIToolsWorkflowActionEditorService.saveAction(flowDetail);
            Test.stopTest();

            AIToolsWorkflowActionDataStructure.ActionDetail apexSaved = AIToolsWorkflowActionEditorService.getAction(apexRow.actionId);
            AIToolsWorkflowActionDataStructure.ActionDetail flowSaved = AIToolsWorkflowActionEditorService.getAction(flowRow.actionId);

            // [3] Check what was saved
            Assert.areEqual(PLAIN_EXECUTOR, apexSaved.apexClassName, 'The Apex class is saved.');
            Assert.isNull(apexSaved.flowApiName, 'An Apex action has no flow.');
            Assert.areEqual('Case', apexSaved.targetObject, 'The target object is saved.');
            Assert.isFalse(apexSaved.requiresConfirmation, 'A read only action does not need to confirm.');
            Assert.areEqual(MISSING_FLOW, flowSaved.flowApiName, 'The flow is saved.');
            Assert.isNull(flowSaved.apexClassName, 'A flow action has no Apex class.');
            Assert.isTrue(flowSaved.requiresConfirmation, 'A Write flow action is made to confirm.');
            Assert.areEqual('Create a follow-up task?', flowSaved.confirmationMessage, 'The confirmation message is saved.');
            Assert.isFalse(flowSaved.isActive, 'The action is saved inactive when asked.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build one good action to start from, and save it so its API name is taken
            AIToolsWorkflowActionDataStructure.ActionDetail good = new AIToolsWorkflowActionDataStructure.ActionDetail();
            good.actionName = 'Good action';
            good.developerName = 'Good_Action';
            good.description = 'Does a good thing.';
            good.actionType = AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX;
            good.executionType = AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY;
            good.apexClassName = PLAIN_EXECUTOR;
            good.isActive = true;
            AIToolsWorkflowActionEditorService.saveAction(good);

            // [2] Build one bad copy for each refusal
            AIToolsWorkflowActionDataStructure.ActionDetail noName = (AIToolsWorkflowActionDataStructure.ActionDetail) JSON.deserialize(JSON.serialize(good), AIToolsWorkflowActionDataStructure.ActionDetail.class);
            noName.actionName = '';
            AIToolsWorkflowActionDataStructure.ActionDetail badApiName = (AIToolsWorkflowActionDataStructure.ActionDetail) JSON.deserialize(JSON.serialize(good), AIToolsWorkflowActionDataStructure.ActionDetail.class);
            badApiName.developerName = '1 bad name';
            AIToolsWorkflowActionDataStructure.ActionDetail badType = (AIToolsWorkflowActionDataStructure.ActionDetail) JSON.deserialize(JSON.serialize(good), AIToolsWorkflowActionDataStructure.ActionDetail.class);
            badType.actionType = 'Teleport';
            AIToolsWorkflowActionDataStructure.ActionDetail badClass = (AIToolsWorkflowActionDataStructure.ActionDetail) JSON.deserialize(JSON.serialize(good), AIToolsWorkflowActionDataStructure.ActionDetail.class);
            badClass.developerName = 'Bad_Class';
            badClass.apexClassName = 'AIToolsWorkflowActionEditorServiceTest.NoSuchClass';
            AIToolsWorkflowActionDataStructure.ActionDetail noMessage = (AIToolsWorkflowActionDataStructure.ActionDetail) JSON.deserialize(JSON.serialize(good), AIToolsWorkflowActionDataStructure.ActionDetail.class);
            noMessage.developerName = 'No_Message';
            noMessage.executionType = AIAssistApplicationConstants.WORKFLOW_EXECUTION_WRITE;
            AIToolsWorkflowActionDataStructure.ActionDetail badSchema = (AIToolsWorkflowActionDataStructure.ActionDetail) JSON.deserialize(JSON.serialize(good), AIToolsWorkflowActionDataStructure.ActionDetail.class);
            badSchema.developerName = 'Bad_Schema';
            badSchema.inputSchema = 'not json';
            AIToolsWorkflowActionDataStructure.ActionDetail repeated = (AIToolsWorkflowActionDataStructure.ActionDetail) JSON.deserialize(JSON.serialize(good), AIToolsWorkflowActionDataStructure.ActionDetail.class);
            String noNameMessage;
            String badApiNameMessage;
            String badTypeMessage;
            String badClassMessage;
            String noMessageMessage;
            String badSchemaMessage;
            String repeatedMessage;

            // [3] Try each bad save and keep each message
            Test.startTest();
                try {

                    AIToolsWorkflowActionEditorService.saveAction(noName);
                } catch (Exception ex) {

                    noNameMessage = ex.getMessage();
                }

                try {

                    AIToolsWorkflowActionEditorService.saveAction(badApiName);
                } catch (Exception ex) {

                    badApiNameMessage = ex.getMessage();
                }

                try {

                    AIToolsWorkflowActionEditorService.saveAction(badType);
                } catch (Exception ex) {

                    badTypeMessage = ex.getMessage();
                }

                try {

                    AIToolsWorkflowActionEditorService.saveAction(badClass);
                } catch (Exception ex) {

                    badClassMessage = ex.getMessage();
                }

                try {

                    AIToolsWorkflowActionEditorService.saveAction(noMessage);
                } catch (Exception ex) {

                    noMessageMessage = ex.getMessage();
                }

                try {

                    AIToolsWorkflowActionEditorService.saveAction(badSchema);
                } catch (Exception ex) {

                    badSchemaMessage = ex.getMessage();
                }

                try {

                    AIToolsWorkflowActionEditorService.saveAction(repeated);
                } catch (Exception ex) {

                    repeatedMessage = ex.getMessage();
                }

            Test.stopTest();

            // [4] Check each was refused
            Assert.isTrue(noNameMessage != null && noNameMessage.contains('is required'), 'An action with no name is refused.');
            Assert.isTrue(badApiNameMessage != null && badApiNameMessage.contains('is required'), 'An API name with spaces is refused.');
            Assert.areEqual(Label.AI_ToolsWa_Error_Type_Invalid, badTypeMessage, 'A type the object does not list is refused.');
            Assert.areEqual(Label.AI_ToolsWa_Error_Source_Invalid, badClassMessage, 'A class that does not exist is refused.');
            Assert.isTrue(noMessageMessage != null && noMessageMessage.contains('is required'), 'A Write action with no confirmation message is refused.');
            Assert.areEqual(Label.AI_ToolsWa_Error_Source_Invalid, badSchemaMessage, 'A schema that is not JSON is refused.');
            Assert.areEqual(Label.AI_ToolsWa_Error_Duplicate, repeatedMessage, 'A repeated API name is refused.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a tested action
            AIToolsWorkflowActionDataStructure.ActionDetail detail = new AIToolsWorkflowActionDataStructure.ActionDetail();
            detail.actionName = 'Tested action';
            detail.developerName = 'Tested_Action';
            detail.description = 'Has been tested.';
            detail.actionType = AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX;
            detail.executionType = AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY;
            detail.apexClassName = PLAIN_EXECUTOR;
            detail.lastTestStatus = AIAssistApplicationConstants.WORKFLOW_TEST_STATUS_PASSED;
            detail.isActive = true;

            // [2] Save it, then save it again with the test result cleared
            Test.startTest();
                AIToolsWorkflowActionDataStructure.ActionRow firstRow = AIToolsWorkflowActionEditorService.saveAction(detail);
                AIToolsWorkflowActionDataStructure.ActionDetail firstSaved = AIToolsWorkflowActionEditorService.getAction(firstRow.actionId);
                detail.actionId = firstRow.actionId;
                detail.lastTestStatus = null;
                AIToolsWorkflowActionDataStructure.ActionRow secondRow = AIToolsWorkflowActionEditorService.saveAction(detail);
            Test.stopTest();

            // [3] Check the test result was kept, then cleared
            Assert.areEqual(AIAssistApplicationConstants.WORKFLOW_TEST_STATUS_PASSED, firstSaved.lastTestStatus, 'The test result is saved.');
            Assert.isNotNull(firstSaved.lastTestedOn, 'The test date is saved.');
            Assert.isNull(secondRow.lastTestStatus, 'Saving with no test result clears it.');
            Assert.isNull(secondRow.lastTestedOn, 'Saving with no test result clears the date.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Describe a plain class, a described class and a broken one, and read the lists
            Test.startTest();
                AIToolsWorkflowActionDataStructure.ApexClassOption plain = AIToolsWorkflowActionEditorService.buildApexClassOption(PLAIN_EXECUTOR);
                AIToolsWorkflowActionDataStructure.ApexClassOption described = AIToolsWorkflowActionEditorService.buildApexClassOption(DESCRIBED_EXECUTOR);
                AIToolsWorkflowActionDataStructure.ApexClassOption broken = AIToolsWorkflowActionEditorService.buildApexClassOption(BROKEN_EXECUTOR);
                List<AIToolsWorkflowActionDataStructure.ApexClassOption> classes = AIToolsWorkflowActionEditorService.getApexClasses();
                List<AIToolsWorkflowActionDataStructure.FlowOption> screenFlows = AIToolsWorkflowActionEditorService.getFlows(true);
                List<AIToolsWorkflowActionDataStructure.FlowOption> autolaunchedFlows = AIToolsWorkflowActionEditorService.getFlows(false);
                List<AIToolsWorkflowActionDataStructure.FlowVariableOption> variables = AIToolsWorkflowActionEditorService.getFlowVariables(MISSING_FLOW);
            Test.stopTest();

            // [2] Check what each says
            Assert.isNull(plain.inputSchema, 'A class that does not describe itself has no schema.');
            Assert.areEqual('body, recordId', described.inputNames, 'A described class lists its input names.');
            Assert.areEqual('Sends email', described.callouts, 'A described class lists its callouts.');
            Assert.isNull(broken.inputSchema, 'A class whose description is not JSON shows nothing.');
            Assert.isNotNull(classes, 'The class list comes back.');
            Assert.isNotNull(screenFlows, 'The screen flow list comes back.');
            Assert.isNotNull(autolaunchedFlows, 'The autolaunched flow list comes back.');
            Assert.isTrue(variables.isEmpty(), 'A flow that is not there has no variables.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            List<String> refusals = new List<String>();

            // [2] Call each method as that user and keep each message
            Test.startTest();
                System.runAs(users[0]) {
                    try {

                        AIToolsWorkflowActionEditorService.getActions();
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsWorkflowActionEditorService.getAction(users[0].Id);
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsWorkflowActionEditorService.getFlows(false);
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsWorkflowActionEditorService.getFlowVariables(MISSING_FLOW);
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsWorkflowActionEditorService.getApexClasses();
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsWorkflowActionEditorService.saveAction(new AIToolsWorkflowActionDataStructure.ActionDetail());
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }
                }
            Test.stopTest();

            // [3] Check every call was refused with the access label
            Assert.areEqual(6, refusals.size(), 'All six calls are refused.');
            Assert.areEqual(new Set<String>{Label.AI_Settings_Error_Access}, new Set<String>(refusals), 'Every refusal shows the access label.');
        }
    }
}
