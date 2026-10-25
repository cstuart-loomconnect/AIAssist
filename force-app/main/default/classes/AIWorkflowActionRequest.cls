/*
Class Name: AIWorkflowActionRequest

=================================================================
=================================================================

Description: What the package hands to an Apex Workflow Action (IAIWorkflowActionExecutor.execute).

Step 1: The dispatcher builds one request for the action it is about to run
Step 2: The request carries the record, the declared inputs and who is asking
Step 3: The Apex class reads it in execute

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

global without sharing class AIWorkflowActionRequest {

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

    // Explicit and global, so a subscriber's test can build a request to call its own class with. The implicit constructor of a global class is not visible outside the package.
    global AIWorkflowActionRequest() {}
}
