/*
Class Name: AIToolsWorkflowActionControllerTest

=================================================================
=================================================================

Description: Testing utility for AIToolsWorkflowActionController: each call reaches the service, and a refusal reaches the tab as a readable message.

=================================================================
=================================================================
Applicable Classes:

AIToolsWorkflowActionController: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIToolsWorkflowActionControllerTest {

    private static final String ECHO_EXECUTOR = 'AIToolsWorkflowActionControllerTest.EchoExecutor';

    // An executor the platform calls by name.
    public class EchoExecutor implements IAIWorkflowActionExecutor {
        public AIWorkflowActionResponse execute(AIWorkflowActionRequest request) {
            return new AIWorkflowActionResponse('echo');
        }
    }

    // testScenario1: A manager saves an action, reads the list and the action, lists flows, flow variables and classes, and tests it -> each call returns what the service returns.
    // testScenario2: A manager saves an action with no name -> the tab gets a readable message.
    // testScenario3: A user without the permission calls every method -> each throws the access label as an AuraHandledException.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an action
            AIToolsWorkflowActionDataStructure.ActionDetail detail = new AIToolsWorkflowActionDataStructure.ActionDetail();
            detail.actionName = 'Controller action';
            detail.developerName = 'Controller_Action';
            detail.description = 'Does a thing.';
            detail.actionType = AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX;
            detail.executionType = AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY;
            detail.apexClassName = ECHO_EXECUTOR;
            detail.isActive = true;

            // [2] Save it, read it back and test it
            Test.startTest();
                AIToolsWorkflowActionDataStructure.ActionRow savedRow = AIToolsWorkflowActionController.saveAction((Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(detail)));
                List<AIToolsWorkflowActionDataStructure.ActionRow> rows = AIToolsWorkflowActionController.getActions();
                AIToolsWorkflowActionDataStructure.ActionDetail savedDetail = AIToolsWorkflowActionController.getAction(savedRow.actionId);
                List<AIToolsWorkflowActionDataStructure.FlowOption> flows = AIToolsWorkflowActionController.getFlows(false);
                List<AIToolsWorkflowActionDataStructure.FlowVariableOption> variables = AIToolsWorkflowActionController.getFlowVariables('AI_Tools_Missing_Flow_For_Test');
                List<AIToolsWorkflowActionDataStructure.ApexClassOption> classes = AIToolsWorkflowActionController.getApexClasses();
                AIToolsWorkflowActionDataStructure.TestResult result = AIToolsWorkflowActionController.runTest((Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(savedDetail)), (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(new AIToolsWorkflowActionDataStructure.TestRequest())));
            Test.stopTest();

            // [3] Check each answer
            Assert.areEqual('Controller action', savedRow.actionName, 'The saved row is returned.');
            Assert.areEqual(1, rows.size(), 'The list holds the saved action.');
            Assert.areEqual(ECHO_EXECUTOR, savedDetail.apexClassName, 'The action is read back in full.');
            Assert.isNotNull(flows, 'The flow list comes back.');
            Assert.isTrue(variables.isEmpty(), 'A missing flow has no variables.');
            Assert.isNotNull(classes, 'The class list comes back.');
            Assert.areEqual(AIAssistApplicationConstants.WORKFLOW_TEST_STATUS_PASSED, result.status, 'The test runs.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Save an action with no name
            String refusal;

            Test.startTest();
                try {

                    AIToolsWorkflowActionController.saveAction((Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(new AIToolsWorkflowActionDataStructure.ActionDetail())));
                } catch (AuraHandledException ex) {

                    refusal = ex.getMessage();
                }
            Test.stopTest();

            // [2] Check the tab gets the reason
            Assert.isTrue(refusal != null && refusal.contains('is required'), 'The tab is told which value is missing.');
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
                    try {

                        AIToolsWorkflowActionController.getActions();
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsWorkflowActionController.getAction(users[0].Id);
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsWorkflowActionController.getFlows(true);
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsWorkflowActionController.getFlowVariables('Any_Flow');
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsWorkflowActionController.getApexClasses();
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsWorkflowActionController.saveAction((Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(new AIToolsWorkflowActionDataStructure.ActionDetail())));
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsWorkflowActionController.runTest((Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(new AIToolsWorkflowActionDataStructure.ActionDetail())), (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(new AIToolsWorkflowActionDataStructure.TestRequest())));
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }
                }
            Test.stopTest();

            // [3] Check every call was refused with the access label
            Assert.areEqual(7, refusals.size(), 'All seven calls are refused.');
            Assert.areEqual(new Set<String>{Label.AI_Settings_Error_Access}, new Set<String>(refusals), 'Every refusal shows the access label.');
        }
    }
}
