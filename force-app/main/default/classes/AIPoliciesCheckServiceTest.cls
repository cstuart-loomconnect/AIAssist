/*
Class Name: AIPoliciesCheckServiceTest

=================================================================
=================================================================

Description: Testing utility for AIPoliciesCheckService: which policy a user gets, and the line that explains each policy that could apply.

=================================================================
=================================================================
Applicable Classes:

AIPoliciesCheckService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPoliciesCheckServiceTest {

    // testScenario1: A user has a user assignment and a permission set assignment -> the user assignment wins, the permission set is ignored and the default is not needed.
    // testScenario2: A user holds two permission sets with different policies -> the stricter policy wins, the other is ignored, and a hint offers it as a user assignment.
    // testScenario3: A user holds one permission set that has a policy -> that policy wins with no hint.
    // testScenario4: A user has nothing assigned -> the default policy applies.
    // testScenario5: Every policy is switched off -> no policy applies and the reason says so.
    // testScenario6: A user that is gone, and a user without the Manage Settings permission -> each is refused.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two policies, a user holding a permission set, and assign the user and the permission set
            AIUsagePolicy__c userPolicy = new AIUsagePolicy__c(Name = 'Exception', IsActive__c = true, MaxTokensPer24Hours__c = 900000, MaxConversationsPer24Hours__c = 90);
            AIUsagePolicy__c setPolicy = new AIUsagePolicy__c(Name = 'Team', IsActive__c = true, MaxTokensPer24Hours__c = 100000);
            insert new List<AIUsagePolicy__c>{userPolicy, setPolicy};
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            insert new List<AIUsagePolicyAssignment__c>{
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = userPolicy.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, User__c = users[0].Id, IsActive__c = true),
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = setPolicy.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, PermissionSetName__c = 'AIAssistUser', IsActive__c = true)
            };

            // [2] Check the user
            Test.startTest();
                AIPoliciesDataStructure.UserCheck check = AIPoliciesCheckService.checkUser(users[0].Id);
            Test.stopTest();

            // [3] Check the winner and each line
            Assert.areEqual(userPolicy.Id, check.policyId, 'The user assignment wins.');
            Assert.areEqual(Label.AI_Policies_Check_Reason_User, check.reason, 'The reason names the user assignment.');
            Assert.areEqual(3, check.sources.size(), 'The user assignment, the permission set and the default are listed.');
            Assert.areEqual(AIAssistApplicationConstants.POLICY_OUTCOME_WINS, check.sources[0].outcome, 'The user assignment wins.');
            Assert.areEqual(900000, check.sources[0].maxTokensPer24Hours, 'The limits are shown.');
            Assert.areEqual(AIAssistApplicationConstants.POLICY_OUTCOME_IGNORED, check.sources[1].outcome, 'The permission set is ignored.');
            Assert.areEqual(AIAssistApplicationConstants.POLICY_OUTCOME_NOT_NEEDED, check.sources[2].outcome, 'The default is not needed.');
            Assert.isNull(check.hintText, 'A user assignment needs no hint.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a loose and a strict policy, a user holding two permission sets, and assign one set to each policy
            AIUsagePolicy__c loose = new AIUsagePolicy__c(Name = 'Team leaders', IsActive__c = true, MaxTokensPer24Hours__c = 500000);
            AIUsagePolicy__c strict = new AIUsagePolicy__c(Name = 'Advisers default', IsActive__c = true, MaxTokensPer24Hours__c = 200000);
            insert new List<AIUsagePolicy__c>{loose, strict};
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistAdminUser');
            insert new List<AIUsagePolicyAssignment__c>{
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = loose.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, PermissionSetName__c = 'AIAssistAdminUser', IsActive__c = true),
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = strict.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, PermissionSetName__c = 'AIAssistUser', IsActive__c = true)
            };

            // [2] Check the user
            Test.startTest();
                AIPoliciesDataStructure.UserCheck check = AIPoliciesCheckService.checkUser(users[0].Id);
            Test.stopTest();

            // [3] Check the winner, the ignored policy and the hint
            Assert.areEqual(strict.Id, check.policyId, 'The stricter policy wins.');
            Assert.areEqual(String.format(Label.AI_Policies_Check_Reason_Permission_Set_Several, new List<String>{'2'}), check.reason, 'The reason says two permission sets clash.');
            Assert.areEqual(loose.Id, check.ignoredPolicyId, 'The looser policy is ignored.');
            Assert.areEqual('Team leaders', check.ignoredPolicyName, 'The ignored policy is named.');
            Assert.isTrue(check.hintText.contains('Team leaders') && check.hintText.contains(check.sources[1].sourceLabel), 'The hint names the ignored policy and the assignment that wins.');
            Assert.isTrue(check.sources[0].sourceLabel.startsWith('Permission set'), 'A permission set line names its source.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a policy, a user holding a permission set and the assignment
            AIUsagePolicy__c policy = new AIUsagePolicy__c(Name = 'Team', IsActive__c = true);
            insert policy;
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            insert new AIUsagePolicyAssignment__c(AIUsagePolicy__c = policy.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, PermissionSetName__c = 'AIAssistUser', IsActive__c = true);

            // [2] Check the user
            Test.startTest();
                AIPoliciesDataStructure.UserCheck check = AIPoliciesCheckService.checkUser(users[0].Id);
            Test.stopTest();

            // [3] Check the policy and that no hint is needed
            Assert.areEqual(policy.Id, check.policyId, 'The permission set policy applies.');
            Assert.areEqual(Label.AI_Policies_Check_Reason_Permission_Set, check.reason, 'The reason names the permission set.');
            Assert.isNull(check.hintText, 'Nothing was ignored.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user with nothing assigned
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);

            // [2] Check the user
            Test.startTest();
                AIPoliciesDataStructure.UserCheck check = AIPoliciesCheckService.checkUser(users[0].Id);
            Test.stopTest();

            // [3] Check the default applies
            Assert.isNotNull(check.policyId, 'The default policy applies.');
            Assert.areEqual(Label.AI_Policies_Check_Reason_Default, check.reason, 'The reason names the default.');
            Assert.areEqual(1, check.sources.size(), 'Only the default is listed.');
            Assert.areEqual(AIAssistApplicationConstants.POLICY_OUTCOME_APPLIES, check.sources[0].outcome, 'The default applies.');
            Assert.areEqual(Label.AI_Policies_Source_Default, check.sources[0].sourceLabel, 'The source is the default.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user and switch every policy off
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.deactivateUsagePolicies();

            // [2] Check the user
            Test.startTest();
                AIPoliciesDataStructure.UserCheck check = AIPoliciesCheckService.checkUser(users[0].Id);
            Test.stopTest();

            // [3] Check no policy applies
            Assert.isNull(check.policyId, 'No policy applies.');
            Assert.areEqual(Label.AI_Policies_Check_Reason_None, check.reason, 'The reason says so.');
            Assert.isTrue(check.sources.isEmpty(), 'Nothing is listed.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            Id missingId = User.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
            String missingRefusal;
            String accessRefusal;

            // [2] Check a user that is gone, then check as the end user
            Test.startTest();
                try {

                    AIPoliciesCheckService.checkUser(missingId);
                } catch (Exception ex) {

                    missingRefusal = ex.getMessage();
                }

                System.runAs(users[0]) {
                    try {

                        AIPoliciesCheckService.checkUser(users[0].Id);
                    } catch (Exception ex) {

                        accessRefusal = ex.getMessage();
                    }
                }
            Test.stopTest();

            // [3] Check each refusal
            Assert.areEqual(Label.AI_Settings_Error_Row_Not_Found, missingRefusal, 'A user that is gone is refused.');
            Assert.areEqual(Label.AI_Settings_Error_Access, accessRefusal, 'A user without the permission is refused.');
        }
    }
}
