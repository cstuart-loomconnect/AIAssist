/*
Class Name: IAIProviderRequestBuilder

=================================================================
=================================================================

Description: Contract for shaping one AI provider's request body, implemented per provider (e.g. AIAnthropicMessageRequestBuilder).

Step 1: The caller passes in the canonical AIProvider.Request
Step 2: The implementation converts it into that provider's exact JSON-ready body
Step 3: The body is returned to the caller to send

Kept separate from IAIProviderResponseHandler since building a request and handling a response are different jobs.
The endpoint path and API version header are not part of this contract. They vary per deployment (e.g. Azure OpenAI vs. OpenAI directly), not per provider brand, so they live on AIModelConfiguration__c instead.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public interface IAIProviderRequestBuilder {

    // Converts the canonical request into this provider's exact JSON-ready body.
    Map<String, Object> buildRequestBody(AIProvider.Request request);
}
