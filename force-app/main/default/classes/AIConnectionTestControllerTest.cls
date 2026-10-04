/*
Class Name: AIConnectionTestControllerTest

=================================================================
=================================================================

Description: Testing utility for AIConnectionTestController: a minimal call to the provider and a readable result.

=================================================================
=================================================================
Applicable Classes:

AIConnectionTestController

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIConnectionTestControllerTest {
  // testScenario1: A successful test sends one small request to the model's Named Credential and path, says so, and stamps the Connection Tested Date.
  // testScenario2: A rejected credential, a retired model and rate limiting each come back with their own reason and readable message, and nothing is stamped.
  // testScenario3: A timeout and an endpoint that cannot be called are explained, not thrown.
  // testScenario4: A model configuration that is missing, or has no Named Credential, is reported as not configured without a callout.
  // testScenario5: Without the AIAssistManageConfiguration permission the test is refused.

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

  private class ScriptedMock implements HttpCalloutMock {
    List<Object> script = new List<Object>();
    List<HttpRequest> requests = new List<HttpRequest>();

    public HttpResponse respond(HttpRequest request) {
      requests.add(request);
      Object next = script.remove(0);
      if (next instanceof Exception)
        throw (Exception) next;
      return (HttpResponse) next;
    }
  }

  private static HttpResponse response(Integer statusCode, String body) {
    HttpResponse httpResponse = new HttpResponse();
    httpResponse.setStatusCode(statusCode);
    httpResponse.setBody(body);
    return httpResponse;
  }

  private static AIModelConfiguration__c createModel() {
    return AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
  }

  @IsTest
  static void testScenario1() {
    allow(true, false);
    AIModelConfiguration__c model = createModel();
    ScriptedMock mock = new ScriptedMock();
    mock.script.add(response(200, '{"content":[{"type":"text","text":"p"}]}'));
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AIConnectionTestController.TestResult result = AIConnectionTestController.testConnection(
      model.Id
    );
    Test.stopTest();

    Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(
      mock.requests[0].getBody()
    );
    Assert.isTrue(result.isSuccess, 'Connected: ' + result.detail);
    Assert.areEqual(200, result.statusCode, 'The status.');
    Assert.isNull(result.reason, 'No failure reason.');
    Assert.isTrue(
      result.message.contains(String.valueOf(result.latencyMilliseconds)),
      'Says how long it took.'
    );
    Assert.areEqual(
      'callout:Test_Credential/v1/messages',
      mock.requests[0].getEndpoint(),
      'The model\'s own credential and path.'
    );
    Assert.areEqual(
      1,
      sent.get('max_tokens'),
      'The smallest request: one output token.'
    );
    Assert.areEqual(
      1,
      ((List<Object>) sent.get('messages')).size(),
      'One message.'
    );
    Assert.isNotNull(
      [
        SELECT ConnectionTestedDate__c
        FROM AIModelConfiguration__c
        WHERE Id = :model.Id
      ]
      .ConnectionTestedDate__c,
      'Stamped for the set-up checklist.'
    );
  }

  @IsTest
  static void testScenario2() {
    allow(true, false);
    AIModelConfiguration__c model = createModel();
    ScriptedMock mock = new ScriptedMock();
    mock.script.add(
      response(
        401,
        '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}'
      )
    );
    mock.script.add(
      response(
        404,
        '{"type":"error","error":{"type":"not_found_error","message":"model: test-model"}}'
      )
    );
    mock.script.add(response(429, '{"error":{"code":"rate_limit_exceeded"}}'));
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AIConnectionTestController.TestResult rejected = AIConnectionTestController.testConnection(
      model.Id
    );
    AIConnectionTestController.TestResult retired = AIConnectionTestController.testConnection(
      model.Id
    );
    AIConnectionTestController.TestResult limited = AIConnectionTestController.testConnection(
      model.Id
    );
    Test.stopTest();

    Assert.isFalse(rejected.isSuccess, 'Not connected.');
    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_AUTHENTICATION_FAILED,
      rejected.reason,
      'A rejected key.'
    );
    Assert.areEqual(
      Label.AI_Error_Provider_Authentication,
      rejected.message,
      'In plain words.'
    );
    Assert.isTrue(
      rejected.detail.contains('401') &&
      rejected.detail.contains('invalid x-api-key'),
      'With the provider\'s own words for the administrator.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED,
      retired.reason,
      'A retired model.'
    );
    Assert.areEqual(
      Label.AI_Error_Provider_Model_Retired,
      retired.message,
      'In plain words.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_RATE_LIMITED,
      limited.reason,
      'Rate limited.'
    );
    Assert.isNull(
      [
        SELECT ConnectionTestedDate__c
        FROM AIModelConfiguration__c
        WHERE Id = :model.Id
      ]
      .ConnectionTestedDate__c,
      'A failed test stamps nothing.'
    );
  }

  @IsTest
  static void testScenario3() {
    allow(true, false);
    AIModelConfiguration__c model = createModel();
    ScriptedMock mock = new ScriptedMock();
    mock.script.add(new CalloutException('Read timed out'));
    mock.script.add(
      new CalloutException('Unauthorized endpoint, please check Setup')
    );
    mock.script.add(new CalloutException('Connection reset'));
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AIConnectionTestController.TestResult timedOut = AIConnectionTestController.testConnection(
      model.Id
    );
    AIConnectionTestController.TestResult notAllowed = AIConnectionTestController.testConnection(
      model.Id
    );
    AIConnectionTestController.TestResult reset = AIConnectionTestController.testConnection(
      model.Id
    );
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT,
      timedOut.reason,
      'A timeout.'
    );
    Assert.areEqual(
      Label.AI_Error_Provider_Timeout,
      timedOut.message,
      'In plain words.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR,
      notAllowed.reason,
      'A setup problem.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR,
      reset.reason,
      'Anything else.'
    );
    Assert.isTrue(
      reset.detail.contains('Connection reset'),
      'The real reason is kept for the administrator.'
    );
  }

  @IsTest
  static void testScenario4() {
    allow(true, false);
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      false
    )[0];
    model.NamedCredential__c = null;
    model.IsActive__c = false;
    insert model;

    Test.startTest();
    AIConnectionTestController.TestResult noCredential = AIConnectionTestController.testConnection(
      model.Id
    );
    AIConnectionTestController.TestResult noModel = AIConnectionTestController.testConnection(
      null
    );
    Integer callouts = Limits.getCallouts();
    Test.stopTest();

    Assert.isFalse(noCredential.isSuccess, 'Not testable.');
    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR,
      noCredential.reason,
      'Not configured.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR,
      noModel.reason,
      'No such model configuration.'
    );
    Assert.areEqual(0, callouts, 'No callout was made.');
  }

  @IsTest
  static void testScenario5() {
    allow(false, true);
    AIModelConfiguration__c model = createModel();
    String refusal;

    Test.startTest();
    try {
      AIConnectionTestController.testConnection(model.Id);
    } catch (AuraHandledException refused) {
      refusal = refused.getMessage();
    }
    Test.stopTest();

    Assert.areEqual(
      Label.AI_Error_Not_Authorised,
      refusal,
      'Refused without the permission.'
    );
  }
}
