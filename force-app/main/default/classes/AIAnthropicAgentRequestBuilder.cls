/*
Class Name: AIAnthropicAgentRequestBuilder

=================================================================
=================================================================

Description: Opens the Anthropic Agent API session for the turn, continuing the conversation's saved one when it can, and builds the body that sends one turn's events to it.

Step 1: The first time in the turn, continue the conversation's saved session if it is still usable, else start a new session for the agent and its environment
Step 2: Point the request at that session, and give it the extra headers the Agent API needs
Step 3: For a user message, add the system prompt, then the message itself, with the earlier conversation written into it only when the session is new
Step 4: For tool results, add one custom tool result event per tool call
Step 5: Return the events body

The session is the one on the request, shared with the response handler and the next pass of the turn.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAnthropicAgentRequestBuilder implements IAIProviderRequestBuilder {

    public class AIAnthropicAgentRequestBuilderException extends Exception {}

    private static final String METHOD_GET = 'GET';

    // Opens the session if there is none, then builds { events: [...] } for POST /v1/sessions/{id}/events. The model, tools and max tokens belong to the agent on Anthropic's side, so they are not sent, and the tool definitions in the request are ignored.
    public Map<String, Object> buildRequestBody(AIProvider.Request request) {

        try {

            // [1] A request with no messages has nothing to send
            if (request == null || request.messages == null || request.messages.isEmpty()) throw new AIAnthropicAgentRequestBuilderException('There is no message to send to the agent.');

            // [2] Open the session the first time and point the request at it
            if (request.session == null) throw new AIAnthropicAgentRequestBuilderException('The request has no session to keep the agent session in.');
            if (request.session.id == null) openSession(request);

            Map<String, Object> lastMessage = request.messages[request.messages.size() - 1];
            Object lastContent = lastMessage.get(AIAssistApplicationConstants.CANONICAL_CONTENT_KEY);
            List<Object> events = new List<Object>();

            if (lastContent instanceof List<Object>) {

                // [3] The model asked for tools last pass, so answer each call with its result
                for (Object contentBlockObject : (List<Object>) lastContent) {

                    Map<String, Object> contentBlock = (Map<String, Object>) contentBlockObject;

                    if (contentBlock.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_BLOCK_TYPE) != AIAssistApplicationConstants.ANTHROPIC_BLOCK_TYPE_TOOL_RESULT) continue;

                    events.add(new Map<String, Object>{
                        AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_TYPE => AIAssistApplicationConstants.ANTHROPIC_AGENT_EVENT_USER_TOOL_RESULT,
                        AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_TOOL_USE_ID => contentBlock.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_RESULT_ID),
                        AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_CONTENT => buildTextContent(String.valueOf(contentBlock.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_CONTENT)))
                    });
                }

                if (events.isEmpty()) throw new AIAnthropicAgentRequestBuilderException('The last message holds no tool results to send to the agent.');

            } else {

                // [4] A new user message: add the system prompt as context for this session first, since the agent's own prompt is fixed on Anthropic's side
                if (String.isNotBlank(request.systemPromptText)) {

                    events.add(new Map<String, Object>{
                        AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_TYPE => AIAssistApplicationConstants.ANTHROPIC_AGENT_EVENT_SYSTEM_MESSAGE,
                        AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_CONTENT => buildTextContent(request.systemPromptText)
                    });
                }

                // [5] Add the user message. A continued session already holds the earlier conversation, so only a new session gets it written into the message
                events.add(new Map<String, Object>{
                    AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_TYPE => AIAssistApplicationConstants.ANTHROPIC_AGENT_EVENT_USER_MESSAGE,
                    AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_CONTENT => buildTextContent(buildUserText(request.messages, request.session.isResumed))
                });
            }

            // [6] Return the events body
            return new Map<String, Object>{AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_EVENTS => events};

        } catch (Exception ex) {

            if (ex instanceof AIAnthropicAgentRequestBuilderException) throw ex;
            throw new AIAnthropicAgentRequestBuilderException('Failed to build the Anthropic Agent request body: ' + ex.getMessage(), ex);
        }
    }

    // Sends one callout to the Agent API with its version and beta headers. The Named Credential adds the API key. Also used by AIAnthropicAgentResponseHandler.
    public static HttpResponse sendRequest(String endpoint, String method, String body, Integer timeoutMilliseconds) {

        // [1] Build the request
        HttpRequest agentRequest = new HttpRequest();
        agentRequest.setEndpoint(endpoint);
        agentRequest.setMethod(method);
        agentRequest.setHeader(AIAssistApplicationConstants.HTTP_HEADER_CONTENT_TYPE, AIAssistApplicationConstants.CONTENT_TYPE_JSON);
        agentRequest.setHeader(AIAssistApplicationConstants.ANTHROPIC_AGENT_VERSION_HEADER_NAME, AIAssistApplicationConstants.ANTHROPIC_AGENT_VERSION_HEADER_VALUE);
        agentRequest.setHeader(AIAssistApplicationConstants.ANTHROPIC_AGENT_BETA_HEADER_NAME, AIAssistApplicationConstants.ANTHROPIC_AGENT_BETA_HEADER_VALUE);
        agentRequest.setTimeout(Math.max(AIAssistApplicationConstants.ANTHROPIC_AGENT_MIN_CALLOUT_MILLISECONDS, Math.min(AIAssistApplicationConstants.ANTHROPIC_AGENT_MAX_CALLOUT_MILLISECONDS, timeoutMilliseconds == null ? AIAssistApplicationConstants.ANTHROPIC_AGENT_MAX_CALLOUT_MILLISECONDS : timeoutMilliseconds)));

        if (body != null) agentRequest.setBody(body);

        // [2] Send it
        return new Http().send(agentRequest);
    }

    // Continues the conversation's saved session when it can, otherwise starts a new one. Called once per turn, because the later passes find the session already open.
    private static void openSession(AIProvider.Request request) {

        // [1] Continue the saved session if Anthropic still has it open for this agent and environment
        if (String.isNotBlank(request.session.resumeId) && isSessionUsable(request)) {

            attachSession(request, request.session.resumeId);
            request.session.isResumed = true;

            return;
        }

        // [2] Otherwise start a new one, which holds none of the earlier conversation
        startSession(request);
    }

    // True when the saved session still exists, is not ended or archived, and belongs to this agent and environment. Anything else, including an answer that cannot be read, means start a new session: the conversation is then written into it again, so nothing is lost.
    // Not yet proven against a live session, so confirm on the first run: (1) GET /v1/sessions/{id} returns status, archived_at, agent.id and environment_id as read here (a wrong name only means every turn starts a new session); (2) a second user.message sent to an idle session is answered with the earlier turns remembered; (3) a system.message sent on every turn of the same session is accepted.
    private static Boolean isSessionUsable(AIProvider.Request request) {

        // [1] Without an agent and an environment there is nothing to compare the saved session with
        if (String.isBlank(request.modelIdentifier) || String.isBlank(request.environmentId)) return false;

        // [2] Ask Anthropic about the saved session
        HttpResponse sessionResponse = sendRequest(request.endpoint + '/' + request.session.resumeId, METHOD_GET, null, request.maxWaitMilliseconds);

        if (sessionResponse.getStatusCode() < 200 || sessionResponse.getStatusCode() > 299) return false;

        Object parsedBody;

        try {

            parsedBody = JSON.deserializeUntyped(sessionResponse.getBody());

        } catch (Exception ex) {

            return false;
        }

        if (!(parsedBody instanceof Map<String, Object>)) return false;

        Map<String, Object> savedSession = (Map<String, Object>) parsedBody;

        // [3] An ended or archived session cannot take another message
        if (savedSession.get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_STATUS) == AIAssistApplicationConstants.ANTHROPIC_AGENT_SESSION_STATUS_TERMINATED || savedSession.get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_ARCHIVED_AT) != null) return false;

        // [4] A session made for another agent or environment would answer as that agent, so it is not continued
        Object savedAgent = savedSession.get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_AGENT);
        Object savedAgentId = savedAgent instanceof Map<String, Object> ? ((Map<String, Object>) savedAgent).get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_ID) : null;
        Object savedEnvironmentId = savedSession.get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_ENVIRONMENT_ID);

        if (savedAgentId != null && savedAgentId != request.modelIdentifier) return false;
        if (savedEnvironmentId != null && savedEnvironmentId != request.environmentId) return false;

        return true;
    }

    // Starts a session for the agent (the Model Identifier) in the environment, and records on the request's session where to send events and which headers to send them with.
    private static void startSession(AIProvider.Request request) {

        // [1] A session cannot be started without an agent and an environment
        if (String.isBlank(request.modelIdentifier) || String.isBlank(request.environmentId)) throw new AIAnthropicAgentRequestBuilderException('The agent id (Model Identifier) and the Environment Id are both needed to start an Anthropic Agent session.');

        // [2] Ask Anthropic for a session
        Map<String, Object> sessionBody = new Map<String, Object>{
            AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_AGENT => new Map<String, Object>{AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_TYPE => AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_AGENT_TYPE, AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_ID => request.modelIdentifier},
            AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_ENVIRONMENT_ID => request.environmentId
        };
        HttpResponse sessionResponse = sendRequest(request.endpoint, AIAssistApplicationConstants.HTTP_METHOD_POST, JSON.serialize(sessionBody), request.maxWaitMilliseconds);

        // [3] Anthropic refused, so say why
        if (sessionResponse.getStatusCode() < 200 || sessionResponse.getStatusCode() > 299) throw new AIAnthropicAgentRequestBuilderException('Anthropic did not start an agent session (HTTP ' + sessionResponse.getStatusCode() + '): ' + String.valueOf(sessionResponse.getBody()).abbreviate(500));

        String sessionId = (String) ((Map<String, Object>) JSON.deserializeUntyped(sessionResponse.getBody())).get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_ID);

        if (String.isBlank(sessionId)) throw new AIAnthropicAgentRequestBuilderException('Anthropic did not return a session id.');

        // [4] Remember the session
        attachSession(request, sessionId);
    }

    // Records the session on the request: events go to it from now on, with the beta header the model configuration cannot carry.
    private static void attachSession(AIProvider.Request request, String sessionId) {

        // [1] Remember the session and where its events go
        request.session.id = sessionId;
        request.session.endpoint = request.endpoint + '/' + sessionId + AIAssistApplicationConstants.ANTHROPIC_AGENT_EVENTS_PATH;

        // [2] Add the beta header every request to it needs
        request.session.headers.put(AIAssistApplicationConstants.ANTHROPIC_AGENT_BETA_HEADER_NAME, AIAssistApplicationConstants.ANTHROPIC_AGENT_BETA_HEADER_VALUE);
    }

    // The text of the last message, with every earlier message written out above it when there are any and the session does not already hold them.
    private static String buildUserText(List<Map<String, Object>> messages, Boolean sessionHoldsEarlierMessages) {

        // [1] The last message is the one being answered
        String latestText = String.valueOf(messages[messages.size() - 1].get(AIAssistApplicationConstants.CANONICAL_CONTENT_KEY));

        // [2] With nothing before it, or with the session already holding what came before, send it as it is
        if (messages.size() == 1 || sessionHoldsEarlierMessages) return latestText;

        // [3] Write each earlier message on its own line, labelled with who said it
        List<String> lines = new List<String>{AIAssistApplicationConstants.ANTHROPIC_AGENT_TRANSCRIPT_HEADING};

        for (Integer messageIndex = 0; messageIndex < messages.size() - 1; messageIndex++) {

            Map<String, Object> message = messages[messageIndex];
            Boolean isUser = message.get(AIAssistApplicationConstants.CANONICAL_ROLE_KEY) == AIAssistApplicationConstants.CANONICAL_ROLE_USER;

            lines.add((isUser ? AIAssistApplicationConstants.ANTHROPIC_AGENT_TRANSCRIPT_USER : AIAssistApplicationConstants.ANTHROPIC_AGENT_TRANSCRIPT_ASSISTANT) + String.valueOf(message.get(AIAssistApplicationConstants.CANONICAL_CONTENT_KEY)));
        }

        // [4] Put the latest message last
        lines.add('');
        lines.add(AIAssistApplicationConstants.ANTHROPIC_AGENT_TRANSCRIPT_LATEST);
        lines.add(latestText);

        return String.join(lines, '\n');
    }

    // Wraps text in the content list every event uses.
    private static List<Object> buildTextContent(String text) {

        // [1] Return one text item
        return new List<Object>{new Map<String, Object>{
            AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_TYPE => AIAssistApplicationConstants.ANTHROPIC_AGENT_CONTENT_TYPE_TEXT,
            AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_TEXT => text
        }};
    }
}
