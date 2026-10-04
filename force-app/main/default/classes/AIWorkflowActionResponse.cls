/*
Class Name: AIWorkflowActionResponse

=================================================================
=================================================================

Description: What an Apex Workflow Action (IAIWorkflowActionExecutor.execute) returns. message is shown to
the user as text; it must not contain anything the user may not see.

Global: part of the package's permanent API. After release a field can be added, never changed or
removed.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

global class AIWorkflowActionResponse {
  global String message;

  global AIWorkflowActionResponse() {
  }

  global AIWorkflowActionResponse(String message) {
    this.message = message;
  }
}
