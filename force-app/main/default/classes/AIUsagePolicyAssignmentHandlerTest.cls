/*
Class Name: AIUsagePolicyAssignmentHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIUsagePolicyAssignmentTrigger and AIUsagePolicyAssignmentTriggerHandler: the unique key that stops one policy being assigned to the same user or permission set twice.

=================================================================
=================================================================
Applicable Classes:

AIUsagePolicyAssignmentTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIUsagePolicyAssignmentHandlerTest {
  // testScenario1: A user assignment and a permission set assignment each get a key made of the policy and the assignee.
  // testScenario2: The same user, or the same permission set, cannot be given one policy twice; another policy can have them.
  // testScenario3: An unexpected failure inside the handler is logged and never throws.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  @IsTest
  static void testScenario1() {
    AIUsagePolicy__c policy = AIAssistTestDataFactory.createAIUsagePolicies(
      1,
      true
    )[0];
    List<User> users = AIAssistTestDataFactory.createUsers(1, true);

    Test.startTest();
    AIUsagePolicyAssignment__c userAssignment = AIAssistTestDataFactory.createAIUsagePolicyAssignments(
      policy.Id,
      users,
      null,
      true
    )[0];
    AIUsagePolicyAssignment__c permissionSetAssignment = AIAssistTestDataFactory.createAIUsagePolicyAssignments(
      policy.Id,
      null,
      AIAssistApplicationConstants.PERMISSION_SET_USER,
      true
    )[0];
    Test.stopTest();

    Map<Id, AIUsagePolicyAssignment__c> savedById = new Map<Id, AIUsagePolicyAssignment__c>(
      [SELECT Id, AssignmentKey__c FROM AIUsagePolicyAssignment__c]
    );
    Assert.areEqual(
      policy.Id + '|U:' + users[0].Id,
      savedById.get(userAssignment.Id).AssignmentKey__c,
      'The policy, then the user.'
    );
    Assert.areEqual(
      policy.Id + '|PS:' + AIAssistApplicationConstants.PERMISSION_SET_USER,
      savedById.get(permissionSetAssignment.Id).AssignmentKey__c,
      'The policy, then the permission set by name.'
    );
  }

  @IsTest
  static void testScenario2() {
    List<AIUsagePolicy__c> policies = AIAssistTestDataFactory.createAIUsagePolicies(
      2,
      true
    );
    List<User> users = AIAssistTestDataFactory.createUsers(1, true);
    AIAssistTestDataFactory.createAIUsagePolicyAssignments(
      policies[0].Id,
      users,
      null,
      true
    );
    AIAssistTestDataFactory.createAIUsagePolicyAssignments(
      policies[0].Id,
      null,
      AIAssistApplicationConstants.PERMISSION_SET_USER,
      true
    );

    Test.startTest();
    List<Database.SaveResult> sameUser = Database.insert(
      AIAssistTestDataFactory.createAIUsagePolicyAssignments(
        policies[0].Id,
        users,
        null,
        false
      ),
      false
    );
    List<Database.SaveResult> samePermissionSet = Database.insert(
      AIAssistTestDataFactory.createAIUsagePolicyAssignments(
        policies[0].Id,
        null,
        AIAssistApplicationConstants.PERMISSION_SET_USER,
        false
      ),
      false
    );
    List<Database.SaveResult> otherPolicy = Database.insert(
      AIAssistTestDataFactory.createAIUsagePolicyAssignments(
        policies[1].Id,
        users,
        null,
        false
      ),
      false
    );
    Test.stopTest();

    Assert.isFalse(sameUser[0].isSuccess(), 'The same user twice is refused.');
    Assert.isFalse(
      samePermissionSet[0].isSuccess(),
      'The same permission set twice is refused.'
    );
    Assert.isTrue(
      otherPolicy[0].isSuccess(),
      'Another policy can have the user.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIUsagePolicy__c policy = AIAssistTestDataFactory.createAIUsagePolicies(
      1,
      true
    )[0];
    List<User> users = AIAssistTestDataFactory.createUsers(1, true);
    AIUsagePolicyAssignmentTriggerHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    List<AIUsagePolicyAssignment__c> assignments = AIAssistTestDataFactory.createAIUsagePolicyAssignments(
      policy.Id,
      users,
      null,
      true
    );
    Test.stopTest();

    Assert.isNotNull(
      assignments[0].Id,
      'The save went through; the failure was logged.'
    );
  }
}
