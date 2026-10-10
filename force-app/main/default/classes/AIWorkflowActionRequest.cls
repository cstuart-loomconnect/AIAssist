/*
Class Name: AIWorkflowActionRequest

=================================================================
=================================================================

Description: What the package hands to an Apex Workflow Action (IAIWorkflowActionExecutor.execute). A
request class instead of loose arguments, so the package can pass more in a later version without
breaking a class a subscriber has already written.

inputParameters holds only the inputs the action declares in its input schema; anything else the browser
sent has already been dropped.

Global: part of the package's permanent API. After release a field can be added, never changed or
removed.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Explicit global no-argument constructor.
*/

global class AIWorkflowActionRequest {
  // Explicit and global, so a subscriber's test can build a request to call its own class with. The implicit constructor of a global class is not visible outside the package.
  global AIWorkflowActionRequest() {
  }

  // The record the conversation is about. Null when the action does not work on a record.
  global Id recordId;
  global Map<String, Object> inputParameters = new Map<String, Object>();
  global Id conversationId;
  global Id agentId;
  global Id userId;
  // The Developer Name of the action being run.
  global String actionName;
  // Whether the user confirmed it; always true for an action that requires confirmation.
  global Boolean isConfirmed = false;
}
