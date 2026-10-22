/*
Class Name: AIPoliciesAssignmentServiceTest

=================================================================
=================================================================

Description: Testing utility for AIPoliciesAssignmentService: finding users and permission sets, warning about a policy they already have, and adding, switching and removing assignments.

=================================================================
=================================================================
Applicable Classes:

AIPoliciesAssignmentService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPoliciesAssignmentServiceTest {

    // testScenario1: A manager searches permission sets with too little text, then with a real name, before and after one is assigned -> nothing, then a match that gets the default policy, then a match on its own policy with its users counted.
    // testScenario2: A manager searches users with too little text, then by name, before and after a user is assigned, and with an unknown type -> nothing, a user on the default policy, a user on their own policy, then a refusal.
    // testScenario3: A manager asks what adding a permission set, a user and a policy with no limits would do -> a sentence naming the stricter policy where there is a clash, and no warning where there is none.
    // testScenario4: A manager assigns a policy to a user, a permission set and a permission set group, switches one off and removes another -> each change is reflected.
    // testScenario5: A manager assigns the same user twice, a missing permission set, a blank user, an unknown type and a missing assignment -> each is refused.
    // testScenario6: The users of a permission set are counted and the labels are looked up -> counted users, zero for an unknown name, and the name itself as a label when none is found.
    // testScenario7: A user without the Manage Settings permission calls the service -> the access label is shown.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a policy, the default policy that the factory made already covers everyone, and one user holding the permission set
            AIUsagePolicy__c policy = new AIUsagePolicy__c(Name = 'Advisers', IsActive__c = true);
            insert policy;
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');

            // [2] Search with too little text and then with a real name, before an assignment
            Test.startTest();
                List<AIPoliciesDataStructure.AssigneeOption> shortResults = AIPoliciesAssignmentService.findAssignees(policy.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, 'A');
                List<AIPoliciesDataStructure.AssigneeOption> before = AIPoliciesAssignmentService.findAssignees(policy.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, 'AIAssistUser');

                // [3] Assign the permission set to the policy and search again
                insert new AIUsagePolicyAssignment__c(AIUsagePolicy__c = policy.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, PermissionSetName__c = 'AIAssistUser', IsActive__c = true);
                List<AIPoliciesDataStructure.AssigneeOption> after = AIPoliciesAssignmentService.findAssignees(policy.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, 'AIAssistUser');
            Test.stopTest();

            // [4] Pick the match out of each result
            AIPoliciesDataStructure.AssigneeOption beforeMatch;
            AIPoliciesDataStructure.AssigneeOption afterMatch;

            for (AIPoliciesDataStructure.AssigneeOption option : before) {

                if (option.detail == 'AIAssistUser') beforeMatch = option;
            }

            for (AIPoliciesDataStructure.AssigneeOption option : after) {

                if (option.detail == 'AIAssistUser') afterMatch = option;
            }

            // [5] Check the results
            Assert.isTrue(shortResults.isEmpty(), 'Short text finds nothing.');
            Assert.isNotNull(beforeMatch, 'A permission set is found by its API name.');
            Assert.isFalse(beforeMatch.hasPolicy, 'It has no policy of its own yet.');
            Assert.isTrue(beforeMatch.isCurrentPolicyDefault, 'Without one it gets the default policy.');
            Assert.isTrue(beforeMatch.usersCovered >= 1, 'The user holding it is counted.');
            Assert.isTrue(afterMatch.hasPolicy && afterMatch.isOnThisPolicy, 'It is now assigned to this policy.');
            Assert.areEqual(policy.Id, afterMatch.currentPolicyId, 'It gets the policy it is assigned to.');
            Assert.areEqual('Advisers', afterMatch.currentPolicyName, 'The policy name is returned.');
            Assert.isFalse(afterMatch.isCurrentPolicyDefault, 'It no longer gets the default.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a policy and a user to find
            AIUsagePolicy__c policy = new AIUsagePolicy__c(Name = 'Exceptions', IsActive__c = true);
            insert policy;
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            String refusal;

            // [2] Search with too little text and then by name, before an assignment
            Test.startTest();
                List<AIPoliciesDataStructure.AssigneeOption> shortResults = AIPoliciesAssignmentService.findAssignees(policy.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, 'A');
                List<AIPoliciesDataStructure.AssigneeOption> before = AIPoliciesAssignmentService.findAssignees(policy.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, users[0].Username);

                // [3] Assign the user to the policy and search again, then try an unknown type
                insert new AIUsagePolicyAssignment__c(AIUsagePolicy__c = policy.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, User__c = users[0].Id, IsActive__c = true);
                List<AIPoliciesDataStructure.AssigneeOption> after = AIPoliciesAssignmentService.findAssignees(null, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, users[0].Username);

                try {

                    AIPoliciesAssignmentService.findAssignees(policy.Id, 'Team', 'Assist');
                } catch (Exception ex) {

                    refusal = ex.getMessage();
                }
            Test.stopTest();

            // [4] Check the results
            Assert.isTrue(shortResults.isEmpty(), 'Short text finds nothing.');
            Assert.areEqual(1, before.size(), 'The user is found by username.');
            Assert.isFalse(before[0].hasPolicy, 'They have no user assignment yet.');
            Assert.isTrue(before[0].isCurrentPolicyDefault, 'They get the default policy.');
            Assert.areEqual(1, before[0].usersCovered, 'A user covers one user.');
            Assert.isTrue(after[0].hasPolicy, 'They now have a user assignment.');
            Assert.isFalse(after[0].isOnThisPolicy, 'With no policy being edited they are not on it.');
            Assert.areEqual(policy.Id, after[0].currentPolicyId, 'They get the policy they are assigned to.');
            Assert.areEqual(Label.AI_Policies_Error_Assignee, refusal, 'An unknown type is refused.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a loose policy, a strict policy and two policies with no limits
            AIUsagePolicy__c loose = new AIUsagePolicy__c(Name = 'Team leaders', IsActive__c = true, MaxTokensPer24Hours__c = 500000);
            AIUsagePolicy__c strict = new AIUsagePolicy__c(Name = 'Advisers default', IsActive__c = true, MaxTokensPer24Hours__c = 200000);
            AIUsagePolicy__c openOne = new AIUsagePolicy__c(Name = 'Open one', IsActive__c = true);
            AIUsagePolicy__c openTwo = new AIUsagePolicy__c(Name = 'Open two', IsActive__c = true);
            insert new List<AIUsagePolicy__c>{loose, strict, openOne, openTwo};
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);
            Id leadersSetId = [SELECT Id FROM PermissionSet WHERE Name = 'AIAssistUser' LIMIT 1].Id;
            Id adminSetId = [SELECT Id FROM PermissionSet WHERE Name = 'AIAssistAdminUser' LIMIT 1].Id;

            // [2] Assign a permission set and a user to the loose policy, and another permission set to a policy with no limits
            insert new List<AIUsagePolicyAssignment__c>{
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = loose.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, PermissionSetName__c = 'AIAssistUser', IsActive__c = true),
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = loose.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, User__c = users[0].Id, IsActive__c = true),
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = openOne.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, PermissionSetName__c = 'AIAssistAdminUser', IsActive__c = true)
            };

            // [3] Ask what adding each would do
            Test.startTest();
                AIPoliciesDataStructure.AssignmentWarning permissionSetWarning = AIPoliciesAssignmentService.getAssignmentWarning(strict.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, leadersSetId);
                AIPoliciesDataStructure.AssignmentWarning userWarning = AIPoliciesAssignmentService.getAssignmentWarning(strict.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, users[0].Id);
                AIPoliciesDataStructure.AssignmentWarning noLimitWarning = AIPoliciesAssignmentService.getAssignmentWarning(openTwo.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, adminSetId);
                AIPoliciesDataStructure.AssignmentWarning noClashWarning = AIPoliciesAssignmentService.getAssignmentWarning(strict.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, users[1].Id);
                AIPoliciesDataStructure.AssignmentWarning missingUserWarning = AIPoliciesAssignmentService.getAssignmentWarning(strict.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, strict.Id);
            Test.stopTest();

            // [4] Check each sentence
            Assert.isTrue(permissionSetWarning.hasWarning, 'A permission set that already has a policy warns.');
            Assert.isTrue(permissionSetWarning.message.contains('Team leaders') && permissionSetWarning.message.contains('Advisers default') && permissionSetWarning.message.contains('200,000'), 'The sentence names both policies and the stricter limit.');
            Assert.isTrue(userWarning.hasWarning && userWarning.message.contains('already has a user assignment'), 'A user who already has a user assignment warns.');
            Assert.isTrue(noLimitWarning.hasWarning && noLimitWarning.message.contains(Label.AI_Policies_No_Token_Limit), 'Policies with no token limit say so.');
            Assert.isFalse(noClashWarning.hasWarning, 'A user with no assignment does not warn.');
            Assert.isFalse(missingUserWarning.hasWarning, 'A user that is not found does not warn.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a policy, a user, a permission set and a permission set group
            AIUsagePolicy__c policy = new AIUsagePolicy__c(Name = 'Assignments', IsActive__c = true);
            insert policy;
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'AIAssistUser' LIMIT 1].Id;
            PermissionSetGroup permissionSetGroup = new PermissionSetGroup(DeveloperName = 'AIPoliciesTestGroup', MasterLabel = 'AI Policies Test Group');

            System.runAs(AIAssistTestDataFactory.getSetupUser()) {

                insert permissionSetGroup;
            }

            // [2] Assign the user, the permission set and the group, then find the group through a search
            Test.startTest();
                AIPoliciesAssignmentService.addAssignment(policy.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, users[0].Id);
                AIPoliciesAssignmentService.addAssignment(policy.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, permissionSetId);
                AIPoliciesDataStructure.PolicyView assigned = AIPoliciesAssignmentService.addAssignment(policy.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, permissionSetGroup.Id);
                List<AIPoliciesDataStructure.AssigneeOption> groups = AIPoliciesAssignmentService.findAssignees(policy.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, 'AIPoliciesTestGroup');
            Test.stopTest();

            // [3] Find the assignments and switch the user one off and remove the permission set one
            Map<String, Id> assignmentIdsByName = new Map<String, Id>();

            for (AIPoliciesDataStructure.AssignmentView assignment : assigned.assignments) {

                assignmentIdsByName.put(assignment.assigneeDetail, assignment.assignmentId);
            }

            AIPoliciesDataStructure.PolicyView switchedOff = AIPoliciesAssignmentService.setAssignmentActive(assignmentIdsByName.get(users[0].Username), false);
            AIPoliciesDataStructure.PolicyView removed = AIPoliciesAssignmentService.removeAssignment(assignmentIdsByName.get('AIAssistUser'));

            // [4] Read the user assignment back
            AIUsagePolicyAssignment__c userAssignment = [SELECT IsActive__c FROM AIUsagePolicyAssignment__c WHERE Id = :assignmentIdsByName.get(users[0].Username)];

            // [5] Check each step
            Assert.areEqual(3, assigned.assignments.size(), 'All three assignments were added.');
            Assert.isTrue(assignmentIdsByName.containsKey('AIPoliciesTestGroup'), 'The group is stored by its API name.');
            Assert.areEqual(1, groups.size(), 'The group is found by search.');
            Assert.areEqual('AI Policies Test Group', groups[0].name, 'The group label is shown.');
            Assert.isFalse(userAssignment.IsActive__c, 'The user assignment was switched off.');
            Assert.areEqual(3, switchedOff.assignments.size(), 'Switching off keeps the assignment.');
            Assert.areEqual(2, removed.assignments.size(), 'Removing takes the permission set assignment away.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a policy and assign a user once
            AIUsagePolicy__c policy = new AIUsagePolicy__c(Name = 'Refusals', IsActive__c = true);
            insert policy;
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIPoliciesAssignmentService.addAssignment(policy.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, users[0].Id);
            Id missingId = AIUsagePolicy__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
            String duplicate;
            String missingSet;
            String blankSet;
            String blankUser;
            String notAUser;
            String unknownType;
            String missingAssignment;
            String missingPolicy;

            // [2] Try each bad call and keep each message
            Test.startTest();
                try {

                    AIPoliciesAssignmentService.addAssignment(policy.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, users[0].Id);
                } catch (Exception ex) {

                    duplicate = ex.getMessage();
                }

                try {

                    AIPoliciesAssignmentService.addAssignment(policy.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, missingId);
                } catch (Exception ex) {

                    missingSet = ex.getMessage();
                }

                try {

                    AIPoliciesAssignmentService.addAssignment(policy.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, null);
                } catch (Exception ex) {

                    blankSet = ex.getMessage();
                }

                try {

                    AIPoliciesAssignmentService.addAssignment(policy.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, null);
                } catch (Exception ex) {

                    blankUser = ex.getMessage();
                }

                try {

                    AIPoliciesAssignmentService.addAssignment(policy.Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, policy.Id);
                } catch (Exception ex) {

                    notAUser = ex.getMessage();
                }

                try {

                    AIPoliciesAssignmentService.addAssignment(policy.Id, 'Team', users[0].Id);
                } catch (Exception ex) {

                    unknownType = ex.getMessage();
                }

                try {

                    AIPoliciesAssignmentService.setAssignmentActive(missingId, true);
                } catch (Exception ex) {

                    missingAssignment = ex.getMessage();
                }

                try {

                    AIPoliciesAssignmentService.addAssignment(missingId, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, users[0].Id);
                } catch (Exception ex) {

                    missingPolicy = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check each was refused with its own message
            Assert.areEqual(Label.AI_Policies_Error_Duplicate, duplicate, 'The same user twice is refused.');
            Assert.areEqual(Label.AI_Policies_Error_Permission_Set, missingSet, 'A permission set that does not exist is refused.');
            Assert.areEqual(Label.AI_Policies_Error_Permission_Set, blankSet, 'A blank permission set is refused.');
            Assert.areEqual(Label.AI_Policies_Error_Assignee, blankUser, 'A blank user is refused.');
            Assert.areEqual(Label.AI_Policies_Error_Assignee, notAUser, 'An Id that is not a user is refused.');
            Assert.areEqual(Label.AI_Policies_Error_Assignee, unknownType, 'An unknown type is refused.');
            Assert.areEqual(Label.AI_Settings_Error_Row_Not_Found, missingAssignment, 'An assignment that is gone is refused.');
            Assert.areEqual(Label.AI_Settings_Error_Row_Not_Found, missingPolicy, 'A policy that is gone is refused.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two users holding the same permission set
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            PermissionSetGroup permissionSetGroup = new PermissionSetGroup(DeveloperName = 'AIPoliciesCountGroup', MasterLabel = 'AI Policies Count Group');

            Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'AIAssistUser' LIMIT 1].Id;

            System.runAs(AIAssistTestDataFactory.getSetupUser()) {

                insert permissionSetGroup;
                insert new PermissionSetGroupComponent(PermissionSetGroupId = permissionSetGroup.Id, PermissionSetId = permissionSetId);
                Test.calculatePermissionSetGroup(permissionSetGroup.Id);
                insert new PermissionSetAssignment(AssigneeId = users[0].Id, PermissionSetGroupId = permissionSetGroup.Id);
            }

            // [2] Count the users and look up the labels
            Test.startTest();
                Map<String, Integer> counts = AIPoliciesAssignmentService.getUsersCovered(new Set<String>{'AIAssistUser', 'AIPoliciesCountGroup', 'NoSuchSet'});
                Map<String, Integer> noCounts = AIPoliciesAssignmentService.getUsersCovered(new Set<String>());
                Map<String, String> labels = AIPoliciesAssignmentService.getPermissionSetLabels(new Set<String>{'AIAssistUser', 'AIPoliciesCountGroup', 'NoSuchSet'});
                Map<String, String> noLabels = AIPoliciesAssignmentService.getPermissionSetLabels(new Set<String>());
            Test.stopTest();

            // [3] Check the counts and labels
            Assert.isTrue(counts.get('AIAssistUser') >= 2, 'Both users holding the set are counted.');
            Assert.areEqual(1, counts.get('AIPoliciesCountGroup'), 'A group counts the user assigned to it.');
            Assert.areEqual(0, counts.get('NoSuchSet'), 'An unknown name counts zero.');
            Assert.isTrue(noCounts.isEmpty(), 'No names means no counts.');
            Assert.areEqual('AI Policies Count Group', labels.get('AIPoliciesCountGroup'), 'A group shows its label.');
            Assert.areEqual('NoSuchSet', labels.get('NoSuchSet'), 'An unknown name is its own label.');
            Assert.isNotNull(labels.get('AIAssistUser'), 'A permission set shows a label.');
            Assert.isTrue(noLabels.isEmpty(), 'No names means no labels.');
        }
    }

    @IsTest static void testScenario7() {

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

                        AIPoliciesAssignmentService.findAssignees(null, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, 'Assist');
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIPoliciesAssignmentService.getAssignmentWarning(users[0].Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, users[0].Id);
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIPoliciesAssignmentService.addAssignment(users[0].Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, users[0].Id);
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIPoliciesAssignmentService.setAssignmentActive(users[0].Id, true);
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIPoliciesAssignmentService.removeAssignment(users[0].Id);
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }
                }
            Test.stopTest();

            // [3] Check every call was refused with the access label
            Assert.areEqual(5, refusals.size(), 'All five calls are refused.');
            Assert.areEqual(new Set<String>{Label.AI_Settings_Error_Access}, new Set<String>(refusals), 'Every refusal shows the access label.');
        }
    }
}
