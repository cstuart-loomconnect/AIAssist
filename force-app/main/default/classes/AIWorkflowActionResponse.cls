/*
Class Name: AIWorkflowActionResponse

=================================================================
=================================================================

Description: What an Apex Workflow Action (IAIWorkflowActionExecutor.execute) returns.

Step 1: The Apex class does its work and builds a response
Step 2: The response message is the text shown to the user
Step 3: The dispatcher returns that message to the chat

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

global without sharing class AIWorkflowActionResponse {

    global String message;

    global AIWorkflowActionResponse() {}

    global AIWorkflowActionResponse(String message) {
        this.message = message;
    }
}
