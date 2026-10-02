/*
Class Name: AIUserSettingsTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIUserSettingsTrigger and AIUserSettingsTriggerHandler: the unique key that stops one user having two settings records.

=================================================================
=================================================================
Applicable Classes:

AIUserSettingsTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIUserSettingsTriggerHandlerTest {
  // testScenario1: A new settings record gets its user's Id as its key.
  // testScenario2: A second settings record for the same user is refused; another user's is not.
  // testScenario3: A key typed in by hand is replaced, on insert and on update.
  // testScenario4: An unexpected failure inside the handler is logged and never throws.

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
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

    Test.startTest();
    AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      true
    )[0];
    Test.stopTest();

    Assert.areEqual(
      String.valueOf(chatUser.Id),
      [SELECT UserKey__c FROM AIUserSettings__c WHERE Id = :settings.Id]
      .UserKey__c,
      'The user the settings belong to.'
    );
  }

  @IsTest
  static void testScenario2() {
    List<User> users = AIAssistTestDataFactory.createUsers(2, true);
    AIAssistTestDataFactory.createAIUserSettings(users[0].Id, true);
    AIUserSettings__c duplicate = AIAssistTestDataFactory.createAIUserSettings(
      users[0].Id,
      false
    )[0];
    duplicate.IsActive__c = false;

    Test.startTest();
    Database.SaveResult duplicateResult = Database.insert(duplicate, false);
    Database.SaveResult otherUserResult = Database.insert(
      AIAssistTestDataFactory.createAIUserSettings(users[1].Id, false)[0],
      false
    );
    Test.stopTest();

    Assert.isFalse(duplicateResult.isSuccess(), 'Refused as a duplicate.');
    Assert.areEqual(
      StatusCode.DUPLICATE_VALUE,
      duplicateResult.getErrors()[0].getStatusCode(),
      'By the unique key.'
    );
    Assert.isTrue(otherUserResult.isSuccess(), 'Another user is fine.');
  }

  @IsTest
  static void testScenario3() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      false
    )[0];
    settings.UserKey__c = 'typed-in';

    Test.startTest();
    insert settings;
    String keyAfterInsert = [
      SELECT UserKey__c
      FROM AIUserSettings__c
      WHERE Id = :settings.Id
    ]
    .UserKey__c;
    settings.UserKey__c = 'typed-again';
    settings.DebugModeEnabled__c = true;
    update settings;
    Test.stopTest();

    Assert.areEqual(
      String.valueOf(chatUser.Id),
      keyAfterInsert,
      'Replaced on insert.'
    );
    Assert.areEqual(
      keyAfterInsert,
      [SELECT UserKey__c FROM AIUserSettings__c WHERE Id = :settings.Id]
      .UserKey__c,
      'And on update.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIUserSettingsTriggerHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    try {
      AIUserSettingsTriggerHandler.handleBeforeInsert(
        new List<AIUserSettings__c>{ new AIUserSettings__c() }
      );
      AIUserSettingsTriggerHandler.handleBeforeUpdate(null);
    } catch (Exception ex) {
      Assert.fail('The handler must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM AIPlatformLog__c
        WHERE ClassName__c = 'AIUserSettingsTriggerHandler'
      ],
      'Logged once for each call.'
    );
  }
}
