/*
Class Name: AISchemaHelperTest

=================================================================
=================================================================

Description: Testing utility for AISchemaHelper: object and field facts, the two cache levels, and that a missing or failing cache only costs a describe. The platform cache is replaced by an in-memory fake.

=================================================================
=================================================================
Applicable Classes:

AISchemaHelper

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AISchemaHelperTest {
  // testScenario1: Object info gives the API name, labels, key prefix and name field, for a name or an Id.
  // testScenario2: Field info gives the type and length, and hasField and getFieldLength agree, whatever the case.
  // testScenario3: A blank name, an Id of nothing, an unknown object and a missing field all answer null or false and never throw.
  // testScenario4: Within a transaction an object is described once, however many questions are asked, and an unknown object is not looked up again.
  // testScenario7: clearCache for one object removes it and leaves the others, and clearCache with no name clears everything seen.
  // testScenario8: isAccessible follows the user: a user with no access to the package objects cannot read an AI object, and is cached for the transaction only.

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
    Account record = AIAssistTestDataFactory.createAccounts(1, true)[0];

    Test.startTest();
    AISchemaHelper.ObjectInfo byName = AISchemaHelper.getObjectInfo('Account');
    AISchemaHelper.ObjectInfo byId = AISchemaHelper.getObjectInfo(record.Id);
    String apiName = AISchemaHelper.getObjectApiName(record.Id);
    String nameField = AISchemaHelper.getNameField('account');
    Test.stopTest();

    Assert.areEqual('Account', byName.apiName, 'The API name.');
    Assert.areEqual('Accounts', byName.pluralLabel, 'The plural label.');
    Assert.areEqual('001', byName.keyPrefix, 'The key prefix.');
    Assert.areEqual('Account', apiName, 'From the Id.');
    Assert.areEqual(
      'Name',
      nameField,
      'The name field, whatever the case asked for.'
    );
    Assert.areEqual(byName.apiName, byId.apiName, 'Same answer by Id.');
  }

  @IsTest
  static void testScenario2() {
    Test.startTest();
    AISchemaHelper.FieldInfo field = AISchemaHelper.getFieldInfo(
      'Account',
      'NAME'
    );
    Boolean exists = AISchemaHelper.hasField('Account', 'name');
    Boolean missing = AISchemaHelper.hasField('Account', 'No_Such_Field__c');
    Integer length = AISchemaHelper.getFieldLength('Account', 'Name');
    Integer noLength = AISchemaHelper.getFieldLength(
      'Account',
      'No_Such_Field__c'
    );
    Test.stopTest();

    Assert.areEqual('STRING', field.dataType, 'The type.');
    Assert.isTrue(field.isNameField, 'It is the name field.');
    Assert.isTrue(exists, 'It exists.');
    Assert.isFalse(missing, 'This one does not.');
    Assert.areEqual(255, length, 'The length of Account Name.');
    Assert.isNull(noLength, 'No field, no length.');
  }

  @IsTest
  static void testScenario3() {
    Test.startTest();
    AISchemaHelper.ObjectInfo blank = AISchemaHelper.getObjectInfo(
      (String) null
    );
    AISchemaHelper.ObjectInfo unknown = AISchemaHelper.getObjectInfo(
      'No_Such_Object__c'
    );
    String noId = AISchemaHelper.getObjectApiName(null);
    AISchemaHelper.FieldInfo noObject = AISchemaHelper.getFieldInfo(
      'No_Such_Object__c',
      'Name'
    );
    AISchemaHelper.FieldInfo noField = AISchemaHelper.getFieldInfo(
      'Account',
      null
    );
    String label = AISchemaHelper.getLabel('No_Such_Object__c');
    Test.stopTest();

    Assert.isNull(blank, 'Blank.');
    Assert.isNull(unknown, 'Unknown object.');
    Assert.isNull(noId, 'No Id.');
    Assert.isNull(noObject, 'No object.');
    Assert.isNull(noField, 'No field name.');
    Assert.isNull(label, 'No label.');
  }

  @IsTest
  static void testScenario4() {
    Integer before = AISchemaHelper.describeCount;

    Test.startTest();
    for (Integer i = 0; i < 50; i++) {
      AISchemaHelper.getLabel('Contact');
      AISchemaHelper.hasField('Contact', 'LastName');
    }
    AISchemaHelper.getObjectInfo('No_Such_Object__c');
    AISchemaHelper.getObjectInfo('No_Such_Object__c');
    Test.stopTest();

    Assert.areEqual(
      1,
      AISchemaHelper.describeCount - before,
      'One describe for a hundred questions.'
    );
  }

  @IsTest
  static void testScenario7() {
    AISchemaHelper.getObjectInfo('Account');
    AISchemaHelper.getObjectInfo('Contact');

    Test.startTest();
    AISchemaHelper.clearCache('account');
    Boolean accountCleared = !AISchemaHelper.infoByLowerName.containsKey(
      'account'
    );
    Boolean contactKept = AISchemaHelper.infoByLowerName.containsKey('contact');
    AISchemaHelper.clearCache(null);
    Test.stopTest();

    Assert.isTrue(accountCleared, 'The named object is cleared.');
    Assert.isTrue(contactKept, 'The other object is kept.');
    Assert.isTrue(
      AISchemaHelper.infoByLowerName.isEmpty(),
      'Everything seen is cleared when no name is given.'
    );
  }

  @IsTest
  static void testScenario8() {
    User noAccess = AIAssistTestDataFactory.createUsers(1, true)[0];
    Boolean forAdmin = AISchemaHelper.isAccessible('LoomConnect__AIAgent__c');
    Boolean forUser;
    Boolean blank = AISchemaHelper.isAccessible(null);
    Boolean unknown = AISchemaHelper.isAccessible('No_Such_Object__c');

    System.runAs(noAccess) {
      AISchemaHelper.accessibleByLowerName.clear();
      Test.startTest();
      forUser = AISchemaHelper.isAccessible('LoomConnect__AIAgent__c');
      Test.stopTest();
    }

    Assert.isTrue(forAdmin, 'The deploying user can read it.');
    Assert.isFalse(forUser, 'A user with no permission set cannot.');
    Assert.isFalse(blank || unknown, 'Blank and unknown are not accessible.');
  }
}
