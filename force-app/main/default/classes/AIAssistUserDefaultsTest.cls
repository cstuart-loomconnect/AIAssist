/*
Class Name: AIAssistUserDefaultsTest

=================================================================
=================================================================

Description: Testing utility for AIAssistUserDefaults: the default AIUserSettings__c record built for a User.

=================================================================
=================================================================
Applicable Classes:

AIAssistUserDefaults: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIAssistUserDefaultsTest {

    // testScenario1: Building the defaults for a User -> the record holds the seeded default values.
    // testScenario2: Building the defaults for a User -> the record is linked to that User and is not saved.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Create a user to build the defaults for
        User user = AIAssistTestDataFactory.createUsers(1, true)[0];

        // [2] Build the defaults
        Test.startTest();
            AIUserSettings__c settings = AIAssistUserDefaults.build(user);
        Test.stopTest();

        // [3] Check each default value
        Assert.areEqual(true, settings.IsActive__c, 'IsActive__c should default to true.');
        Assert.areEqual(false, settings.DebugModeEnabled__c, 'DebugModeEnabled__c should default to false.');
        Assert.areEqual(false, settings.WorkflowActionsEnabled__c, 'WorkflowActionsEnabled__c should default to false.');
        Assert.areEqual(false, settings.ConversationExportEnabled__c, 'ConversationExportEnabled__c should default to false.');
        Assert.isNull(settings.MaxTokensPer24Hours__c, 'MaxTokensPer24Hours__c should default to no limit.');
        Assert.isNull(settings.MaxConcurrentConversations__c, 'MaxConcurrentConversations__c should default to no limit.');
        Assert.isNull(settings.MaxConversationsPer24Hours__c, 'MaxConversationsPer24Hours__c should default to no limit.');
        Assert.areEqual(AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY, settings.UsageLimitReachedBehavior__c, 'UsageLimitReachedBehavior__c should default to blocking new conversations only.');
        Assert.areEqual(AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN, settings.ConversationVisibilityScope__c, 'ConversationVisibilityScope__c should default to the user\'s own conversations.');
        Assert.areEqual(AIAssistApplicationConstants.CHANNEL_RECORD_PAGE_CHAT + AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR + AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, settings.AllowedChannels__c, 'AllowedChannels__c should default to Record Page Chat and Utility Bar.');
    }

    @IsTest static void testScenario2() {

        // [1] Create an inactive user, so the User trigger creates no settings of its own
        User user = AIAssistTestDataFactory.createUsers(1, false)[0];
        user.IsActive = false;
        System.runAs(new User(Id = UserInfo.getUserId())) { insert user; }

        // [2] Build the defaults
        Test.startTest();
            AIUserSettings__c settings = AIAssistUserDefaults.build(user);
        Test.stopTest();

        // [3] Count the saved settings for the user
        Integer savedSettingsCount = [SELECT COUNT() FROM AIUserSettings__c WHERE User__c = :user.Id];

        // [4] Check the record is linked to the user and was not saved
        Assert.areEqual(user.Id, settings.User__c, 'The settings should be linked to the user they were built for.');
        Assert.areEqual(0, savedSettingsCount, 'Building the defaults should not save anything.');
    }
}
