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
  // testScenario1: With the settings the TestSetup enabled and no UI settings row, the application and both logging switches are on and the UI settings are the field defaults.
  // testScenario2: Unchecking the three switches turns the application and both kinds of logging off, and a UI settings row replaces the field defaults.
  // testScenario3: With no organisation settings row at all, the field defaults apply instead of every checkbox reading as off.
  // testScenario4: Configured values are parsed and returned: success and retry status codes (skipping blanks and non-numbers), the callout timeout, and the tool-calling and lock limits, where a zero or negative limit falls back to its default.
  // testScenario5: Blank or garbled values fall back safely: success codes to 200, retry codes to none, blank limits to their defaults, and a blank callout timeout throws rather than guessing.

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
    Boolean isExceptionLoggingEnabled = AIAssistSettingsService.isExceptionLoggingEnabled();
    Boolean isPlatformLoggingEnabled = AIAssistSettingsService.isPlatformLoggingEnabled();
    AIAssistUISettings__c uiSettings = AIAssistSettingsService.getUiSettings();
    Test.stopTest();

    Assert.isTrue(isEnabled, 'The application is on when the row enables it.');
    Assert.isTrue(isExceptionLoggingEnabled, 'Exception logging is on.');
    Assert.isTrue(isPlatformLoggingEnabled, 'Platform logging is on.');
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
    settings.IsExceptionLoggingEnabled__c = false;
    settings.IsPlatformLoggingEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;

    AIAssistUISettings__c uiRow = AIAssistUISettings__c.getOrgDefaults();
    uiRow.IsMaintenanceMode__c = true;
    uiRow.IsUserInitiatedChatEnabled__c = false;
    upsert uiRow;

    Test.startTest();
    Boolean isEnabled = AIAssistSettingsService.isEnabled();
    Boolean isExceptionLoggingEnabled = AIAssistSettingsService.isExceptionLoggingEnabled();
    Boolean isPlatformLoggingEnabled = AIAssistSettingsService.isPlatformLoggingEnabled();
    AIAssistUISettings__c uiSettings = AIAssistSettingsService.getUiSettings();
    Test.stopTest();

    Assert.isFalse(
      isEnabled,
      'Unchecking IsEnabled__c switches the application off.'
    );
    Assert.isFalse(
      isExceptionLoggingEnabled,
      'Unchecking the exception switch stops events being published.'
    );
    Assert.isFalse(
      isPlatformLoggingEnabled,
      'Unchecking the platform switch stops events being saved.'
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
    AIAssistSettingsService.cachedSettings = null;

    Test.startTest();
    AIAssistSettings__c settings = AIAssistSettingsService.getSettings();
    Boolean isEnabled = AIAssistSettingsService.isEnabled();
    Integer lockMinutes = AIAssistSettingsService.getProcessingLockMinutes();
    Test.stopTest();

    Assert.isNull(
      settings.Id,
      'No row exists, so the settings are the in-memory defaults.'
    );
    Assert.isTrue(
      isEnabled,
      'The IsEnabled__c field default is on, so a missing row must not switch the application off.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.DEFAULT_PROCESSING_LOCK_MINUTES,
      lockMinutes,
      'The lock time falls back to its default.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.AIProviderSuccessStatusCodes__c = '200, 201,abc,, 202 ';
    settings.RetryableStatusCodes__c = '429,503, x';
    settings.CalloutTimeoutMilliseconds__c = 45000;
    settings.DefaultMaxToolCallingIterations__c = 7;
    settings.MaxToolCallingIterationsCap__c = 0;
    settings.MaxToolCallsPerIteration__c = -2;
    settings.ProcessingLockMinutes__c = 15;
    update settings;
    AIAssistSettingsService.cachedSettings = null;

    Test.startTest();
    Set<Integer> successCodes = AIAssistSettingsService.getSuccessStatusCodes();
    Set<Integer> retryCodes = AIAssistSettingsService.getRetryStatusCodes();
    Integer timeout = AIAssistSettingsService.getCalloutTimeoutMilliseconds();
    Integer iterations = AIAssistSettingsService.getDefaultMaxToolCallingIterations();
    Integer iterationCap = AIAssistSettingsService.getMaxToolCallingIterationsCap();
    Integer callsPerIteration = AIAssistSettingsService.getMaxToolCallsPerIteration();
    Integer lockMinutes = AIAssistSettingsService.getProcessingLockMinutes();
    Test.stopTest();

    Assert.areEqual(
      new Set<Integer>{ 200, 201, 202 },
      successCodes,
      'Numbers are kept; blanks and words are skipped.'
    );
    Assert.areEqual(
      new Set<Integer>{ 429, 503 },
      retryCodes,
      'Retry codes are parsed the same way.'
    );
    Assert.areEqual(45000, timeout, 'The configured timeout is returned.');
    Assert.areEqual(7, iterations, 'A configured default is returned.');
    Assert.areEqual(
      AIAssistApplicationConstants.DEFAULT_MAX_TOOL_CALLING_ITERATIONS_CAP,
      iterationCap,
      'A zero cap falls back to the default.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.DEFAULT_MAX_TOOL_CALLS_PER_ITERATION,
      callsPerIteration,
      'A negative limit falls back to the default.'
    );
    Assert.areEqual(15, lockMinutes, 'A configured lock time is returned.');
  }

  @IsTest
  static void testScenario5() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.AIProviderSuccessStatusCodes__c = 'none, x';
    settings.RetryableStatusCodes__c = '';
    settings.CalloutTimeoutMilliseconds__c = null;
    settings.DefaultMaxToolCallingIterations__c = null;
    settings.ProcessingLockMinutes__c = null;
    update settings;
    AIAssistSettingsService.cachedSettings = null;

    Test.startTest();
    Set<Integer> successCodes = AIAssistSettingsService.getSuccessStatusCodes();
    Set<Integer> retryCodes = AIAssistSettingsService.getRetryStatusCodes();
    Integer iterations = AIAssistSettingsService.getDefaultMaxToolCallingIterations();
    Integer lockMinutes = AIAssistSettingsService.getProcessingLockMinutes();

    try {
      AIAssistSettingsService.getCalloutTimeoutMilliseconds();
      Assert.fail('A blank callout timeout should have thrown.');
    } catch (AIAssistSettingsService.AIAssistSettingsServiceException ex) {
      Assert.isTrue(
        ex.getMessage().contains('Callout Timeout'),
        'The error should name the missing setting.'
      );
    }
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.DEFAULT_AI_PROVIDER_SUCCESS_STATUS_CODES,
      successCodes,
      'With nothing usable the default applies, so a bad setting never fails every response.'
    );
    Assert.isTrue(retryCodes.isEmpty(), 'A blank list retries nothing.');
    Assert.areEqual(
      AIAssistApplicationConstants.DEFAULT_MAX_TOOL_CALLING_ITERATIONS,
      iterations,
      'Blank falls back to the default iterations.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.DEFAULT_PROCESSING_LOCK_MINUTES,
      lockMinutes,
      'Blank falls back to the default lock time.'
    );
  }
}
