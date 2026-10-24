/*
Class Name: AIToolsWorkflowActionTestServiceTest

=================================================================
=================================================================

Description: Testing utility for AIToolsWorkflowActionTestService: running an action from the AI Tools tab, rolling it back, and the checks that stop an unsafe test.

=================================================================
=================================================================
Applicable Classes:

AIToolsWorkflowActionTestService: Coverage TBC
AIWorkflowActionDispatcher: Coverage TBC (applyServerFilledInputs)

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIToolsWorkflowActionTestServiceTest {

    private static final String ECHO_EXECUTOR = 'AIToolsWorkflowActionTestServiceTest.EchoExecutor';
    private static final String THROWING_EXECUTOR = 'AIToolsWorkflowActionTestServiceTest.ThrowingExecutor';
    private static final String CALLOUT_EXECUTOR = 'AIToolsWorkflowActionTestServiceTest.CalloutExecutor';
    private static final String NOT_AN_EXECUTOR = 'AIToolsWorkflowActionTestServiceTest.NotAnExecutor';
    private static final String ECHO_SCHEMA = '{"type":"object","properties":{"x":{"type":"string"},"ownerId":{"type":"string","x-source":"user"},"mode":{"type":"string","x-source":"fixed","x-value":"fast"}}}';
    private static final String PAGE_SCHEMA = '{"type":"object","properties":{"recordId":{"type":"string","x-source":"page"}}}';
    private static final String TEST_ACCOUNT_NAME = 'AI Tools Workflow Test Account';

    // Executors the platform calls by name. The first changes data so the roll back can be seen, the second fails, the third says it sends email, and the last is not an executor at all.
    public class EchoExecutor implements IAIWorkflowActionExecutor {
        public AIWorkflowActionResponse execute(AIWorkflowActionRequest request) {
            insert new Account(Name = 'AI Tools Workflow Test Account');
            return new AIWorkflowActionResponse(request.inputParameters.get('x') + '|' + request.inputParameters.get('ownerId') + '|' + request.inputParameters.get('mode') + '|' + request.inputParameters.containsKey('rogue'));
        }
    }

    public class ThrowingExecutor implements IAIWorkflowActionExecutor {
        public AIWorkflowActionResponse execute(AIWorkflowActionRequest request) {
            insert new Account(Name = 'AI Tools Workflow Test Account');
            throw new CalloutException('boom');
        }
    }

    public class CalloutExecutor implements IAIWorkflowActionExecutor, IAIWorkflowActionInputDescriber {
        public AIWorkflowActionResponse execute(AIWorkflowActionRequest request) {
            return new AIWorkflowActionResponse('sent');
        }
        public String describeInputs() {
            return '{"type":"object","properties":{},"x-callouts":"Sends email"}';
        }
    }

    public class NotAnExecutor {
        public String execute() {
            return 'never runs';
        }
    }

    // testScenario1: A manager tests an Apex action with the user, fixed and agent inputs and a rogue input, rolling back -> the class sees the server's values and no rogue input, and the account it created is gone.
    // testScenario2: A manager tests an Apex action that throws after changing data -> the test fails with the reason and the change is rolled back.
    // testScenario3: A manager tests a screen flow, an action with no record, a class that is not an executor and a flow that is not active -> the first, second and last are refused and the class that is not an executor fails.
    // testScenario4: A manager switches Roll back off, and tests a class that says it sends email -> a production org refuses both, and a sandbox runs them.
    // testScenario5: The dispatcher fills the inputs the server owns -> the user and fixed values replace what was sent, the page input is removed, and a schema with no sources changes nothing.
    // testScenario7: A manager tests a Read Only action whose class creates an account -> the test fails and says it changed a record.
    // testScenario6: A user without the Manage Settings permission runs a test -> the access label is shown.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the action and the values the tab would send, including one input nobody declared and an owner that is not the user
            AIToolsWorkflowActionDataStructure.ActionDetail detail = new AIToolsWorkflowActionDataStructure.ActionDetail();
            detail.developerName = 'Echo_Action';
            detail.actionType = AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX;
            detail.executionType = AIAssistApplicationConstants.WORKFLOW_EXECUTION_WRITE;
            detail.apexClassName = ECHO_EXECUTOR;
            detail.inputSchema = ECHO_SCHEMA;
            AIToolsWorkflowActionDataStructure.TestRequest request = new AIToolsWorkflowActionDataStructure.TestRequest();
            request.inputValues = new Map<String, Object>{'x' => 'hello', 'ownerId' => '005000000000000AAA', 'rogue' => 'z'};
            request.shouldRollBack = true;

            // [2] Run the test
            Test.startTest();
                AIToolsWorkflowActionDataStructure.TestResult result = AIToolsWorkflowActionTestService.runTest(detail, request);
            Test.stopTest();

            // [3] Count the accounts the class created
            Integer accountCount = [SELECT COUNT() FROM Account WHERE Name = :TEST_ACCOUNT_NAME];

            // [4] Check the result
            Assert.areEqual(AIAssistApplicationConstants.WORKFLOW_TEST_STATUS_PASSED, result.status, 'The test passes.');
            Assert.areEqual('hello|' + superUser.Id + '|fast|false', result.outputs[0].value, 'The class sees the user and fixed values from the server and no rogue input.');
            Assert.areEqual(1, result.recordsChanged, 'One record was changed.');
            Assert.isTrue(result.isRolledBack, 'The test says it rolled back.');
            Assert.areEqual(0, accountCount, 'The account the class created was rolled back.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an action whose class changes data and then throws
            AIToolsWorkflowActionDataStructure.ActionDetail detail = new AIToolsWorkflowActionDataStructure.ActionDetail();
            detail.developerName = 'Throwing_Action';
            detail.actionType = AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX;
            detail.executionType = AIAssistApplicationConstants.WORKFLOW_EXECUTION_WRITE;
            detail.apexClassName = THROWING_EXECUTOR;
            AIToolsWorkflowActionDataStructure.TestRequest request = new AIToolsWorkflowActionDataStructure.TestRequest();

            // [2] Run the test
            Test.startTest();
                AIToolsWorkflowActionDataStructure.TestResult result = AIToolsWorkflowActionTestService.runTest(detail, request);
            Test.stopTest();

            // [3] Count the accounts the class created
            Integer accountCount = [SELECT COUNT() FROM Account WHERE Name = :TEST_ACCOUNT_NAME];

            // [4] Check it failed and was undone
            Assert.areEqual(AIAssistApplicationConstants.WORKFLOW_TEST_STATUS_FAILED, result.status, 'The test fails.');
            Assert.isTrue(result.message.contains('boom'), 'The reason is shown.');
            Assert.areEqual(0, accountCount, 'The change was rolled back.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a request and one action for each refusal
            AIToolsWorkflowActionDataStructure.TestRequest request = new AIToolsWorkflowActionDataStructure.TestRequest();
            AIToolsWorkflowActionDataStructure.ActionDetail screenFlow = new AIToolsWorkflowActionDataStructure.ActionDetail();
            screenFlow.actionType = AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_SCREEN_FLOW;
            screenFlow.flowApiName = 'AI_Tools_Missing_Flow_For_Test';
            AIToolsWorkflowActionDataStructure.ActionDetail noRecord = new AIToolsWorkflowActionDataStructure.ActionDetail();
            noRecord.actionType = AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX;
            noRecord.apexClassName = ECHO_EXECUTOR;
            noRecord.inputSchema = PAGE_SCHEMA;
            AIToolsWorkflowActionDataStructure.ActionDetail notExecutor = new AIToolsWorkflowActionDataStructure.ActionDetail();
            notExecutor.actionType = AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX;
            notExecutor.apexClassName = NOT_AN_EXECUTOR;
            AIToolsWorkflowActionDataStructure.ActionDetail inactiveFlow = new AIToolsWorkflowActionDataStructure.ActionDetail();
            inactiveFlow.actionType = AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW;
            inactiveFlow.flowApiName = 'AI_Tools_Missing_Flow_For_Test';
            String screenFlowMessage;
            String noRecordMessage;
            String inactiveFlowMessage;

            // [2] Try each test and keep each message
            Test.startTest();
                try {

                    AIToolsWorkflowActionTestService.runTest(screenFlow, request);
                } catch (Exception ex) {

                    screenFlowMessage = ex.getMessage();
                }

                try {

                    AIToolsWorkflowActionTestService.runTest(noRecord, request);
                } catch (Exception ex) {

                    noRecordMessage = ex.getMessage();
                }

                try {

                    AIToolsWorkflowActionTestService.runTest(inactiveFlow, request);
                } catch (Exception ex) {

                    inactiveFlowMessage = ex.getMessage();
                }

                AIToolsWorkflowActionDataStructure.TestResult notExecutorResult = AIToolsWorkflowActionTestService.runTest(notExecutor, request);
            Test.stopTest();

            // [3] Check each was refused
            Assert.areEqual(Label.AI_ToolsWa_Error_Screen_Flow_No_Test, screenFlowMessage, 'A screen flow cannot be tested here.');
            Assert.areEqual(Label.AI_ToolsWa_Error_Record_Required, noRecordMessage, 'An action that works on a record needs one.');
            Assert.areEqual(AIAssistApplicationConstants.WORKFLOW_TEST_STATUS_FAILED, notExecutorResult.status, 'A class that is not an executor fails the test and is not run.');
            Assert.areEqual(Label.AI_ToolsWa_Error_Flow_Inactive, inactiveFlowMessage, 'A flow with no active version is refused.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build one action that is kept, and one whose class says it sends email
            Boolean isSandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
            AIToolsWorkflowActionDataStructure.ActionDetail kept = new AIToolsWorkflowActionDataStructure.ActionDetail();
            kept.developerName = 'Kept_Action';
            kept.actionType = AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX;
            kept.apexClassName = ECHO_EXECUTOR;
            AIToolsWorkflowActionDataStructure.ActionDetail callout = new AIToolsWorkflowActionDataStructure.ActionDetail();
            callout.developerName = 'Callout_Action';
            callout.actionType = AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX;
            callout.apexClassName = CALLOUT_EXECUTOR;
            AIToolsWorkflowActionDataStructure.TestRequest keepRequest = new AIToolsWorkflowActionDataStructure.TestRequest();
            keepRequest.shouldRollBack = false;
            AIToolsWorkflowActionDataStructure.TestRequest rollBackRequest = new AIToolsWorkflowActionDataStructure.TestRequest();
            String keptMessage;
            String calloutMessage;
            AIToolsWorkflowActionDataStructure.TestResult keptResult;
            AIToolsWorkflowActionDataStructure.TestResult calloutResult;

            // [2] Run both
            Test.startTest();
                try {

                    keptResult = AIToolsWorkflowActionTestService.runTest(kept, keepRequest);
                } catch (Exception ex) {

                    keptMessage = ex.getMessage();
                }

                try {

                    calloutResult = AIToolsWorkflowActionTestService.runTest(callout, rollBackRequest);
                } catch (Exception ex) {

                    calloutMessage = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check a production org refused both and a sandbox ran both
            Assert.areEqual(isSandbox ? null : Label.AI_ToolsWa_Error_Rollback_Sandbox, keptMessage, 'Only a sandbox may switch Roll back off.');
            Assert.areEqual(isSandbox ? null : Label.AI_ToolsWa_Error_Callouts_Sandbox, calloutMessage, 'Only a sandbox may test a class that sends email.');
            Assert.areEqual(isSandbox, keptResult != null && !keptResult.isRolledBack, 'In a sandbox the test with Roll back off is kept.');
            Assert.areEqual(isSandbox, calloutResult != null, 'In a sandbox the class that sends email runs.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build what the browser sent
            Map<String, Object> sent = new Map<String, Object>{'x' => 'hello', 'ownerId' => '005000000000000AAA', 'recordId' => '001000000000000AAA'};
            String pageSchema = '{"properties":{"x":{"type":"string"},"ownerId":{"x-source":"user"},"mode":{"x-source":"fixed","x-value":"fast"},"recordId":{"x-source":"page"}}}';

            // [2] Fill the inputs the server owns, with a schema that has sources, one that has none, a blank one and a broken one
            Test.startTest();
                Map<String, Object> filled = AIWorkflowActionDispatcher.applyServerFilledInputs(pageSchema, sent);
                Map<String, Object> unchanged = AIWorkflowActionDispatcher.applyServerFilledInputs('{"properties":{"x":{"type":"string"}}}', sent);
                Map<String, Object> blank = AIWorkflowActionDispatcher.applyServerFilledInputs(null, sent);
                Map<String, Object> broken = AIWorkflowActionDispatcher.applyServerFilledInputs('not json', sent);
            Test.stopTest();

            // [3] Check each
            Assert.areEqual(superUser.Id, filled.get('ownerId'), 'The user input is always the signed in user.');
            Assert.areEqual('fast', filled.get('mode'), 'The fixed input is always the fixed value.');
            Assert.isFalse(filled.containsKey('recordId'), 'The page input is never taken from the browser.');
            Assert.areEqual('hello', filled.get('x'), 'An agent input is kept.');
            Assert.areEqual(sent, unchanged, 'A schema with no sources changes nothing.');
            Assert.areEqual(sent, blank, 'A blank schema changes nothing.');
            Assert.areEqual(sent, broken, 'A broken schema changes nothing.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            String refusal;

            // [2] Run a test as that user
            Test.startTest();
                System.runAs(users[0]) {
                    try {

                        AIToolsWorkflowActionTestService.runTest(new AIToolsWorkflowActionDataStructure.ActionDetail(), new AIToolsWorkflowActionDataStructure.TestRequest());
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusal = ex.getMessage();
                    }
                }
            Test.stopTest();

            // [3] Check the call was refused with the access label
            Assert.areEqual(Label.AI_Settings_Error_Access, refusal, 'The refusal shows the access label.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] A Read Only action whose class creates an account
            AIToolsWorkflowActionDataStructure.ActionDetail detail = new AIToolsWorkflowActionDataStructure.ActionDetail();
            detail.developerName = 'Echo_Read_Only_Action';
            detail.actionType = AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX;
            detail.executionType = AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY;
            detail.apexClassName = ECHO_EXECUTOR;
            detail.inputSchema = ECHO_SCHEMA;
            AIToolsWorkflowActionDataStructure.TestRequest request = new AIToolsWorkflowActionDataStructure.TestRequest();
            request.shouldRollBack = true;

            // [2] Run the test
            Test.startTest();
                AIToolsWorkflowActionDataStructure.TestResult result = AIToolsWorkflowActionTestService.runTest(detail, request);
            Test.stopTest();

            // [3] The test fails, the change is still rolled back
            Assert.areEqual(AIAssistApplicationConstants.WORKFLOW_TEST_STATUS_FAILED, result.status, 'A Read Only action that changes a record fails.');
            Assert.isTrue(result.message.contains('Read Only'), 'The message says why.');
            Assert.areEqual(0, [SELECT COUNT() FROM Account WHERE Name = :TEST_ACCOUNT_NAME], 'The account was rolled back.');
        }
    }
}
