/*
Class Name: AIAssistPolicyEditorServiceTest

=================================================================
=================================================================

Description: Testing utility for AIAssistPolicyEditorService: reading, saving and deleting usage policies, and assigning them to users and permission sets.

=================================================================
=================================================================
Applicable Classes:

AIAssistPolicyEditorService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIAssistPolicyEditorServiceTest {

    // testScenario1: A manager saves a new policy and reads the list -> the policy is created with its values and appears in the list.
    // testScenario2: A manager saves a policy with no name, a zero limit, a decimal limit, an unlisted channel and an unknown field -> each is refused.
    // testScenario3: A manager edits a policy and clears a limit -> the changes are saved and the cleared limit is blank.
    // testScenario4: A manager assigns a policy to a user and to a permission set, switches one off, then removes it -> each change is reflected.
    // testScenario5: A manager assigns the same user twice, a missing permission set and a blank assignee -> each is refused.
    // testScenario6: A manager deletes a policy -> the policy and its assignments are gone, and deleting it again is refused.
    // testScenario7: A manager searches permission sets -> short text finds nothing and a real name finds a match.
    // testScenario8: A user without the Manage Settings permission calls the service -> the access label is shown.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the values for a new policy
            Map<String, Object> values = new Map<String, Object>{
                'Name' => 'Team leader',
                'Description__c' => 'Leaders',
                'IsActive__c' => true,
                'MaxTokensPer24Hours__c' => '500,000',
                'MaxConversationsPer24Hours__c' => 100,
                'UsageLimitReachedBehavior__c' => 'Notify Only',
                'AllowedChannels__c' => new List<Object>{AIAssistApplicationConstants.CHANNEL_RECORD_PAGE_CHAT}
            };

            // [2] Save the new policy and read the list
            Test.startTest();
                AIAssistSettingsDataStructure.PolicyView saved = AIAssistPolicyEditorService.savePolicy(null, values);
                List<AIAssistSettingsDataStructure.PolicyView> policies = AIAssistPolicyEditorService.getPolicies();
            Test.stopTest();

            // [3] Collect the ids of the listed policies
            Set<Id> listedIds = new Set<Id>();

            for (AIAssistSettingsDataStructure.PolicyView policy : policies) {

                listedIds.add(policy.policyId);
            }

            // [4] Check the saved policy and the list
            Assert.areEqual('Team leader', saved.name, 'The name was saved.');
            Assert.areEqual(500000, saved.values.get('MaxTokensPer24Hours__c'), 'A limit with a comma is read as a number.');
            Assert.areEqual(AIAssistApplicationConstants.CHANNEL_RECORD_PAGE_CHAT, saved.values.get('AllowedChannels__c'), 'The channel list was saved.');
            Assert.isTrue(listedIds.contains(saved.policyId), 'The policy is in the list.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build each bad set of values
            Map<String, Object> noNameValues = new Map<String, Object>{'IsActive__c' => true};
            Map<String, Object> zeroLimitValues = new Map<String, Object>{
                'Name' => 'A',
                'MaxTokensPer24Hours__c' => 0
            };
            Map<String, Object> decimalLimitValues = new Map<String, Object>{
                'Name' => 'A',
                'MaxConcurrentConversations__c' => '2.5'
            };
            Map<String, Object> badChannelValues = new Map<String, Object>{
                'Name' => 'A',
                'AllowedChannels__c' => new List<Object>{'Carrier Pigeon'}
            };
            Map<String, Object> unknownFieldValues = new Map<String, Object>{
                'Name' => 'A',
                'OwnerId' => UserInfo.getUserId()
            };
            String noName;
            String zeroLimit;
            String decimalLimit;
            String badChannel;
            String unknownField;

            // [2] Try each bad save and keep each message
            Test.startTest();
                try {

                    AIAssistPolicyEditorService.savePolicy(null, noNameValues);
                } catch (Exception ex) {

                    noName = ex.getMessage();
                }

                try {

                    AIAssistPolicyEditorService.savePolicy(null, zeroLimitValues);
                } catch (Exception ex) {

                    zeroLimit = ex.getMessage();
                }

                try {

                    AIAssistPolicyEditorService.savePolicy(null, decimalLimitValues);
                } catch (Exception ex) {

                    decimalLimit = ex.getMessage();
                }

                try {

                    AIAssistPolicyEditorService.savePolicy(null, badChannelValues);
                } catch (Exception ex) {

                    badChannel = ex.getMessage();
                }

                try {

                    AIAssistPolicyEditorService.savePolicy(null, unknownFieldValues);
                } catch (Exception ex) {

                    unknownField = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check each was refused
            Assert.isTrue(noName != null && noName.contains('is required'), 'A policy with no name is refused.');
            Assert.isTrue(zeroLimit != null && zeroLimit.contains('above zero'), 'A zero limit is refused.');
            Assert.isTrue(decimalLimit != null && decimalLimit.contains('above zero'), 'A decimal limit is refused.');
            Assert.isTrue(badChannel != null && badChannel.contains('not allowed'), 'A channel the field does not list is refused.');
            Assert.isTrue(unknownField != null && unknownField.contains('cannot be set'), 'A field the tab does not list is refused.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a policy with a limit
            AIAssistSettingsDataStructure.PolicyView created = AIAssistPolicyEditorService.savePolicy(null, new Map<String, Object>{
                'Name' => 'Support',
                'MaxTokensPer24Hours__c' => 1000
            });

            // [2] Build the changes that rename the policy, clear the limit and switch debug on
            Map<String, Object> changes = new Map<String, Object>{
                'Name' => 'Support team',
                'MaxTokensPer24Hours__c' => '',
                'DebugModeEnabled__c' => true
            };

            // [3] Save the changes
            Test.startTest();
                AIAssistSettingsDataStructure.PolicyView edited = AIAssistPolicyEditorService.savePolicy(created.policyId, changes);
            Test.stopTest();

            // [4] Count the policies with the same id
            Integer policyCount = [SELECT COUNT() FROM AIUsagePolicy__c WHERE Id = :created.policyId];

            // [5] Check the changes
            Assert.areEqual('Support team', edited.name, 'The name changed.');
            Assert.isNull(edited.values.get('MaxTokensPer24Hours__c'), 'A cleared limit is blank.');
            Assert.areEqual(true, edited.values.get('DebugModeEnabled__c'), 'Debug mode was switched on.');
            Assert.areEqual(1, policyCount, 'The same policy was edited, not copied.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a policy and a user to assign
            AIAssistSettingsDataStructure.PolicyView policy = AIAssistPolicyEditorService.savePolicy(null, new Map<String, Object>{'Name' => 'Assigned'});
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);

            // [2] Assign the user and the AIAssistUser permission set
            AIAssistPolicyEditorService.addAssignment(policy.policyId, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, users[0].Id, null);
            AIAssistSettingsDataStructure.PolicyView afterBoth = AIAssistPolicyEditorService.addAssignment(policy.policyId, AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, null, 'AIAssistUser');

            // [3] Find the id of each assignment
            Id userAssignmentId;
            Id permissionSetAssignmentId;

            for (AIAssistSettingsDataStructure.PolicyAssignmentView assignment : afterBoth.assignments) {

                if (assignment.assigneeType == AIAssistApplicationConstants.ASSIGNEE_TYPE_USER) {

                    userAssignmentId = assignment.assignmentId;
                } else {

                    permissionSetAssignmentId = assignment.assignmentId;
                }
            }

            // [4] Switch the user assignment off, then remove the permission set assignment
            Test.startTest();
                AIAssistPolicyEditorService.setAssignmentActive(userAssignmentId, false);
                AIAssistSettingsDataStructure.PolicyView afterRemove = AIAssistPolicyEditorService.removeAssignment(permissionSetAssignmentId);
            Test.stopTest();

            // [5] Read the user assignment back
            AIUsagePolicyAssignment__c userAssignment = [SELECT User__c FROM AIUsagePolicyAssignment__c WHERE Id = :userAssignmentId];

            // [6] Check each step
            Assert.areEqual(2, afterBoth.assignments.size(), 'Both assignments were added.');
            Assert.areEqual(1, afterRemove.assignments.size(), 'The permission set assignment was removed.');
            Assert.areEqual(false, afterRemove.assignments[0].isActive, 'The user assignment was switched off.');
            Assert.areEqual(users[0].Id, userAssignment.User__c, 'The assignment is for the user.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a policy and assign a user once
            AIAssistSettingsDataStructure.PolicyView policy = AIAssistPolicyEditorService.savePolicy(null, new Map<String, Object>{'Name' => 'Strict'});
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistPolicyEditorService.addAssignment(policy.policyId, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, users[0].Id, null);
            List<String> refusals = new List<String>();

            // [2] Try the same user again, a missing permission set, a blank assignee and an unknown type
            Test.startTest();
                try {

                    AIAssistPolicyEditorService.addAssignment(policy.policyId, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, users[0].Id, null);
                } catch (AIAssistPolicyEditorService.AIAssistPolicyEditorServiceException ex) {

                    refusals.add(ex.getMessage());
                }

                try {

                    AIAssistPolicyEditorService.addAssignment(policy.policyId, AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, null, 'NoSuchPermissionSet');
                } catch (AIAssistPolicyEditorService.AIAssistPolicyEditorServiceException ex) {

                    refusals.add(ex.getMessage());
                }

                try {

                    AIAssistPolicyEditorService.addAssignment(policy.policyId, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, null, null);
                } catch (AIAssistPolicyEditorService.AIAssistPolicyEditorServiceException ex) {

                    refusals.add(ex.getMessage());
                }

                try {

                    AIAssistPolicyEditorService.addAssignment(policy.policyId, 'Team', null, null);
                } catch (AIAssistPolicyEditorService.AIAssistPolicyEditorServiceException ex) {

                    refusals.add(ex.getMessage());
                }
            Test.stopTest();

            // [3] Build the messages each refusal should show
            List<String> expectedRefusals = new List<String>{
                Label.AI_Settings_Policy_Error_Duplicate,
                Label.AI_Settings_Policy_Error_Permission_Set,
                Label.AI_Settings_Policy_Error_Assignee,
                Label.AI_Settings_Policy_Error_Assignee
            };

            // [4] Check each was refused with its own message
            Assert.areEqual(expectedRefusals, refusals, 'Each bad assignment is refused with the right message.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a policy with an assignment
            AIAssistSettingsDataStructure.PolicyView policy = AIAssistPolicyEditorService.savePolicy(null, new Map<String, Object>{'Name' => 'Temporary'});
            AIAssistPolicyEditorService.addAssignment(policy.policyId, AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, null, 'AIAssistUser');
            String secondRefusal;

            // [2] Delete the policy, then try to delete it again
            Test.startTest();
                AIAssistPolicyEditorService.deletePolicy(policy.policyId);

                try {

                    AIAssistPolicyEditorService.deletePolicy(policy.policyId);
                } catch (AIAssistPolicyEditorService.AIAssistPolicyEditorServiceException ex) {

                    secondRefusal = ex.getMessage();
                }
            Test.stopTest();

            // [3] Count what is left of the policy and its assignments
            Integer policyCount = [SELECT COUNT() FROM AIUsagePolicy__c WHERE Id = :policy.policyId];
            Integer assignmentCount = [SELECT COUNT() FROM AIUsagePolicyAssignment__c WHERE AIUsagePolicy__c = :policy.policyId];

            // [4] Check the policy and its assignment are gone
            Assert.areEqual(0, policyCount, 'The policy is deleted.');
            Assert.areEqual(0, assignmentCount, 'Its assignments are deleted.');
            Assert.areEqual(Label.AI_Settings_Error_Row_Not_Found, secondRefusal, 'Deleting it again is refused.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Search with too little text and then with a real permission set name
            Test.startTest();
                List<AIAssistSettingsDataStructure.OwnerOption> shortResults = AIAssistPolicyEditorService.findPermissionSets('A');
                List<AIAssistSettingsDataStructure.OwnerOption> found = AIAssistPolicyEditorService.findPermissionSets('AIAssistUser');
            Test.stopTest();

            // [2] Collect the names that were found
            Set<String> foundNames = new Set<String>();

            for (AIAssistSettingsDataStructure.OwnerOption option : found) {

                foundNames.add(option.name);
            }

            // [3] Check the results
            Assert.isTrue(shortResults.isEmpty(), 'Short text finds nothing.');
            Assert.isTrue(foundNames.contains('AIAssistUser'), 'A permission set is found by its name.');
        }
    }

    @IsTest static void testScenario8() {

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

                        AIAssistPolicyEditorService.getPolicies();
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIAssistPolicyEditorService.savePolicy(null, new Map<String, Object>{'Name' => 'No'});
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIAssistPolicyEditorService.deletePolicy(users[0].Id);
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIAssistPolicyEditorService.addAssignment(users[0].Id, AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, users[0].Id, null);
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIAssistPolicyEditorService.setAssignmentActive(users[0].Id, true);
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIAssistPolicyEditorService.removeAssignment(users[0].Id);
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIAssistPolicyEditorService.findPermissionSets('AIAssist');
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

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
