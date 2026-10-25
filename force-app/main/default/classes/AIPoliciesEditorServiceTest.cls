/*
Class Name: AIPoliciesEditorServiceTest

=================================================================
=================================================================

Description: Testing utility for AIPoliciesEditorService: reading, saving and deleting usage policies, and moving their people on delete.

=================================================================
=================================================================
Applicable Classes:

AIPoliciesEditorService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPoliciesEditorServiceTest {

    // testScenario1: A manager saves a new policy and reads the list -> the policy is created with its values and appears in the list.
    // testScenario2: A manager saves a policy with no name, a zero limit, a decimal limit, an unlisted channel and an unknown field -> each is refused.
    // testScenario3: A manager edits a policy and clears a limit -> the changes are saved and the cleared limit is blank.
    // testScenario4: A manager makes a second policy the default, then tries to switch the only default off -> the first default is cleared, and switching off is refused.
    // testScenario5: A manager reads the delete options and deletes a policy that has assignments -> the people move to the other policy, a duplicate is dropped, and the list comes back without it.
    // testScenario6: A manager deletes the default policy, a policy with people and no place to move them, a policy into itself and a policy that is gone -> each is refused.
    // testScenario7: A manager deletes a policy with no assignments -> it is deleted without choosing where to move anyone.
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
                AIPoliciesDataStructure.PolicyView saved = AIPoliciesEditorService.savePolicy(null, values);
                List<AIPoliciesDataStructure.PolicyView> policies = AIPoliciesEditorService.getPolicies();
            Test.stopTest();

            // [3] Collect the ids of the listed policies
            Set<Id> listedIds = new Set<Id>();

            for (AIPoliciesDataStructure.PolicyView policy : policies) {

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
            Map<String, Object> notANumberValues = new Map<String, Object>{
                'Name' => 'A',
                'MaxTokensPer24Hours__c' => 'abc'
            };
            String notANumber;
            String noName;
            String zeroLimit;
            String decimalLimit;
            String badChannel;
            String unknownField;

            // [2] Try each bad save and keep each message
            Test.startTest();
                try {

                    AIPoliciesEditorService.savePolicy(null, noNameValues);
                } catch (Exception ex) {

                    noName = ex.getMessage();
                }

                try {

                    AIPoliciesEditorService.savePolicy(null, zeroLimitValues);
                } catch (Exception ex) {

                    zeroLimit = ex.getMessage();
                }

                try {

                    AIPoliciesEditorService.savePolicy(null, notANumberValues);
                } catch (Exception ex) {

                    notANumber = ex.getMessage();
                }

                try {

                    AIPoliciesEditorService.savePolicy(null, decimalLimitValues);
                } catch (Exception ex) {

                    decimalLimit = ex.getMessage();
                }

                try {

                    AIPoliciesEditorService.savePolicy(null, badChannelValues);
                } catch (Exception ex) {

                    badChannel = ex.getMessage();
                }

                try {

                    AIPoliciesEditorService.savePolicy(null, unknownFieldValues);
                } catch (Exception ex) {

                    unknownField = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check each was refused
            Assert.isTrue(noName != null && noName.contains('is required'), 'A policy with no name is refused.');
            Assert.isTrue(zeroLimit != null && zeroLimit.contains('above zero'), 'A zero limit is refused.');
            Assert.isTrue(notANumber != null && notANumber.contains('above zero'), 'A limit that is not a number is refused.');
            Assert.isTrue(decimalLimit != null && decimalLimit.contains('above zero'), 'A decimal limit is refused.');
            Assert.isTrue(badChannel != null && badChannel.contains('not allowed'), 'A channel the field does not list is refused.');
            Assert.isTrue(unknownField != null && unknownField.contains('cannot be set'), 'A field the tab does not list is refused.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a policy with a limit
            AIPoliciesDataStructure.PolicyView created = AIPoliciesEditorService.savePolicy(null, new Map<String, Object>{
                'Name' => 'Support',
                'MaxTokensPer24Hours__c' => 1000
            });

            // [2] Build the changes that rename the policy, clear the limit and switch debug on
            Map<String, Object> changes = new Map<String, Object>{
                'Name' => 'Support team',
                'MaxTokensPer24Hours__c' => '',
                'DebugModeEnabled__c' => true,
                'AllowedChannels__c' => AIAssistApplicationConstants.CHANNEL_RECORD_PAGE_CHAT + ';' + AIAssistApplicationConstants.CHANNEL_MOBILE
            };

            // [3] Save the changes
            Test.startTest();
                AIPoliciesDataStructure.PolicyView edited = AIPoliciesEditorService.savePolicy(created.policyId, changes);
            Test.stopTest();

            // [4] Count the policies with the same id
            Integer policyCount = [SELECT COUNT() FROM AIUsagePolicy__c WHERE Id = :created.policyId];

            // [5] Check the changes
            Assert.areEqual('Support team', edited.name, 'The name changed.');
            Assert.isNull(edited.values.get('MaxTokensPer24Hours__c'), 'A cleared limit is blank.');
            Assert.areEqual(true, edited.values.get('DebugModeEnabled__c'), 'Debug mode was switched on.');
            Assert.areEqual(AIAssistApplicationConstants.CHANNEL_RECORD_PAGE_CHAT + ';' + AIAssistApplicationConstants.CHANNEL_MOBILE, edited.values.get('AllowedChannels__c'), 'Channels sent as text are saved.');
            Assert.areEqual(1, policyCount, 'The same policy was edited, not copied.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a default policy
            AIPoliciesDataStructure.PolicyView first = AIPoliciesEditorService.savePolicy(null, new Map<String, Object>{'Name' => 'First', 'IsDefault__c' => true});
            String refusal;

            // [2] Make a second policy the default, then try to switch it off again
            Test.startTest();
                AIPoliciesDataStructure.PolicyView second = AIPoliciesEditorService.savePolicy(null, new Map<String, Object>{'Name' => 'Second', 'IsDefault__c' => true});

                try {

                    AIPoliciesEditorService.savePolicy(second.policyId, new Map<String, Object>{'IsDefault__c' => false});
                } catch (Exception ex) {

                    refusal = ex.getMessage();
                }
            Test.stopTest();

            // [3] Count the default policies
            List<AIUsagePolicy__c> defaults = [SELECT Id FROM AIUsagePolicy__c WHERE IsDefault__c = TRUE];

            // [4] Check only the second is the default, and the only default cannot be switched off
            Assert.areEqual(1, defaults.size(), 'Only one policy is the default.');
            Assert.areEqual(second.policyId, defaults[0].Id, 'The newest default policy is the one that stays.');
            Assert.areEqual(Label.AI_Policies_Error_Last_Default, refusal, 'The only default cannot be switched off.');
            Assert.areNotEqual(first.policyId, defaults[0].Id, 'The first policy lost the default.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a policy to delete and another to move to, with a shared user and their own permission set
            AIUsagePolicy__c doomed = new AIUsagePolicy__c(Name = 'Trial users', IsActive__c = true);
            AIUsagePolicy__c target = new AIUsagePolicy__c(Name = 'Advisers', IsActive__c = true);
            insert new List<AIUsagePolicy__c>{doomed, target};
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);
            insert new List<AIUsagePolicyAssignment__c>{
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = doomed.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, User__c = users[0].Id, IsActive__c = true),
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = doomed.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, User__c = users[1].Id, IsActive__c = true),
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = doomed.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, PermissionSetName__c = 'AIAssistUser', IsActive__c = true),
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = target.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, User__c = users[0].Id, IsActive__c = true)
            };

            // [2] Read the delete options, delete the policy moving its people, and read the target
            Test.startTest();
                AIPoliciesDataStructure.DeleteOptions options = AIPoliciesEditorService.getDeleteOptions(doomed.Id);
                List<AIPoliciesDataStructure.PolicyView> remaining = AIPoliciesEditorService.deletePolicy(doomed.Id, target.Id);
            Test.stopTest();

            // [3] Collect what is left
            Integer doomedCount = [SELECT COUNT() FROM AIUsagePolicy__c WHERE Id = :doomed.Id];
            Integer targetAssignments = [SELECT COUNT() FROM AIUsagePolicyAssignment__c WHERE AIUsagePolicy__c = :target.Id];
            Set<Id> remainingIds = new Set<Id>();

            for (AIPoliciesDataStructure.PolicyView policy : remaining) {

                remainingIds.add(policy.policyId);
            }

            // [4] Check the options, the move and the list
            Assert.areEqual(3, options.assignmentCount, 'The policy has three assignments.');
            Assert.isTrue(options.userCount >= 2, 'The users it covers are counted.');
            Assert.isFalse(options.isDefault, 'The policy is not the default.');
            Assert.isNotNull(options.defaultPolicyId, 'The default policy is offered as a place to move to.');
            Assert.areEqual(0, doomedCount, 'The policy is deleted.');
            Assert.areEqual(3, targetAssignments, 'The second user and the permission set moved, and the duplicate user was dropped.');
            Assert.isTrue(remainingIds.contains(target.Id) && !remainingIds.contains(doomed.Id), 'The list comes back without the deleted policy.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create the default policy, a policy with a person and no other policy to name, and a missing id
            AIPoliciesDataStructure.PolicyView defaultView = AIPoliciesEditorService.savePolicy(null, new Map<String, Object>{'Name' => 'Everyone', 'IsDefault__c' => true});
            AIUsagePolicy__c withPeople = new AIUsagePolicy__c(Name = 'With people', IsActive__c = true);
            insert withPeople;
            insert new AIUsagePolicyAssignment__c(AIUsagePolicy__c = withPeople.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, User__c = superUser.Id, IsActive__c = true);
            Id missingId = AIUsagePolicy__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() + '000000000001AAA';
            String defaultRefusal;
            String noTargetRefusal;
            String sameTargetRefusal;
            String missingRefusal;

            // [2] Try each bad delete
            Test.startTest();
                try {

                    AIPoliciesEditorService.deletePolicy(defaultView.policyId, withPeople.Id);
                } catch (Exception ex) {

                    defaultRefusal = ex.getMessage();
                }

                try {

                    AIPoliciesEditorService.deletePolicy(withPeople.Id, null);
                } catch (Exception ex) {

                    noTargetRefusal = ex.getMessage();
                }

                try {

                    AIPoliciesEditorService.deletePolicy(withPeople.Id, withPeople.Id);
                } catch (Exception ex) {

                    sameTargetRefusal = ex.getMessage();
                }

                try {

                    AIPoliciesEditorService.deletePolicy(missingId, null);
                } catch (Exception ex) {

                    missingRefusal = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check each was refused with its own message
            Assert.areEqual(Label.AI_Policies_Error_Delete_Default, defaultRefusal, 'The default policy cannot be deleted.');
            Assert.areEqual(Label.AI_Policies_Error_Move_To, noTargetRefusal, 'People need somewhere to move to.');
            Assert.areEqual(Label.AI_Policies_Error_Move_To, sameTargetRefusal, 'People cannot move to the policy being deleted.');
            Assert.areEqual(Label.AI_Settings_Error_Row_Not_Found, missingRefusal, 'A policy that is gone is refused.');
            Assert.areEqual(1, [SELECT COUNT() FROM AIUsagePolicy__c WHERE Id = :withPeople.Id], 'The policy is still there.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a policy with no assignments
            AIPoliciesDataStructure.PolicyView created = AIPoliciesEditorService.savePolicy(null, new Map<String, Object>{'Name' => 'Empty'});

            // [2] Delete it without choosing where to move anyone
            Test.startTest();
                AIPoliciesEditorService.deletePolicy(created.policyId, null);
            Test.stopTest();

            // [3] Check it is gone
            Assert.areEqual(0, [SELECT COUNT() FROM AIUsagePolicy__c WHERE Id = :created.policyId], 'The policy is deleted.');
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

                        AIPoliciesEditorService.getPolicies();
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIPoliciesEditorService.savePolicy(null, new Map<String, Object>{'Name' => 'Nope'});
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIPoliciesEditorService.getDeleteOptions(users[0].Id);
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIPoliciesEditorService.deletePolicy(users[0].Id, null);
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

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
