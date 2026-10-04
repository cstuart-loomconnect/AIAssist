/*
Class Name: AICredentialSetupControllerTest

=================================================================
=================================================================

Description: Testing utility for AICredentialSetupController and AIConfigurationAccess: the provider credential is created, re-run and rotated through a test double of the platform gateway, and the key never reaches a log, a result or an error.

=================================================================
=================================================================
Applicable Classes:

AICredentialSetupController, AIConfigurationAccess

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AICredentialSetupControllerTest {
  // testScenario1: Every step is refused without the AIAssistManageConfiguration permission, and without Customize Application, and nothing is created.
  // testScenario2: saveCredential creates the External Credential with the provider's header formula, stores the key, and creates the Named Credential with the provider's URL and this package's namespace.
  // testScenario3: Running it again updates rather than duplicates: no second External Credential, the key replaced, the Named Credential updated; rotateKey replaces the key alone.
  // testScenario4: The key never appears in a result, a Platform Log entry or an error, even when the platform echoes it back in its own error message.
  // testScenario5: grantAccess maps the principal to a created permission set, reuses it when run again, and returns instructions when it cannot be done.
  // testScenario6: linkModelConfiguration puts the Named Credential on the model configuration with the provider's path and version header, and Test Connection returns its result.
  // testScenario7: An unsupported provider, a blank key, a URL that is not https and a malformed name are each refused with a message that says what to fix.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  private static void allow(Boolean canManage, Boolean canCustomize) {
    AIConfigurationAccess.canManageForTest = canManage;
    AIConfigurationAccess.canCustomizeForTest = canCustomize;
  }

  private static final String SECRET = 'sk-test-SECRET-9f8e7d6c5b4a';

  // Stands in for ConnectApi.NamedCredentials, remembering what it was asked to do.
  private class GatewayDouble implements IAICredentialGateway {
    Set<String> externalCredentials = new Set<String>();
    Set<String> namedCredentials = new Set<String>();
    Map<String, String> storedKeys = new Map<String, String>();
    List<String> calls = new List<String>();
    String headerValue;
    String url;
    String allowedNamespace;
    Boolean shouldEchoKeyInError = false;
    Id principalId;

    public Id getPrincipalId(String externalCredential, String principalName) {
      return externalCredentials.contains(externalCredential)
        ? principalId
        : null;
    }

    public Boolean externalCredentialExists(String developerName) {
      return externalCredentials.contains(developerName);
    }

    public void createExternalCredential(
      String developerName,
      String label,
      String principalName,
      String headerName,
      String headerValue
    ) {
      calls.add('createExternalCredential:' + headerName);
      externalCredentials.add(developerName);
      this.headerValue = headerValue;
    }

    public Boolean credentialExists(
      String externalCredential,
      String principalName
    ) {
      return storedKeys.containsKey(externalCredential);
    }

    public void saveCredential(
      String externalCredential,
      String principalName,
      String parameterName,
      String secret,
      Boolean isUpdate
    ) {
      if (shouldEchoKeyInError)
        throw new CalloutException('The value ' + secret + ' was rejected.');
      calls.add(
        (isUpdate ? 'updateCredential:' : 'createCredential:') + parameterName
      );
      storedKeys.put(externalCredential, secret);
    }

    public Boolean namedCredentialExists(String developerName) {
      return namedCredentials.contains(developerName);
    }

    public void saveNamedCredential(
      String developerName,
      String label,
      String url,
      String externalCredential,
      String allowedNamespace,
      Boolean isUpdate
    ) {
      calls.add(isUpdate ? 'updateNamedCredential' : 'createNamedCredential');
      namedCredentials.add(developerName);
      this.url = url;
      this.allowedNamespace = allowedNamespace;
    }
  }

  private static GatewayDouble useDouble() {
    GatewayDouble gateway = new GatewayDouble();
    AICredentialSetupController.gateway = gateway;
    return gateway;
  }

  // Every text field of every Platform Log entry, joined, so a test can look for the key anywhere in the log.
  private static String allLogText() {
    Test.getEventBus().deliver();
    List<String> texts = new List<String>();
    for (AIPlatformLog__c log : [
      SELECT ExceptionMessage__c, ExceptionLogDetail__c, ClassName__c
      FROM AIPlatformLog__c
    ])
      texts.add(JSON.serialize(log));
    return String.join(texts, '\n');
  }

  @IsTest
  static void testScenario1() {
    GatewayDouble gateway = useDouble();
    List<String> refusals = new List<String>();

    Test.startTest();
    for (
      List<Boolean> held : new List<List<Boolean>>{
        new List<Boolean>{ false, true },
        new List<Boolean>{ true, false }
      }
    ) {
      allow(held[0], held[1]);
      try {
        AICredentialSetupController.saveCredential(
          'Anthropic',
          SECRET,
          null,
          null
        );
      } catch (AuraHandledException refused) {
        refusals.add(refused.getMessage());
      }
      try {
        AICredentialSetupController.rotateKey('AIAssistAnthropic', SECRET);
      } catch (AuraHandledException refused) {
        refusals.add(refused.getMessage());
      }
      try {
        AICredentialSetupController.grantAccess('AIAssistAnthropic');
      } catch (AuraHandledException refused) {
        refusals.add(refused.getMessage());
      }
      try {
        AICredentialSetupController.linkModelConfiguration(
          null,
          'AIAssistAnthropic'
        );
      } catch (AuraHandledException refused) {
        refusals.add(refused.getMessage());
      }
      try {
        AICredentialSetupController.testConnection(null);
      } catch (AuraHandledException refused) {
        refusals.add(refused.getMessage());
      }
    }
    Test.stopTest();

    Assert.areEqual(10, refusals.size(), 'Five steps, refused both ways.');
    for (String refusal : refusals)
      Assert.areEqual(
        Label.AI_Error_Not_Authorised,
        refusal,
        'Not authorised.'
      );
    Assert.isTrue(gateway.calls.isEmpty(), 'Nothing was created.');
  }

  @IsTest
  static void testScenario2() {
    allow(true, true);
    GatewayDouble gateway = useDouble();

    Test.startTest();
    AICredentialSetupController.SetupResult result = AICredentialSetupController.saveCredential(
      'Anthropic',
      SECRET,
      null,
      null
    );
    Test.stopTest();

    Assert.isTrue(result.isSuccess, 'Created.');
    Assert.isFalse(result.isRotation, 'A first run is not a rotation.');
    Assert.areEqual(
      'AIAssistAnthropic',
      result.namedCredential,
      'Named after the provider.'
    );
    Assert.areEqual(
      new List<String>{
        'createExternalCredential:x-api-key',
        'createCredential:ApiKey',
        'createNamedCredential'
      },
      gateway.calls,
      'The External Credential, the key, then the Named Credential.'
    );
    Assert.areEqual(
      '{!$Credential.AIAssistAnthropic.ApiKey}',
      gateway.headerValue,
      'The header is a formula that reads the stored key, not the key.'
    );
    Assert.areEqual(
      'https://api.anthropic.com',
      gateway.url,
      'The provider\'s URL.'
    );
    Assert.areEqual(
      AIMessagingSelector.getPackageNamespace(),
      gateway.allowedNamespace,
      'This package\'s namespace is allowed to call it.'
    );
    Assert.areEqual(
      SECRET,
      gateway.storedKeys.get('AIAssistAnthropic'),
      'The key went to the platform.'
    );
  }

  @IsTest
  static void testScenario3() {
    allow(true, true);
    GatewayDouble gateway = useDouble();

    Test.startTest();
    AICredentialSetupController.saveCredential(
      'OpenAI',
      SECRET,
      'https://api.example.com/',
      'Compatible_Service'
    );
    gateway.calls.clear();
    AICredentialSetupController.SetupResult again = AICredentialSetupController.saveCredential(
      'OpenAI',
      'sk-second-key',
      'https://api.example.com',
      'Compatible_Service'
    );
    List<String> secondRun = gateway.calls.clone();
    gateway.calls.clear();
    AICredentialSetupController.SetupResult rotated = AICredentialSetupController.rotateKey(
      'Compatible_Service',
      'sk-third-key'
    );
    String missing;
    try {
      AICredentialSetupController.rotateKey('No_Such_Credential', 'sk-x');
    } catch (AuraHandledException refused) {
      missing = refused.getMessage();
    }
    Test.stopTest();

    Assert.areEqual(
      new List<String>{ 'updateCredential:ApiKey', 'updateNamedCredential' },
      secondRun,
      'Matched by name: the key and the Named Credential are updated, and no second External Credential is created.'
    );
    Assert.isTrue(again.isRotation, 'The second run replaced the key.');
    Assert.areEqual(
      1,
      gateway.externalCredentials.size(),
      'One External Credential.'
    );
    Assert.areEqual(
      1,
      gateway.namedCredentials.size(),
      'One Named Credential.'
    );
    Assert.areEqual(
      'https://api.example.com',
      gateway.url,
      'An OpenAI-compatible base URL, without the trailing slash.'
    );
    Assert.areEqual(
      new List<String>{ 'updateCredential:ApiKey' },
      gateway.calls,
      'Rotation replaces the key alone.'
    );
    Assert.isTrue(rotated.isRotation, 'A rotation.');
    Assert.areEqual(
      'sk-third-key',
      gateway.storedKeys.get('Compatible_Service'),
      'The newest key is the one stored.'
    );
    Assert.isTrue(
      missing.contains('No_Such_Credential'),
      'A missing credential is named: ' + missing
    );
  }

  @IsTest
  static void testScenario4() {
    allow(true, true);
    GatewayDouble gateway = useDouble();
    String errorShown;

    Test.startTest();
    AICredentialSetupController.SetupResult created = AICredentialSetupController.saveCredential(
      'Anthropic',
      SECRET,
      null,
      null
    );
    AICredentialSetupController.SetupResult rotated = AICredentialSetupController.rotateKey(
      'AIAssistAnthropic',
      SECRET
    );
    gateway.shouldEchoKeyInError = true;
    try {
      AICredentialSetupController.saveCredential(
        'Anthropic',
        SECRET,
        null,
        null
      );
    } catch (AuraHandledException failure) {
      errorShown = failure.getMessage();
    }
    String logText = allLogText();
    Test.stopTest();

    Assert.isFalse(
      JSON.serialize(created).contains(SECRET),
      'Not in the result.'
    );
    Assert.isFalse(
      JSON.serialize(rotated).contains(SECRET),
      'Not in the rotation result.'
    );
    Assert.isNotNull(errorShown, 'The failure is reported.');
    Assert.isFalse(
      errorShown.contains(SECRET),
      'Removed from the error shown: ' + errorShown
    );
    Assert.isTrue(
      errorShown.contains('[key removed]'),
      'Replaced, so the rest of the error is still readable.'
    );
    Assert.isTrue(
      String.isNotBlank(logText),
      'The changes and the failure were logged.'
    );
    Assert.isFalse(logText.contains(SECRET), 'Never in the Platform Log.');
    Assert.isTrue(
      logText.contains('AIAssistAnthropic'),
      'The audit entry names the credential.'
    );
    Assert.isTrue(
      logText.contains(UserInfo.getUserId()),
      'And who changed it.'
    );
  }

  @IsTest
  static void testScenario5() {
    allow(true, true);
    GatewayDouble gateway = useDouble();
    gateway.externalCredentials.add('AIAssistAnthropic');
    // A principal cannot be created in a test; a custom permission is another thing a permission set can be given.
    gateway.principalId = [
      SELECT Id
      FROM CustomPermission
      WHERE
        DeveloperName = :AIAssistApplicationConstants.PERMISSION_MANAGE_CONFIGURATION
      LIMIT 1
    ]
    .Id;
    AICredentialSetupController.SetupResult first;
    AICredentialSetupController.SetupResult second;
    AICredentialSetupController.SetupResult manual;

    Test.startTest();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      delete [
        SELECT Id
        FROM SetupEntityAccess
        WHERE SetupEntityId = :gateway.principalId
      ];
      first = AICredentialSetupController.grantAccess('AIAssistAnthropic');
      second = AICredentialSetupController.grantAccess('AIAssistAnthropic');
      manual = AICredentialSetupController.grantAccess('No_Such_Credential');
    }
    Test.stopTest();

    Assert.isTrue(first.isSuccess, 'Granted: ' + first.message);
    Assert.areEqual(
      AICredentialSetupController.ACCESS_PERMISSION_SET_NAME,
      first.permissionSetName,
      'Through the created permission set.'
    );
    Assert.areEqual(
      first.permissionSetName,
      second.permissionSetName,
      'Already mapped: the same set, not a second one.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM PermissionSet
        WHERE Name = :AICredentialSetupController.ACCESS_PERMISSION_SET_NAME
      ],
      'One permission set.'
    );
    Assert.isFalse(manual.isSuccess, 'Not granted.');
    Assert.isTrue(
      manual.manualInstructions.contains('No_Such_Credential'),
      'Instructions for doing it by hand, naming the credential.'
    );
  }

  @IsTest
  static void testScenario6() {
    allow(true, true);
    GatewayDouble gateway = useDouble();
    gateway.namedCredentials.add('AIAssistAnthropic');
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      false
    )[0];
    model.NamedCredential__c = null;
    model.ApiPath__c = null;
    model.IsActive__c = false;
    insert model;
    HttpResponse reply = new HttpResponse();
    reply.setStatusCode(200);
    reply.setBody('{"content":[{"type":"text","text":"p"}]}');
    Test.setMock(HttpCalloutMock.class, new FixedMock(reply));
    String missing;

    // Each step is its own request in use; the link is saved before the test's callout so the two do not share a transaction here either.
    AICredentialSetupController.SetupResult linked = AICredentialSetupController.linkModelConfiguration(
      model.Id,
      'AIAssistAnthropic'
    );
    try {
      AICredentialSetupController.linkModelConfiguration(
        model.Id,
        'No_Such_Credential'
      );
    } catch (AuraHandledException refused) {
      missing = refused.getMessage();
    }

    Test.startTest();
    AIConnectionTestController.TestResult tested = AICredentialSetupController.testConnection(
      model.Id
    );
    Test.stopTest();

    model = [
      SELECT
        NamedCredential__c,
        ApiPath__c,
        ApiVersionHeaderName__c,
        ApiVersionHeaderValue__c
      FROM AIModelConfiguration__c
      WHERE Id = :model.Id
    ];
    Assert.isTrue(linked.isSuccess, 'Linked.');
    Assert.areEqual(
      'AIAssistAnthropic',
      model.NamedCredential__c,
      'The Named Credential is on the model configuration.'
    );
    Assert.areEqual(
      '/v1/messages',
      model.ApiPath__c,
      'The provider\'s path filled the blank.'
    );
    Assert.areEqual(
      'anthropic-version',
      model.ApiVersionHeaderName__c,
      'And its version header.'
    );
    Assert.isTrue(
      missing.contains('No_Such_Credential'),
      'A missing Named Credential is named.'
    );
    Assert.isTrue(
      tested.isSuccess,
      'The Test Connection result is what comes back last: ' + tested.detail
    );
  }

  private class FixedMock implements HttpCalloutMock {
    HttpResponse reply;
    FixedMock(HttpResponse reply) {
      this.reply = reply;
    }
    public HttpResponse respond(HttpRequest request) {
      return reply;
    }
  }

  @IsTest
  static void testScenario7() {
    allow(true, true);
    GatewayDouble gateway = useDouble();
    List<String> messages = new List<String>();

    Test.startTest();
    for (
      List<String> input : new List<List<String>>{
        new List<String>{ 'Teleport AI', SECRET, null, null },
        new List<String>{ 'Anthropic', ' ', null, null },
        new List<String>{
          'OpenAI',
          SECRET,
          'http://insecure.example.com',
          null
        },
        new List<String>{ 'Azure OpenAI', SECRET, null, null },
        new List<String>{ 'Anthropic', SECRET, null, '9 bad name' }
      }
    ) {
      try {
        AICredentialSetupController.saveCredential(
          input[0],
          input[1],
          input[2],
          input[3]
        );
      } catch (AuraHandledException refused) {
        messages.add(refused.getMessage());
      }
    }
    Test.stopTest();

    Assert.areEqual(5, messages.size(), 'Each is refused.');
    Assert.isTrue(messages[0].contains('not supported'), messages[0]);
    Assert.isTrue(messages[1].contains('API key'), messages[1]);
    Assert.isTrue(messages[2].contains('https://'), messages[2]);
    Assert.isTrue(
      messages[3].contains('base URL'),
      'Azure has no default URL: ' + messages[3]
    );
    Assert.isTrue(messages[4].contains('9 bad name'), messages[4]);
    Assert.isTrue(gateway.calls.isEmpty(), 'Nothing was created.');
    for (String message : messages)
      Assert.isFalse(message.contains(SECRET), 'No refusal repeats the key.');
  }
}
