/*
Class Name: AIAssistSettingsServiceTest

=================================================================
=================================================================

Description: Testing utility for AIAssistSettingsService: the one reader of the application settings, and what it does with a missing, zero or garbled value.

=================================================================
=================================================================
Applicable Classes:

AIAssistSettingsService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAssistSettingsServiceTest {
  // testScenario1: With the settings the TestSetup enabled and no UI settings row, the application is on and the UI settings are the field defaults.
  // testScenario2: Unchecking the switch turns the application off, and a UI settings row replaces the field defaults.
  // testScenario3: With no organisation settings row at all, the field defaults apply instead of every checkbox reading as off.
  // testScenario4: With a settings row, getSettings returns it and caches it for the transaction until clearCache is called.
  // testScenario5: Settings activated in another org read as switched off, as a sandbox copied from production would be; blank and this org's Id do not. activate switches on and records this org, and recordActivatedOrg fills a blank one in.

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
    Test.startTest();
    Boolean isEnabled = AIAssistSettingsService.isEnabled();
    AIAssistUISettings__c uiSettings = AIAssistSettingsService.getUiSettings();
    Test.stopTest();

    Assert.isTrue(isEnabled, 'The application is on when the row enables it.');
    Assert.isTrue(
      uiSettings.IsUserInitiatedChatEnabled__c,
      'With no UI row the default-on switches stay on.'
    );
    Assert.isFalse(
      uiSettings.IsMaintenanceMode__c,
      'With no UI row maintenance mode is off.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.clearCache();

    AIAssistUISettings__c uiRow = AIAssistUISettings__c.getOrgDefaults();
    uiRow.IsMaintenanceMode__c = true;
    uiRow.IsUserInitiatedChatEnabled__c = false;
    upsert uiRow;

    Test.startTest();
    Boolean isEnabled = AIAssistSettingsService.isEnabled();
    AIAssistUISettings__c uiSettings = AIAssistSettingsService.getUiSettings();
    Test.stopTest();

    Assert.isFalse(
      isEnabled,
      'Unchecking IsEnabled__c switches the application off.'
    );
    Assert.isTrue(
      uiSettings.IsMaintenanceMode__c,
      'The organisation UI row is read once it exists.'
    );
    Assert.isFalse(
      uiSettings.IsUserInitiatedChatEnabled__c,
      'And its switches replace the defaults.'
    );
  }

  @IsTest
  static void testScenario3() {
    delete [SELECT Id FROM AIAssistSettings__c];
    AIAssistSettingsService.clearCache();

    Test.startTest();
    AIAssistSettings__c settings = AIAssistSettingsService.getSettings();
    Boolean isEnabled = AIAssistSettingsService.isEnabled();
    Test.stopTest();

    Assert.isNull(
      settings.Id,
      'No row exists, so the settings are the in-memory defaults.'
    );
    Assert.isTrue(
      isEnabled,
      'The IsEnabled__c field default is on, so a missing row must not switch the application off.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.ProcessingLockMinutes__c = 15;
    update settings;
    AIAssistSettingsService.clearCache();

    Test.startTest();
    AIAssistSettings__c first = AIAssistSettingsService.getSettings();
    settings.ProcessingLockMinutes__c = 30;
    update settings;
    AIAssistSettings__c cached = AIAssistSettingsService.getSettings();
    AIAssistSettingsService.clearCache();
    AIAssistSettings__c refreshed = AIAssistSettingsService.getSettings();
    Test.stopTest();

    Assert.isNotNull(first.Id, 'The organisation row is returned.');
    Assert.areEqual(
      15,
      first.ProcessingLockMinutes__c.intValue(),
      'The configured value is read from the row.'
    );
    Assert.areEqual(
      15,
      cached.ProcessingLockMinutes__c.intValue(),
      'The settings are cached for the transaction.'
    );
    Assert.areEqual(
      30,
      refreshed.ProcessingLockMinutes__c.intValue(),
      'Clearing the cache reads the change.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    String otherOrgId = '00D000000000001AAA';

    Test.startTest();
    settings.ActivatedOrgId__c = otherOrgId;
    update settings;
    AIAssistSettingsService.clearCache();
    Boolean isEnabledElsewhere = AIAssistSettingsService.isEnabled();
    Boolean isElsewhere = AIAssistSettingsService.isActivatedElsewhere();
    AIAssistSettingsService.recordActivatedOrg();
    String afterRecordingOverAnother = AIAssistSettings__c.getOrgDefaults()
      .ActivatedOrgId__c;

    settings.ActivatedOrgId__c = null;
    update settings;
    AIAssistSettingsService.clearCache();
    Boolean isEnabledBlank = AIAssistSettingsService.isEnabled();
    AIAssistSettingsService.recordActivatedOrg();
    String afterRecordingBlank = AIAssistSettings__c.getOrgDefaults()
      .ActivatedOrgId__c;
    Boolean isEnabledHere = AIAssistSettingsService.isEnabled();

    settings.ActivatedOrgId__c = otherOrgId;
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.activate();
    Test.stopTest();

    Assert.isTrue(isElsewhere, 'Another org\'s Id.');
    Assert.isFalse(
      isEnabledElsewhere,
      'A mismatched org Id is inactive although the switch is on.'
    );
    Assert.areEqual(
      otherOrgId,
      afterRecordingOverAnother,
      'Another org\'s Id is never overwritten by itself: an administrator activates.'
    );
    Assert.isTrue(isEnabledBlank, 'Blank is not yet recorded, not a mismatch.');
    Assert.areEqual(
      UserInfo.getOrganizationId(),
      afterRecordingBlank,
      'A blank one is filled in with this org.'
    );
    Assert.isTrue(isEnabledHere, 'This org\'s Id is active.');
    Assert.isTrue(AIAssistSettingsService.isEnabled(), 'Activated here.');
    Assert.areEqual(
      UserInfo.getOrganizationId(),
      AIAssistSettings__c.getOrgDefaults().ActivatedOrgId__c,
      'Activation records this org.'
    );
  }
}
