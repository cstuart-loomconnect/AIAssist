/*
Class Name: AIAssistUserTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for the AI Assist User trigger and handler: the AIUserSettings__c row created, reactivated or deactivated as users are created and their active flag changes.

=================================================================
=================================================================
Applicable Classes:

AIAssistUserTrigger: Coverage TBC
AIAssistUserTriggerHandler: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIAssistUserTriggerHandlerTest {

    // testScenario1: Inserting an active User -> one active AIUserSettings__c with the default values is created for them.
    // testScenario2: Inserting an inactive User -> no AIUserSettings__c is created.
    // testScenario3: Inserting several active Users -> each gets one AIUserSettings__c.
    // testScenario4: Reactivating a User who has no AIUserSettings__c -> default settings are created.
    // testScenario5: Reactivating a User who has an inactive AIUserSettings__c -> the same row is made active and no second row is created.
    // testScenario6: Deactivating a User who has an active AIUserSettings__c -> the row is kept and made inactive.
    // testScenario7: Updating a User without changing the active flag -> no AIUserSettings__c is created or changed.
    // testScenario8: Calling the handler with null or empty input -> nothing is started and nothing is logged.
    // testScenario9: When isTestCustomExceptionThrown forces an exception -> it is logged once and no settings are created.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Build one active user
        User user = AIAssistTestDataFactory.createUsers(1, false)[0];

        // [2] Insert the user so the trigger runs
        Test.startTest();
            System.runAs(new User(Id = UserInfo.getUserId())) { insert user; }
        Test.stopTest();

        // [3] Read the settings created for the user
        List<AIUserSettings__c> settingsRows = [SELECT IsActive__c, DebugModeEnabled__c, UsageLimitReachedBehavior__c, ConversationVisibilityScope__c FROM AIUserSettings__c WHERE User__c = :user.Id];

        // [4] Check one active row with the default values was created
        Assert.areEqual(1, settingsRows.size(), 'One settings row should be created for the new user.');
        Assert.areEqual(true, settingsRows[0].IsActive__c, 'The new settings should be active.');
        Assert.areEqual(false, settingsRows[0].DebugModeEnabled__c, 'The new settings should carry the default values.');
        Assert.areEqual(AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY, settingsRows[0].UsageLimitReachedBehavior__c, 'The new settings should carry the default usage limit behaviour.');
        Assert.areEqual(AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN, settingsRows[0].ConversationVisibilityScope__c, 'The new settings should carry the default visibility scope.');
    }

    @IsTest static void testScenario2() {

        // [1] Build one inactive user
        User user = AIAssistTestDataFactory.createUsers(1, false)[0];
        user.IsActive = false;

        // [2] Insert the user so the trigger runs
        Test.startTest();
            System.runAs(new User(Id = UserInfo.getUserId())) { insert user; }
        Test.stopTest();

        // [3] Count the settings for the user
        Integer settingsCount = [SELECT COUNT() FROM AIUserSettings__c WHERE User__c = :user.Id];

        // [4] Check nothing was created
        Assert.areEqual(0, settingsCount, 'No settings should be created for an inactive user.');
    }

    @IsTest static void testScenario3() {

        // [1] Build three active users
        List<User> users = AIAssistTestDataFactory.createUsers(3, false);

        // [2] Insert the users so the trigger runs once for all of them
        Test.startTest();
            System.runAs(new User(Id = UserInfo.getUserId())) { insert users; }
        Test.stopTest();

        // [3] Count the settings created for these users
        Integer settingsCount = [SELECT COUNT() FROM AIUserSettings__c WHERE User__c IN :users];

        // [4] Check each user got one row
        Assert.areEqual(3, settingsCount, 'Each of the three users should get one settings row.');
    }

    @IsTest static void testScenario4() {

        // [1] Create an inactive user with no settings
        User user = AIAssistTestDataFactory.createUsers(1, false)[0];
        user.IsActive = false;
        System.runAs(new User(Id = UserInfo.getUserId())) { insert user; }

        // [2] Reactivate the user
        Test.startTest();
            System.runAs(new User(Id = UserInfo.getUserId())) { update new User(Id = user.Id, IsActive = true); }
        Test.stopTest();

        // [3] Read the settings for the user
        List<AIUserSettings__c> settingsRows = [SELECT IsActive__c FROM AIUserSettings__c WHERE User__c = :user.Id];

        // [4] Check one active row was created
        Assert.areEqual(1, settingsRows.size(), 'Reactivating a user with no settings should create one settings row.');
        Assert.areEqual(true, settingsRows[0].IsActive__c, 'The created settings should be active.');
    }

    @IsTest static void testScenario5() {

        // [1] Create an inactive user with inactive settings
        User user = AIAssistTestDataFactory.createUsers(1, false)[0];
        user.IsActive = false;
        System.runAs(new User(Id = UserInfo.getUserId())) { insert user; }
        AIUserSettings__c existingSettings = AIAssistTestDataFactory.createAIUserSettings(user.Id, false)[0];
        existingSettings.IsActive__c = false;
        insert existingSettings;

        // [2] Reactivate the user
        Test.startTest();
            System.runAs(new User(Id = UserInfo.getUserId())) { update new User(Id = user.Id, IsActive = true); }
        Test.stopTest();

        // [3] Read the settings for the user
        List<AIUserSettings__c> settingsRows = [SELECT Id, IsActive__c FROM AIUserSettings__c WHERE User__c = :user.Id];

        // [4] Check the same row is now active and there is still only one
        Assert.areEqual(1, settingsRows.size(), 'No second settings row should be created.');
        Assert.areEqual(existingSettings.Id, settingsRows[0].Id, 'The existing settings row should be the one reactivated.');
        Assert.areEqual(true, settingsRows[0].IsActive__c, 'The existing settings should be made active.');
    }

    @IsTest static void testScenario6() {

        // [1] Create an active user with active settings
        User user = AIAssistTestDataFactory.createUsers(1, true)[0];
        AIUserSettings__c existingSettings = AIAssistTestDataFactory.createAIUserSettings(user.Id, true)[0];

        // [2] Deactivate the user
        Test.startTest();
            System.runAs(new User(Id = UserInfo.getUserId())) { update new User(Id = user.Id, IsActive = false); }
        Test.stopTest();

        // [3] Read the settings for the user
        List<AIUserSettings__c> settingsRows = [SELECT Id, IsActive__c FROM AIUserSettings__c WHERE User__c = :user.Id];

        // [4] Check the row was kept and made inactive
        Assert.areEqual(1, settingsRows.size(), 'The settings row should be kept when the user is deactivated.');
        Assert.areEqual(existingSettings.Id, settingsRows[0].Id, 'The same settings row should be kept.');
        Assert.areEqual(false, settingsRows[0].IsActive__c, 'The settings should be made inactive.');
    }

    @IsTest static void testScenario7() {

        // [1] Create an inactive user with no settings
        User user = AIAssistTestDataFactory.createUsers(1, false)[0];
        user.IsActive = false;
        System.runAs(new User(Id = UserInfo.getUserId())) { insert user; }

        // [2] Change the user's name only
        Test.startTest();
            System.runAs(new User(Id = UserInfo.getUserId())) { update new User(Id = user.Id, LastName = 'Renamed Tester'); }
        Test.stopTest();

        // [3] Count the settings for the user
        Integer settingsCount = [SELECT COUNT() FROM AIUserSettings__c WHERE User__c = :user.Id];

        // [4] Check nothing was created
        Assert.areEqual(0, settingsCount, 'Changing something other than the active flag should not create settings.');
    }

    @IsTest static void testScenario8() {

        // [1] Call the handler with missing and empty input
        Test.startTest();
            AIAssistUserTriggerHandler.handleAfterInsert(null);
            AIAssistUserTriggerHandler.handleAfterInsert(new Map<Id, User>());
            AIAssistUserTriggerHandler.handleAfterUpdate(null, null);
            AIAssistUserTriggerHandler.handleAfterUpdate(new Map<Id, User>(), new Map<Id, User>());
        Test.stopTest();

        // [2] Count the jobs started and the logs written
        Integer jobCount = [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'AIAssistUserTriggerHandler'];
        Integer platformLogCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIAssistUserTriggerHandler'];

        // [3] Check nothing started and nothing was logged
        Assert.areEqual(0, jobCount, 'No job should be started without users.');
        Assert.areEqual(0, platformLogCount, 'Missing or empty input should not be logged as a failure.');
    }

    @IsTest static void testScenario9() {

        // [1] Force the handler to throw
        AIAssistUserTriggerHandler.isTestCustomExceptionThrown = true;
        User user = AIAssistTestDataFactory.createUsers(1, false)[0];

        // [2] Insert the user so the trigger runs
        Test.startTest();
            System.runAs(new User(Id = UserInfo.getUserId())) { insert user; }
        Test.stopTest();

        // [3] Count the settings and the matching platform logs
        Integer settingsCount = [SELECT COUNT() FROM AIUserSettings__c WHERE User__c = :user.Id];
        Integer platformLogCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIAssistUserTriggerHandler' AND MethodName__c = 'handleAfterInsert'];

        // [4] Check the user was still saved, no settings were created and the failure was logged
        Assert.areEqual(1, [SELECT COUNT() FROM User WHERE Id = :user.Id], 'The user should still be saved when the handler throws.');
        Assert.areEqual(0, settingsCount, 'No settings should be created when the handler throws.');
        Assert.areEqual(1, platformLogCount, 'The forced exception should be logged to AIPlatformLog__c.');
    }
}
