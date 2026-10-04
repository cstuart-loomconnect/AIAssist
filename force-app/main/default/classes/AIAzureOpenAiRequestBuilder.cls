/*
Class Name: AIAzureOpenAiRequestBuilder

=================================================================
=================================================================

Description: Builds the request body for Azure OpenAI. Azure serves the same Chat Completions API as OpenAI
with two differences, and only the first is in the body:
[1] The model is chosen by the deployment in the URL
    (/openai/deployments/{deployment}/chat/completions?api-version=...), so the body carries no "model".
    The deployment name is AIModelConfiguration__c.ModelIdentifier__c and the URL is ApiPath__c
    (AIProvider.getPreset builds the default).
[2] The key is sent in an "api-key" header, not "Authorization: Bearer". That is set on the Named
    Credential, never here: this package does not handle the key at run time.
Everything else, including the reply, is OpenAI's, so the body is AIOpenAiRequestBuilder's with the model
taken out and the reply is read by AIOpenAiResponseHandler.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public inherited sharing class AIAzureOpenAiRequestBuilder implements IAIProviderRequestBuilder {
  public Map<String, Object> buildRequestBody(AIProvider.Request request) {
    Map<String, Object> requestBody = new AIOpenAiRequestBuilder()
      .buildRequestBody(request);
    requestBody.remove(AIAssistApplicationConstants.OPENAI_FIELD_MODEL);

    return requestBody;
  }
}
