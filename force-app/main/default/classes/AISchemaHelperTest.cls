/*
Class Name: AISchemaHelperTest

=================================================================
=================================================================

Description: Testing utility for AISchemaHelper: object facts for a record, the static cache and the object name list.

=================================================================
=================================================================
Applicable Classes:

AISchemaHelper: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AISchemaHelperTest {
  // testScenario1: Object info for an Account Id -> API name, labels, name field and access are returned.
  // testScenario2: Object info asked for twice, and for a second record of the same object -> the same cached instance is returned.
  // testScenario3: Object info for a null Id -> null is returned.
  // testScenario4: Object info for a user with no access to the package objects -> isAccessible is false.
  // testScenario5: Object name list with blanks, spaces and mixed case -> a lower case set without the blanks.
  // testScenario6: Object name list that is blank or null -> an empty set.

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
    // [1] Create an account
    List<Account> accounts = AIAssistTestDataFactory.createAccounts(1, true);

    // [2] Get the object info for the account Id
    Test.startTest();
    AISchemaHelper.ObjectInfo objectInfo = AISchemaHelper.getObjectInfo(
      accounts[0].Id
    );
    Test.stopTest();

    // [3] Check the names, labels and access come back
    Assert.areEqual(
      'Account',
      objectInfo.apiName,
      'The API name should come from the Id.'
    );
    Assert.areEqual(
      'Account',
      objectInfo.label,
      'The label should be returned.'
    );
    Assert.areEqual(
      'Accounts',
      objectInfo.pluralLabel,
      'The plural label should be returned.'
    );
    Assert.areEqual(
      'Name',
      objectInfo.nameField,
      'The name field should be found.'
    );
    Assert.isTrue(
      objectInfo.isAccessible,
      'The deploying user can read Account.'
    );
  }

  @IsTest
  static void testScenario2() {
    // [1] Create two accounts
    List<Account> accounts = AIAssistTestDataFactory.createAccounts(2, true);

    // [2] Get the object info for each account
    Test.startTest();
    AISchemaHelper.ObjectInfo first = AISchemaHelper.getObjectInfo(
      accounts[0].Id
    );
    AISchemaHelper.ObjectInfo second = AISchemaHelper.getObjectInfo(
      accounts[1].Id
    );
    Test.stopTest();

    // [3] Check the second answer came from the cache
    Assert.areSame(
      first,
      second,
      'The second answer should come from the static cache.'
    );
    Assert.areEqual(
      1,
      AISchemaHelper.infoByLowerName.size(),
      'Only one object should have been described.'
    );
  }

  @IsTest
  static void testScenario3() {
    // [1] Get the object info for a null Id
    Test.startTest();
    AISchemaHelper.ObjectInfo objectInfo = AISchemaHelper.getObjectInfo(null);
    Test.stopTest();

    // [2] Check nothing is returned
    Assert.isNull(objectInfo, 'No Id should give no object info.');
  }

  @IsTest
  static void testScenario4() {
    // [1] Create a user with no access and an agent Id
    User noAccess = AIAssistTestDataFactory.createUsers(1, true)[0];
    Id agentId = Id.valueOf(
      AIAgent__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000'
    );
    AISchemaHelper.ObjectInfo objectInfo;

    System.runAs(noAccess) {
      // [2] Get the object info as that user
      Test.startTest();
      objectInfo = AISchemaHelper.getObjectInfo(agentId);
      Test.stopTest();
    }

    // [3] Check the agent object is not accessible
    Assert.isFalse(
      objectInfo.isAccessible,
      'A user with no permission set cannot read the agent object.'
    );
  }

  @IsTest
  static void testScenario5() {
    // [1] Get the object name set from a messy list
    Test.startTest();
    Set<String> names = AISchemaHelper.getObjectApiNameSet(
      ' Account, ,CONTACT ,'
    );
    Test.stopTest();

    // [2] Check the names are trimmed, lower cased and without blanks
    Assert.areEqual(
      new Set<String>{ 'account', 'contact' },
      names,
      'Names should be trimmed, lower cased and without blanks.'
    );
  }

  @IsTest
  static void testScenario6() {
    // [1] Get the object name set from a blank and a null list
    Test.startTest();
    Set<String> blankNames = AISchemaHelper.getObjectApiNameSet('  ');
    Set<String> nullNames = AISchemaHelper.getObjectApiNameSet(null);
    Test.stopTest();

    // [2] Check both sets are empty
    Assert.isTrue(blankNames.isEmpty(), 'A blank list should be an empty set.');
    Assert.isTrue(nullNames.isEmpty(), 'A null list should be an empty set.');
  }
}
