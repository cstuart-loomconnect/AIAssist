/*
Class Name: AIDataSourceRequest

=================================================================
=================================================================

Description: What the package hands to an Apex data source (IAIDataSourceExecutor.execute). A request
class instead of loose arguments, so the package can pass more in a later version without breaking a
class a subscriber has already written: a new global field is invisible to code that ignores it.

Global: part of the package's permanent API. After release a field can be added, never changed or
removed.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

global class AIDataSourceRequest {
  // The record the conversation is about. Null for an unbound data source.
  global Id recordId;
  // Values the model supplied for the parameters the data source declares.
  global Map<String, Object> inputParameters = new Map<String, Object>();
  // The conversation this request is part of, and the agent and user it is for.
  global Id conversationId;
  global Id agentId;
  global Id userId;
  // The Developer Name of the data source being run.
  global String dataSourceName;
  // The most rows the data source is configured to return; null when no cap is set. The package enforces it again on what comes back.
  global Integer maxRows;
}
