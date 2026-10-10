/*
Class Name: AIChatTermsServiceTest

=================================================================
=================================================================

Description: Testing utility for AIChatTermsService: accepting the terms.

=================================================================
=================================================================
Applicable Classes:

AIChatTermsService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIChatTermsServiceTest {

    // testScenario1: The terms are accepted -> an acknowledgment of the current version is recorded, signed with the user's name.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Set the current terms version and clear the settings cache
        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.CurrentTermsVersion__c = 'v9';
        update settings;
        AIAssistSettingsService.cachedSettings = null;

        // [2] Acknowledge the terms
        Test.startTest();
            AIChatTermsService.acknowledgeTerms();
        Test.stopTest();

        // [3] Read the saved acknowledgment
        AITermsAcknowledgment__c saved = [SELECT TermsVersion__c, SignatureText__c, User__c FROM AITermsAcknowledgment__c];

        // [4] Check the version, signature and user
        Assert.areEqual('v9', saved.TermsVersion__c, 'The acknowledgment should be for the current terms version.');
        Assert.areEqual(UserInfo.getName().left(120), saved.SignatureText__c, 'The acknowledgment should be signed with the user\'s name.');
        Assert.areEqual(UserInfo.getUserId(), saved.User__c, 'The acknowledgment should be for this user.');
    }
}
