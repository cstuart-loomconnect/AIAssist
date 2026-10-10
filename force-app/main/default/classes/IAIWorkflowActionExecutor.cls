/*
Class Name: IAIWorkflowActionExecutor

=================================================================
=================================================================

Description: Contract for the Apex class named in AIWorkflowAction__c.ApexClassName__c when the action type is Apex.

Step 1: The dispatcher checks the class implements this interface before it is instantiated
Step 2: The class runs in the signed-in user's transaction, and is responsible for keeping its own queries and DML within what that user may access
Step 3: The class performs the action and returns an AIWorkflowActionResponse whose message is shown to the user as text

The AIWorkflowActionRequest carries the record, the declared inputs and who is asking.

Global: this is part of the package's permanent API. Once a version is released the method cannot be changed or removed, only added to.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

global interface IAIWorkflowActionExecutor {
  AIWorkflowActionResponse execute(AIWorkflowActionRequest request);
}
