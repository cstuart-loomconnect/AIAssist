/*
Class Name: IAIProviderResponseHandler

=================================================================
=================================================================

Description: Contract for one AI provider's response shape - a single method covering everything response-side.

Step 1: AIProvider picks the implementation matching AIModelConfiguration__c.AIProvider__c (e.g. AIAnthropicMessageResponseHandler, AIOpenAiResponseHandler)
Step 2: AIAgentManager calls handleResponse once per job per tool-calling loop pass
Step 3: The implementation updates providerMessages and returns an AIProvider.Response (making any further callouts its provider needs to finish the answer)

AIAgentManager never inspects a provider's raw JSON itself.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public interface IAIProviderResponseHandler {

    // request is the one that produced response (null when only tool results are being added); most providers ignore it, but one that needs further callouts to finish its answer reads its session from it. Shapes providerMessages for one job: either appends prior tool results (previousToolCalls/previousToolResults set, response null) or parses response and appends the assistant turn (response set, previousToolCalls/previousToolResults null).
    AIProvider.Response handleResponse(List<Map<String, Object>> providerMessages, HttpResponse response, List<AIProvider.ToolCall> previousToolCalls, List<Object> previousToolResults, AIProvider.Request request);
}
