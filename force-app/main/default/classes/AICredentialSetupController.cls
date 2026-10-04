/*
Class Name: AICredentialSetupController

=================================================================
=================================================================

Description: Sets up the connection to an AI provider without the administrator building it by hand in
Setup. With sharing; every method needs the AIAssistManageConfiguration custom permission and Customize
Application.

The steps, each its own call because the platform will not mix them in one transaction (creating a
permission set and updating a model configuration cannot share one, and nothing may be written before a
callout):
[1] saveCredential: creates the External Credential (Custom protocol, one named principal "AIAssist", a
    header whose value is a formula reading the stored key "ApiKey"), stores the key, and creates the
    Named Credential from the provider's preset: the URL, formulas allowed in headers, and this package's
    namespace allowed to call it. Run again with the same name it updates what exists: the key is
    replaced (rotated) and nothing is duplicated. rotateKey replaces the key alone.
[2] grantAccess: users call the provider through a named principal, which a permission set must be mapped
    to. If one already is, nothing is done. Otherwise the permission set "AI Assist Credential Access" is
    created (or reused) and mapped, for the administrator to assign. If that cannot be done, the result
    carries instructions for doing it by hand.
[3] linkModelConfiguration: puts the Named Credential on the model configuration, with the provider's
    path and version header where they are blank.
[4] testConnection: AIConnectionTestController, whose result is what the administrator sees last.

The key: passed straight to the platform, which encrypts and stores it. It is never written to a record or
a log, never returned, and is removed from any error text before that is logged or shown. Each change is
recorded in the Platform Log by name and user only.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public with sharing class AICredentialSetupController {
  public class SetupResult {
    @AuraEnabled
    public Boolean isSuccess = false;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String externalCredential;
    @AuraEnabled
    public String namedCredential;
    @AuraEnabled
    public Boolean isRotation = false; // The credential already existed and its key was replaced.
    @AuraEnabled
    public String permissionSetName; // The permission set mapped to the principal, when one was created or found.
    @AuraEnabled
    public String manualInstructions; // Set when access must be granted by hand.
  }

  public static final String PRINCIPAL_NAME = 'AIAssist';
  public static final String KEY_PARAMETER_NAME = 'ApiKey';
  public static final String ACCESS_PERMISSION_SET_NAME = 'AIAssistCredentialAccess';
  private static final String ACCESS_PERMISSION_SET_LABEL = 'AI Assist Credential Access';
  private static final String KEY_MASK = '[key removed]';

  @TestVisible
  private static IAICredentialGateway gateway = new AICredentialGateway();

  // [1] developerName and baseUrl are optional: the name defaults to AIAssist plus the provider, and the URL to the provider's own.
  @AuraEnabled
  public static SetupResult saveCredential(
    String provider,
    String apiKey,
    String baseUrl,
    String developerName
  ) {
    try {
      AIConfigurationAccess.assertCanManage(true);

      AIProvider.Preset preset = AIProvider.getPreset(provider, null);
      String credentialName = String.isBlank(developerName)
        ? 'AIAssist' +
          (provider == null ? '' : provider.replaceAll('[^A-Za-z0-9]', ''))
        : developerName.trim();
      String url = String.isBlank(baseUrl)
        ? preset?.baseUrl
        : baseUrl.trim().removeEnd('/');

      if (preset == null)
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_NOT_AUTHORISED,
          'Provider "' +
            provider +
            '" is not supported. Choose Anthropic, OpenAI or Azure OpenAI.'
        );
      if (String.isBlank(apiKey))
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_NOT_AUTHORISED,
          'Enter the API key from your provider account.'
        );
      if (String.isBlank(url) || !url.startsWithIgnoreCase('https://'))
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_NOT_AUTHORISED,
          'Enter the base URL of your provider endpoint, starting with https://.'
        );
      if (
        !Pattern.matches('^[A-Za-z][A-Za-z0-9_]{0,39}$', credentialName) ||
        credentialName.endsWith('_') ||
        credentialName.contains('__')
      )
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_NOT_AUTHORISED,
          'The credential name "' +
            credentialName +
            '" must start with a letter and contain only letters, numbers and single underscores, up to 40 characters.'
        );

      SetupResult result = new SetupResult();
      result.externalCredential = credentialName;
      result.namedCredential = credentialName;

      // Matched by name, so running this again updates what is there.
      if (!gateway.externalCredentialExists(credentialName))
        gateway.createExternalCredential(
          credentialName,
          'AI Assist ' + provider,
          PRINCIPAL_NAME,
          preset.headerName,
          preset.headerValue.replace('{0}', credentialName)
        );

      result.isRotation = gateway.credentialExists(
        credentialName,
        PRINCIPAL_NAME
      );
      gateway.saveCredential(
        credentialName,
        PRINCIPAL_NAME,
        KEY_PARAMETER_NAME,
        apiKey,
        result.isRotation
      );

      gateway.saveNamedCredential(
        credentialName,
        'AI Assist ' + provider,
        url,
        credentialName,
        AIMessagingSelector.getPackageNamespace(),
        gateway.namedCredentialExists(credentialName)
      );

      audit(
        result.isRotation
          ? 'Provider key replaced.'
          : 'Provider credential created.',
        credentialName,
        'saveCredential'
      );
      result.isSuccess = true;
      result.message = String.format(
        result.isRotation
          ? Label.AI_Console_Credential_Rotated
          : Label.AI_Console_Credential_Created,
        new List<String>{ credentialName }
      );

      return result;
    } catch (Exception caughtException) {
      throw failed(caughtException, apiKey, 'saveCredential');
    }
  }

  // Replaces the stored key and nothing else.
  @AuraEnabled
  public static SetupResult rotateKey(
    String externalCredential,
    String apiKey
  ) {
    try {
      AIConfigurationAccess.assertCanManage(true);

      if (
        String.isBlank(apiKey) ||
        String.isBlank(externalCredential) ||
        !gateway.externalCredentialExists(externalCredential)
      )
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_NOT_AUTHORISED,
          'External Credential "' +
            externalCredential +
            '" was not found, or no key was entered. Create the credential first.'
        );

      gateway.saveCredential(
        externalCredential,
        PRINCIPAL_NAME,
        KEY_PARAMETER_NAME,
        apiKey,
        gateway.credentialExists(externalCredential, PRINCIPAL_NAME)
      );
      audit('Provider key replaced.', externalCredential, 'rotateKey');

      SetupResult result = new SetupResult();
      result.isSuccess = true;
      result.isRotation = true;
      result.externalCredential = externalCredential;
      result.message = String.format(
        Label.AI_Console_Credential_Rotated,
        new List<String>{ externalCredential }
      );

      return result;
    } catch (Exception caughtException) {
      throw failed(caughtException, apiKey, 'rotateKey');
    }
  }

  // [2] Never throws for a grant that could not be made: the result then says how to do it by hand.
  @AuraEnabled
  public static SetupResult grantAccess(String externalCredential) {
    try {
      AIConfigurationAccess.assertCanManage(true);
    } catch (Exception caughtException) {
      throw failed(caughtException, null, 'grantAccess');
    }

    SetupResult result = new SetupResult();
    result.externalCredential = externalCredential;
    Savepoint beforeGrant = Database.setSavepoint();

    try {
      Id principalId = gateway.getPrincipalId(
        externalCredential,
        PRINCIPAL_NAME
      );
      if (principalId == null)
        throw AIMessagingException.newFailure(
          'External Credential ' +
            externalCredential +
            ' has no principal named ' +
            PRINCIPAL_NAME +
            '.',
          null
        );

      // Already mapped on the External Credential: nothing to do.
      List<SetupEntityAccess> existingGrants = [
        SELECT Parent.Name
        FROM SetupEntityAccess
        WHERE SetupEntityId = :principalId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (!existingGrants.isEmpty()) {
        result.permissionSetName = existingGrants[0].Parent.Name;
      } else {
        List<PermissionSet> accessSets = [
          SELECT Id, Name
          FROM PermissionSet
          WHERE Name = :ACCESS_PERMISSION_SET_NAME AND NamespacePrefix = NULL
          WITH SYSTEM_MODE
          LIMIT 1
        ];
        PermissionSet accessSet = accessSets.isEmpty()
          ? new PermissionSet(
              Name = ACCESS_PERMISSION_SET_NAME,
              Label = ACCESS_PERMISSION_SET_LABEL,
              Description = 'Lets AI Assist users call the AI provider through its External Credential. Created by AI Assist credential set-up.'
            )
          : accessSets[0];
        if (accessSet.Id == null)
          Database.insert(accessSet, true, AccessLevel.SYSTEM_MODE);

        Database.insert(
          new SetupEntityAccess(
            ParentId = accessSet.Id,
            SetupEntityId = principalId
          ),
          true,
          AccessLevel.SYSTEM_MODE
        );
        result.permissionSetName = accessSet.Name;
      }

      audit(
        'Provider credential access mapped to permission set ' +
          result.permissionSetName +
          '.',
        externalCredential,
        'grantAccess'
      );
      result.isSuccess = true;
      result.message = String.format(
        Label.AI_Console_Credential_Access_Granted,
        new List<String>{ result.permissionSetName }
      );
    } catch (Exception grantException) {
      Database.rollback(beforeGrant);
      AIPlatformLogManager.logException(
        grantException,
        'AICredentialSetupController',
        'grantAccess'
      );
      result.permissionSetName = null;
      result.manualInstructions = String.format(
        Label.AI_Console_Credential_Access_Manual,
        new List<String>{ externalCredential }
      );
      result.message = result.manualInstructions;
    }

    return result;
  }

  // [3] Blank path and version header are filled from the provider's preset; values already there are kept.
  @AuraEnabled
  public static SetupResult linkModelConfiguration(
    Id modelConfigurationId,
    String namedCredential
  ) {
    try {
      AIConfigurationAccess.assertCanManage(true);

      AIModelConfiguration__c modelConfiguration = AIMessagingSelector.getModelConfiguration(
        modelConfigurationId
      );
      if (
        modelConfiguration == null ||
        String.isBlank(namedCredential) ||
        !gateway.namedCredentialExists(namedCredential)
      )
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_NOT_AUTHORISED,
          'The model configuration or the Named Credential "' +
            namedCredential +
            '" was not found. Create the credential first.'
        );

      AIProvider.Preset preset = AIProvider.getPreset(
        modelConfiguration.AIProvider__c,
        modelConfiguration.ModelIdentifier__c
      );
      AIModelConfiguration__c changes = new AIModelConfiguration__c(
        Id = modelConfiguration.Id,
        NamedCredential__c = namedCredential
      );
      if (preset != null && String.isBlank(modelConfiguration.ApiPath__c))
        changes.ApiPath__c = preset.apiPath;
      if (
        preset != null &&
        String.isBlank(modelConfiguration.ApiVersionHeaderName__c) &&
        String.isNotBlank(preset.versionHeaderName)
      ) {
        changes.ApiVersionHeaderName__c = preset.versionHeaderName;
        changes.ApiVersionHeaderValue__c = preset.versionHeaderValue;
      }
      // As the administrator: they hold edit on model configurations, and the save-time checks apply.
      Database.update(changes, true, AccessLevel.USER_MODE);

      SetupResult result = new SetupResult();
      result.isSuccess = true;
      result.namedCredential = namedCredential;
      result.message = String.format(
        Label.AI_Console_Credential_Linked,
        new List<String>{ namedCredential }
      );

      return result;
    } catch (Exception caughtException) {
      throw failed(caughtException, null, 'linkModelConfiguration');
    }
  }

  // [4]
  @AuraEnabled
  public static AIConnectionTestController.TestResult testConnection(
    Id modelConfigurationId
  ) {
    try {
      AIConfigurationAccess.assertCanManage(true);
      return AIConnectionTestController.test(modelConfigurationId);
    } catch (Exception caughtException) {
      throw failed(caughtException, null, 'testConnection');
    }
  }

  // The audit trail: what was done, to which credential, by whom. Never the key.
  private static void audit(
    String message,
    String credentialName,
    String methodName
  ) {
    AIPlatformLogManager.logAudit(
      message,
      'Credential ' +
        credentialName +
        ', by user ' +
        UserInfo.getUserId() +
        '.',
      'AICredentialSetupController',
      methodName
    );
  }

  // What the caller is shown when a step fails, with the key taken out of the error text before it is logged or returned: the platform can echo an input back in its message.
  private static AuraHandledException failed(
    Exception caughtException,
    String apiKey,
    String methodName
  ) {
    String errorText = caughtException.getMessage() == null
      ? Label.AI_Error_Generic
      : caughtException.getMessage();
    if (String.isNotBlank(apiKey))
      errorText = errorText.replace(apiKey, KEY_MASK);

    if (!(caughtException instanceof AIMessagingException))
      AIPlatformLogManager.logCustomMessage(
        'Credential set-up failed.',
        (caughtException.getTypeName() + ': ' + errorText).abbreviate(1000),
        'AICredentialSetupController',
        methodName,
        null,
        AIAssistApplicationConstants.LOG_SEVERITY_ERROR
      );

    AuraHandledException auraException = new AuraHandledException(errorText);
    auraException.setMessage(errorText);

    return auraException;
  }
}
