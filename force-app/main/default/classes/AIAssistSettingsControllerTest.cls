/*
Class Name: AIAssistSettingsControllerTest

=================================================================
=================================================================

Description: Testing utility for AIAssistSettingsController: each tab call reaches the service, and a refusal reaches the tab as a readable message.

=================================================================
=================================================================
Applicable Classes:

AIAssistSettingsController: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIAssistSettingsControllerTest {

    // testScenario1: A manager opens the tab, saves a UI row, finds an owner and deletes the row -> each call returns what the service returns.
    // testScenario2: A manager saves a policy, assigns it, switches and removes the assignment, searches permission sets and deletes the policy -> each call returns what the service returns.
    // testScenario3: A manager saves a policy with a bad limit -> the tab gets a readable message.
    // testScenario4: A user without the permission calls every method -> each throws the access label as an AuraHandledException.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Open the tab, save a user UI row, search for users and delete the row
            Test.startTest();
                AIAssistSettingsDataStructure.SettingsPage page = AIAssistSettingsController.getSettingsPage();
                AIAssistSettingsDataStructure.SettingsRow savedRow = AIAssistSettingsController.saveSettingsRow(AIAssistApplicationConstants.SETTINGS_NAME_UI, AIAssistApplicationConstants.SETTINGS_SCOPE_USER, superUser.Id, new Map<String, Object>{'IsMaintenanceMode__c' => true});
                List<AIAssistSettingsDataStructure.OwnerOption> owners = AIAssistSettingsController.findOwners(AIAssistApplicationConstants.SETTINGS_SCOPE_USER, 'Assist Tester');
                AIAssistSettingsController.deleteSettingsRow(AIAssistApplicationConstants.SETTINGS_NAME_UI, savedRow.rowId);
            Test.stopTest();

            // [2] Count the UI rows left for the user
            Integer rowCount = [SELECT COUNT() FROM AIAssistUISettings__c WHERE SetupOwnerId = :superUser.Id];

            // [3] Check each answer
            Assert.areEqual(AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION, page.assistRows[0].scope, 'The page opens with the organisation row.');
            Assert.areEqual(true, savedRow.values.get('IsMaintenanceMode__c'), 'The saved row is returned.');
            Assert.isFalse(owners.isEmpty(), 'The owner search returns the test user.');
            Assert.areEqual(0, rowCount, 'The row was deleted.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Save a policy, assign a user, switch the assignment off, search, remove it and delete the policy
            Test.startTest();
                AIAssistSettingsDataStructure.PolicyView saved = AIAssistSettingsController.savePolicy(null, new Map<String, Object>{'Name' => 'Controller policy'});
                AIAssistSettingsDataStructure.PolicyView assigned = AIAssistSettingsController.addPolicyAssignment(saved.policyId, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, superUser.Id, null);
                AIAssistSettingsDataStructure.PolicyView switchedOff = AIAssistSettingsController.setPolicyAssignmentActive(assigned.assignments[0].assignmentId, false);
                List<AIAssistSettingsDataStructure.OwnerOption> permissionSets = AIAssistSettingsController.findPermissionSets('AIAssistUser');
                List<AIAssistSettingsDataStructure.PolicyView> listed = AIAssistSettingsController.getPolicies();
                AIAssistSettingsDataStructure.PolicyView removed = AIAssistSettingsController.removePolicyAssignment(assigned.assignments[0].assignmentId);
                AIAssistSettingsController.deletePolicy(saved.policyId);
            Test.stopTest();

            // [2] Count the policies left with the saved id
            Integer policyCount = [SELECT COUNT() FROM AIUsagePolicy__c WHERE Id = :saved.policyId];

            // [3] Check each answer
            Assert.areEqual(false, switchedOff.assignments[0].isActive, 'The assignment was switched off.');
            Assert.isFalse(permissionSets.isEmpty(), 'The permission set search returns a match.');
            Assert.isFalse(listed.isEmpty(), 'The policy list is returned.');
            Assert.isTrue(removed.assignments.isEmpty(), 'The assignment was removed.');
            Assert.areEqual(0, policyCount, 'The policy was deleted.');
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

                    AIAssistSettingsController.savePolicy(null, values);
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
            // [1] Create a user who holds only the end user permission set
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            List<String> refusals = new List<String>();

            // [2] Call each method as that user and keep each message
            Test.startTest();
                System.runAs(users[0]) {
                    try {

                        AIAssistSettingsController.getSettingsPage();
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIAssistSettingsController.saveSettingsRow(AIAssistApplicationConstants.SETTINGS_NAME_UI, AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION, null, new Map<String, Object>());
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIAssistSettingsController.deleteSettingsRow(AIAssistApplicationConstants.SETTINGS_NAME_UI, users[0].Id);
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIAssistSettingsController.findOwners(AIAssistApplicationConstants.SETTINGS_SCOPE_USER, 'Assist');
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }
                }
            Test.stopTest();

            // [3] Check every call was refused with the access label
            Assert.areEqual(4, refusals.size(), 'All four calls are refused.');
            Assert.areEqual(new Set<String>{Label.AI_Settings_Error_Access}, new Set<String>(refusals), 'Every refusal shows the access label.');
        }
    }
}
