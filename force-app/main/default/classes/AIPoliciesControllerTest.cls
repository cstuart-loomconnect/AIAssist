/*
Class Name: AIPoliciesControllerTest

=================================================================
=================================================================

Description: Testing utility for AIPoliciesController: each tab call reaches the service, and a refusal reaches the tab as a readable message.

=================================================================
=================================================================
Applicable Classes:

AIPoliciesController: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPoliciesControllerTest {

    // testScenario1: A manager saves a policy, assigns a user, switches and removes the assignment, searches, checks a user and deletes the policy -> each call returns what the service returns.
    // testScenario2: A user without the Manage Settings permission calls every method -> each throws the access label as an AuraHandledException, and nothing is logged.
    // testScenario3: A manager saves a policy with a bad limit -> the tab gets a readable message.
    // testScenario4: A save fails on the platform because a limit is too big -> the generic label is shown and the error is logged once.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user to assign
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

            // [2] Save a policy, assign the user, switch it off, search, warn, check, read the delete options, remove it and delete the policy
            Test.startTest();
                AIPoliciesDataStructure.PolicyView saved = AIPoliciesController.savePolicy(null, new Map<String, Object>{'Name' => 'Controller policy'});
                AIPoliciesDataStructure.PolicyView assigned = AIPoliciesController.addAssignment(saved.policyId, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, chatUser.Id);
                AIPoliciesDataStructure.PolicyView switchedOff = AIPoliciesController.setAssignmentActive(assigned.assignments[0].assignmentId, false);
                List<AIPoliciesDataStructure.AssigneeOption> found = AIPoliciesController.findAssignees(saved.policyId, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, chatUser.Username);
                AIPoliciesDataStructure.AssignmentWarning warning = AIPoliciesController.getAssignmentWarning(saved.policyId, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, chatUser.Id);
                AIPoliciesDataStructure.UserCheck check = AIPoliciesController.checkUser(chatUser.Id);
                List<AIPoliciesDataStructure.PolicyView> listed = AIPoliciesController.getPolicies();
                AIPoliciesDataStructure.DeleteOptions options = AIPoliciesController.getDeleteOptions(saved.policyId);
                AIPoliciesDataStructure.PolicyView removed = AIPoliciesController.removeAssignment(assigned.assignments[0].assignmentId);
                List<AIPoliciesDataStructure.PolicyView> remaining = AIPoliciesController.deletePolicy(saved.policyId, null);
            Test.stopTest();

            // [3] Count the policies left with the saved id
            Integer policyCount = [SELECT COUNT() FROM AIUsagePolicy__c WHERE Id = :saved.policyId];

            // [4] Check each answer
            Assert.areEqual(false, switchedOff.assignments[0].isActive, 'The assignment was switched off.');
            Assert.areEqual(1, found.size(), 'The user search returns the user.');
            Assert.isFalse(warning.hasWarning, 'The user has no other assignment, so there is no warning.');
            Assert.areEqual(chatUser.Id, check.userId, 'The check is for the user.');
            Assert.isFalse(listed.isEmpty(), 'The policy list is returned.');
            Assert.areEqual(1, options.assignmentCount, 'The delete options count the assignment.');
            Assert.isTrue(removed.assignments.isEmpty(), 'The assignment was removed.');
            Assert.areEqual(0, policyCount, 'The policy was deleted.');
            Assert.areEqual(listed.size() - 1, remaining.size(), 'The list comes back without the deleted policy.');
        }
    }

    @IsTest static void testScenario2() {

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

                        AIPoliciesController.getPolicies();
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIPoliciesController.savePolicy(null, new Map<String, Object>{'Name' => 'Nope'});
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIPoliciesController.getDeleteOptions(users[0].Id);
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIPoliciesController.deletePolicy(users[0].Id, null);
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIPoliciesController.findAssignees(null, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, 'Assist');
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIPoliciesController.getAssignmentWarning(users[0].Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, users[0].Id);
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIPoliciesController.addAssignment(users[0].Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, users[0].Id);
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIPoliciesController.setAssignmentActive(users[0].Id, true);
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIPoliciesController.removeAssignment(users[0].Id);
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIPoliciesController.checkUser(users[0].Id);
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }
                }
            Test.stopTest();

            // [3] Check every call was refused with the access label, and nothing was logged
            Assert.areEqual(10, refusals.size(), 'All ten calls are refused.');
            Assert.areEqual(new Set<String>{Label.AI_Settings_Error_Access}, new Set<String>(refusals), 'Every refusal shows the access label.');
            Assert.areEqual(0, [SELECT COUNT() FROM AIPlatformLog__c], 'A refusal is not an error, so nothing should be logged.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a policy with a bad limit
            Map<String, Object> values = new Map<String, Object>{
                'Name' => 'Bad',
                'MaxTokensPer24Hours__c' => -5
            };
            String refusal;

            // [2] Try to save the policy
            Test.startTest();
                try {

                    AIPoliciesController.savePolicy(null, values);
                } catch (AuraHandledException ex) {

                    refusal = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check the tab gets the readable message
            Assert.isTrue(refusal != null && refusal.contains('above zero'), 'The refusal reaches the tab as a readable message.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a policy whose limit is a whole number too big for the field, which the platform refuses on save
            Map<String, Object> values = new Map<String, Object>{
                'Name' => 'Too big',
                'MaxTokensPer24Hours__c' => '99999999999999999999999999999'
            };
            String refusal;

            // [2] Save it
            Test.startTest();
                try {

                    AIPoliciesController.savePolicy(null, values);
                } catch (AuraHandledException ex) {

                    refusal = ex.getMessage();
                }
            Test.stopTest();

            // [3] Read the log
            List<AIPlatformLog__c> logs = [SELECT ClassName__c, MethodName__c FROM AIPlatformLog__c];

            // [4] Check the outcome
            Assert.areEqual(Label.AI_Error_Generic, refusal, 'The generic label should be shown.');
            Assert.areEqual(1, logs.size(), 'The error should be logged once.');
            Assert.areEqual('AIPoliciesController', logs[0].ClassName__c, 'The log should name the controller.');
            Assert.areEqual('savePolicy', logs[0].MethodName__c, 'The log should name the method.');
        }
    }
}
