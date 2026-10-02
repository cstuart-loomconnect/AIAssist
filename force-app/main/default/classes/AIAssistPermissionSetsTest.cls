/*
Class Name: AIAssistPermissionSetsTest

=================================================================
=================================================================

Description: Testing utility for the package permission sets: each set lets its holder call the chat controller the chat window uses, so a missing class access is caught here and not by a user.

=================================================================
=================================================================
Applicable Classes:

AIAssistPermissionSets

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAssistPermissionSetsTest {
  // testScenario1: AI Assist User can call the chat controller.
  // testScenario2: AI Assist Super User can call the chat controller.
  // testScenario3: AI Assist Admin can call the chat controller.

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
    String permissionSetName = AIAssistApplicationConstants.PERMISSION_SET_USER;
    String className = 'AIChatController';
    Integer grants = [
      SELECT COUNT()
      FROM SetupEntityAccess
      WHERE
        Parent.Name = :permissionSetName
        AND SetupEntityType = 'ApexClass'
        AND SetupEntityId IN (SELECT Id FROM ApexClass WHERE Name = :className)
    ];

    Test.startTest();
    Integer found = grants;
    Test.stopTest();

    Assert.areEqual(
      1,
      found,
      'The User permission set must list the chat controller, or the window cannot call it.'
    );
  }

  @IsTest
  static void testScenario2() {
    String permissionSetName = AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER;
    String className = 'AIChatController';
    Integer grants = [
      SELECT COUNT()
      FROM SetupEntityAccess
      WHERE
        Parent.Name = :permissionSetName
        AND SetupEntityType = 'ApexClass'
        AND SetupEntityId IN (SELECT Id FROM ApexClass WHERE Name = :className)
    ];

    Test.startTest();
    Integer found = grants;
    Test.stopTest();

    Assert.areEqual(
      1,
      found,
      'The Super User permission set must list the chat controller.'
    );
  }

  @IsTest
  static void testScenario3() {
    String permissionSetName = AIAssistApplicationConstants.PERMISSION_SET_ADMIN_USER;
    String className = 'AIChatController';
    Integer grants = [
      SELECT COUNT()
      FROM SetupEntityAccess
      WHERE
        Parent.Name = :permissionSetName
        AND SetupEntityType = 'ApexClass'
        AND SetupEntityId IN (SELECT Id FROM ApexClass WHERE Name = :className)
    ];

    Test.startTest();
    Integer found = grants;
    Test.stopTest();

    Assert.areEqual(
      1,
      found,
      'The Admin permission set must list the chat controller.'
    );
  }
}
