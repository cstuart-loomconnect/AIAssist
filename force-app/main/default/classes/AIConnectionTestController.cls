/*
Class Name: AIConnectionTestController

=================================================================
=================================================================

Description: Test Connection for a model configuration: sends the smallest request the provider will
accept (one user message, one output token) through the configuration's own Named Credential and path,
and says in plain words whether it worked. A failure is explained the way a failed chat turn is (a rejected
credential, a retired model, rate limiting, a timeout), with the provider's own words for the
administrator.

Requires the AIAssistManageConfiguration custom permission. Nothing is saved before the callout; when the
test succeeds the configuration's Connection Tested Date is set afterwards, which the set-up checklist reads.
The key is never seen here: the Named Credential adds it.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public with sharing class AIConnectionTestController {
  public class TestResult {
    @AuraEnabled
    public Boolean isSuccess = false;
    @AuraEnabled
    public Integer statusCode;
    @AuraEnabled
    public String reason; // An AIConversationMessage__c.FailureReason__c value; null on success.
    @AuraEnabled
    public String message; // For the person testing.
    @AuraEnabled
    public String detail; // What the provider said, for an administrator.
    @AuraEnabled
    public Long latencyMilliseconds;
  }

  @AuraEnabled
  public static TestResult testConnection(Id modelConfigurationId) {
    try {
      AIConfigurationAccess.assertCanManage(false);
      return test(modelConfigurationId);
    } catch (Exception caughtException) {
      throw AIConfigurationAccess.toAura(
        caughtException,
        'AIConnectionTestController',
        'testConnection'
      );
    }
  }

  // The test itself, for a caller that has already checked access (AICredentialSetupController).
  public static TestResult test(Id modelConfigurationId) {
    TestResult result = new TestResult();
    AIModelConfiguration__c modelConfiguration = AIMessagingSelector.getModelConfiguration(
      modelConfigurationId
    );

    if (
      modelConfiguration == null ||
      String.isBlank(modelConfiguration.NamedCredential__c) ||
      String.isBlank(modelConfiguration.ApiPath__c) ||
      !AIProvider.isSupported(modelConfiguration.AIProvider__c)
    ) {
      result.reason = AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR;
      result.message = Label.AI_Error_Provider_Not_Configured;
      result.detail = 'The model configuration needs a supported provider, a Named Credential and an API Path before it can be tested.';
      return result;
    }

    AIProvider.Request request = new AIProvider.Request();
    request.modelIdentifier = modelConfiguration.ModelIdentifier__c;
    request.maxOutputTokens = 1;
    request.messages = new List<Map<String, Object>>{
      new Map<String, Object>{
        AIAssistApplicationConstants.CANONICAL_ROLE_KEY => AIAssistApplicationConstants.CANONICAL_ROLE_USER,
        AIAssistApplicationConstants.CANONICAL_CONTENT_KEY => 'ping'
      }
    };

    HttpRequest httpRequest = new HttpRequest();
    httpRequest.setEndpoint(
      'callout:' +
        modelConfiguration.NamedCredential__c +
        modelConfiguration.ApiPath__c
    );
    httpRequest.setMethod(AIAssistApplicationConstants.HTTP_METHOD_POST);
    httpRequest.setHeader(
      AIAssistApplicationConstants.HTTP_HEADER_CONTENT_TYPE,
      AIAssistApplicationConstants.CONTENT_TYPE_JSON
    );
    if (String.isNotBlank(modelConfiguration.ApiVersionHeaderName__c))
      httpRequest.setHeader(
        modelConfiguration.ApiVersionHeaderName__c,
        modelConfiguration.ApiVersionHeaderValue__c
      );
    httpRequest.setTimeout(
      AIAssistApplicationConstants.CONNECTION_TEST_TIMEOUT_MILLISECONDS
    );
    httpRequest.setBody(
      JSON.serialize(
        AIProvider.getRequestBuilder(modelConfiguration.AIProvider__c)
          .buildRequestBody(request)
      )
    );

    Long startedAt = System.currentTimeMillis();
    try {
      HttpResponse httpResponse = new Http().send(httpRequest);
      result.latencyMilliseconds = System.currentTimeMillis() - startedAt;
      result.statusCode = httpResponse.getStatusCode();
      result.isSuccess = AIAssistSettingsService.getSuccessStatusCodes()
        .contains(result.statusCode);

      if (!result.isSuccess) {
        result.reason = AIProvider.getFailureReason(
          result.statusCode,
          httpResponse.getBody()
        );
        result.detail =
          'HTTP ' +
          result.statusCode +
          ': ' +
          (String.isBlank(httpResponse.getBody())
            ? '(nothing)'
            : httpResponse.getBody().abbreviate(500));
      }
    } catch (CalloutException calloutException) {
      result.latencyMilliseconds = System.currentTimeMillis() - startedAt;
      String calloutDetail = calloutException.getMessage() == null
        ? ''
        : calloutException.getMessage();
      result.reason = calloutDetail.containsIgnoreCase('timed out')
        ? AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT
        : (calloutDetail.containsIgnoreCase('unauthorized endpoint') ||
            calloutDetail.containsIgnoreCase('named credential')
            ? AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR
            : AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR);
      result.detail = calloutDetail.abbreviate(500);
    }

    // The same words a chat user would see for this failure.
    result.message = result.isSuccess
      ? String.format(
          Label.AI_Console_Connection_Ok,
          new List<String>{ String.valueOf(result.latencyMilliseconds) }
        )
      : AIMessageOutcomeService.publishMessageFailure(null, result.reason);

    // After the callout, so the write cannot block it. Bookkeeping: a failure to stamp is logged and the result stands.
    if (result.isSuccess)
      AIMessagingDataService.updateAndLogFailures(
        new List<SObject>{
          new AIModelConfiguration__c(
            Id = modelConfiguration.Id,
            ConnectionTestedDate__c = System.now()
          )
        },
        'AIConnectionTestController',
        'test'
      );

    return result;
  }
}
