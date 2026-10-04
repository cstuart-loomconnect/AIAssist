/*
Class Name: AIAssistSettingsService

=================================================================
=================================================================

Description: The one reader of AIAssistSettings__c and AIAssistUISettings__c. Every other class
asks this one, so a setting that is blank, zero or garbled has one place that decides what
happens: a safe default, or a refusal to guess.

A custom setting row is data, not metadata. With no organisation row yet, getOrgDefaults()
returns every checkbox as false, which would read every "Is ... Enabled" switch as off. So when
there is no row the field defaults are loaded instead (the post-install script creates the
row, but a scratch org or a deleted row must still work).

Blank logging switches count as on: logging is only off when explicitly unchecked.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Rebuilt for the object model: IsEnabled__c replaces IsApplicationActive__c, per-value caches removed (the platform already caches custom settings), numeric defaults share one rule.
3.0          Chandler Stuart          Sandbox guard (ActivatedOrgId__c), activate, and the step capture mode.
*/

public inherited sharing class AIAssistSettingsService {
  public class AIAssistSettingsServiceException extends Exception {
  }

  @TestVisible
  private static AIAssistSettings__c cachedSettings; // Tests clear it to read a setting changed earlier in the same transaction.

  // Forgets the cached settings so the next read sees a change made in this transaction.
  public static void clearCache() {
    cachedSettings = null;
  }

  // The organisation settings, cached for the transaction.
  public static AIAssistSettings__c getSettings() {
    if (cachedSettings == null) {
      AIAssistSettings__c organisationDefaults = AIAssistSettings__c.getOrgDefaults();
      cachedSettings = organisationDefaults != null &&
        organisationDefaults.Id != null
        ? organisationDefaults
        : (AIAssistSettings__c) AIAssistSettings__c.SObjectType.newSObject(
            null,
            true
          );
    }

    return cachedSettings;
  }

  // The running user's AIAssistUISettings__c (user, then profile, then organisation level), uncached so the chat window sees a change made earlier in the transaction. With no row at any level the field defaults apply, otherwise the default-on switches would all read as off.
  public static AIAssistUISettings__c getUiSettings() {
    AIAssistUISettings__c mergedSettings = AIAssistUISettings__c.getInstance();
    if (mergedSettings != null && mergedSettings.Id != null)
      return mergedSettings;

    Set<Id> hierarchyOwnerIds = new Set<Id>{
      UserInfo.getUserId(),
      UserInfo.getProfileId(),
      UserInfo.getOrganizationId()
    };
    Boolean hasAnyRow =
      [
        SELECT COUNT()
        FROM AIAssistUISettings__c
        WHERE SetupOwnerId IN :hierarchyOwnerIds
        WITH SYSTEM_MODE
      ] > 0;

    return hasAnyRow
      ? mergedSettings
      : (AIAssistUISettings__c) AIAssistUISettings__c.SObjectType.newSObject(
          null,
          true
        );
  }

  // The application switch every trigger and entry point respects. Blank counts as on. Off as well when the settings were activated in another org (isActivatedElsewhere): a sandbox copied from production stays off until it is activated there.
  public static Boolean isEnabled() {
    return getSettings().IsEnabled__c != false && !isActivatedElsewhere();
  }

  // True when ActivatedOrgId__c names an org other than this one. Blank is not "elsewhere": it has not been recorded yet.
  public static Boolean isActivatedElsewhere() {
    String activatedOrgId = getSettings().ActivatedOrgId__c;

    return String.isNotBlank(activatedOrgId) &&
      !UserInfo.getOrganizationId().startsWith(activatedOrgId.left(15));
  }

  // Switches the application on in this org and records the org, which is what makes a copy of the settings in another org inactive. Creates the settings row when there is none.
  public static void activate() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    if (settings == null || settings.Id == null) {
      settings = (AIAssistSettings__c) AIAssistSettings__c.SObjectType.newSObject(
        null,
        true
      );
      settings.SetupOwnerId = UserInfo.getOrganizationId();
    }
    settings.IsEnabled__c = true;
    settings.ActivatedOrgId__c = UserInfo.getOrganizationId();
    Database.upsert(settings, true, AccessLevel.SYSTEM_MODE);
    clearCache();
  }

  // Records this org on settings that are switched on and have no org recorded yet (switched on in Setup, or from before the field existed). Called where DML is safe: the maintenance job and after a turn. A failure is logged, never thrown.
  public static void recordActivatedOrg() {
    try {
      AIAssistSettings__c settings = getSettings();
      if (
        settings.Id == null ||
        settings.IsEnabled__c == false ||
        String.isNotBlank(settings.ActivatedOrgId__c)
      )
        return;

      Database.update(
        new AIAssistSettings__c(
          Id = settings.Id,
          ActivatedOrgId__c = UserInfo.getOrganizationId()
        ),
        true,
        AccessLevel.SYSTEM_MODE
      );
      clearCache();
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIAssistSettingsService',
        'recordActivatedOrg'
      );
    }
  }

  // Exceptions are published as events unless this is explicitly unchecked.
  public static Boolean isExceptionLoggingEnabled() {
    return getSettings().IsExceptionLoggingEnabled__c != false;
  }

  // Published events are saved as AIPlatformLog__c records unless this is explicitly unchecked.
  public static Boolean isPlatformLoggingEnabled() {
    return getSettings().IsPlatformLoggingEnabled__c != false;
  }

  // Parses AIProviderSuccessStatusCodes__c (for example "200,201"). Entries that are not numbers are skipped, and an empty result falls back to the default so a bad setting never fails every response.
  public static Set<Integer> getSuccessStatusCodes() {
    String configuredCodes = getSettings().AIProviderSuccessStatusCodes__c;
    Set<Integer> successCodes = new Set<Integer>();

    if (String.isNotBlank(configuredCodes)) {
      for (String codeEntry : configuredCodes.split(',')) {
        if (String.isNotBlank(codeEntry) && codeEntry.trim().isNumeric())
          successCodes.add(Integer.valueOf(codeEntry.trim()));
      }
    }

    return successCodes.isEmpty()
      ? new Set<Integer>(
          AIAssistApplicationConstants.DEFAULT_AI_PROVIDER_SUCCESS_STATUS_CODES
        )
      : successCodes;
  }

  // Parses RetryableStatusCodes__c (for example "429,503"). An empty result means no status is ever retried.
  public static Set<Integer> getRetryStatusCodes() {
    String configuredCodes = getSettings().RetryableStatusCodes__c;
    Set<Integer> retryCodes = new Set<Integer>();

    if (String.isNotBlank(configuredCodes)) {
      for (String codeEntry : configuredCodes.split(',')) {
        if (String.isNotBlank(codeEntry) && codeEntry.trim().isNumeric())
          retryCodes.add(Integer.valueOf(codeEntry.trim()));
      }
    }

    return retryCodes;
  }

  // Required configuration: blank or not positive throws rather than guessing a timeout.
  public static Integer getCalloutTimeoutMilliseconds() {
    Decimal configuredTimeout = getSettings().CalloutTimeoutMilliseconds__c;

    if (configuredTimeout == null || configuredTimeout < 1)
      throw new AIAssistSettingsServiceException(
        'AI Assist Settings has no Callout Timeout Milliseconds configured.'
      );

    return configuredTimeout.intValue();
  }

  // Used when an agent has no MaxToolCallingIterations__c. Blank or below 1 falls back to the default.
  public static Integer getDefaultMaxToolCallingIterations() {
    return positiveOrDefault(
      getSettings().DefaultMaxToolCallingIterations__c,
      AIAssistApplicationConstants.DEFAULT_MAX_TOOL_CALLING_ITERATIONS
    );
  }

  // Upper bound on every agent's tool-calling iterations.
  public static Integer getMaxToolCallingIterationsCap() {
    return positiveOrDefault(
      getSettings().MaxToolCallingIterationsCap__c,
      AIAssistApplicationConstants.DEFAULT_MAX_TOOL_CALLING_ITERATIONS_CAP
    );
  }

  // How many tool calls run from one model reply.
  public static Integer getMaxToolCallsPerIteration() {
    return positiveOrDefault(
      getSettings().MaxToolCallsPerIteration__c,
      AIAssistApplicationConstants.DEFAULT_MAX_TOOL_CALLS_PER_ITERATION
    );
  }

  // How much of each turn is stored as execution steps: Off, Summary or Full. Blank or anything unrecognised is Summary.
  public static String getStepCaptureMode() {
    String configuredMode = getSettings().StepCaptureMode__c;

    return AIAssistApplicationConstants.STEP_CAPTURE_OFF.equalsIgnoreCase(
        configuredMode
      )
      ? AIAssistApplicationConstants.STEP_CAPTURE_OFF
      : (AIAssistApplicationConstants.STEP_CAPTURE_FULL.equalsIgnoreCase(
            configuredMode
          )
          ? AIAssistApplicationConstants.STEP_CAPTURE_FULL
          : AIAssistApplicationConstants.STEP_CAPTURE_SUMMARY);
  }

  // How long a conversation's processing lock lasts before it expires on its own.
  public static Integer getProcessingLockMinutes() {
    return positiveOrDefault(
      getSettings().ProcessingLockMinutes__c,
      AIAssistApplicationConstants.DEFAULT_PROCESSING_LOCK_MINUTES
    );
  }

  private static Integer positiveOrDefault(
    Decimal configuredValue,
    Integer fallbackValue
  ) {
    return (configuredValue == null ||
      configuredValue < 1)
      ? fallbackValue
      : configuredValue.intValue();
  }
}
