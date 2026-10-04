/*
Class Name: IAIWorkflowActionExecutor

=================================================================
=================================================================

Description: Contract for the Apex class named in AIWorkflowAction__c.ApexClassName__c when the action type is
Apex. The class performs the action and returns an AIWorkflowActionResponse whose message is shown to the user as text. The AIWorkflowActionRequest carries the record, the declared inputs and who is asking.

The class runs in the signed-in user's transaction, in system context and in the sharing mode it declares for itself, so it should be
"with sharing" and use user mode for its own queries and DML. The dispatcher checks that the class
implements this interface before it is instantiated.

Global: this is part of the package's permanent API. Once a version is released the method cannot
be changed or removed, only added to.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Global, so a class in the subscriber's org can implement it. A public interface is visible only inside the package's namespace.
3.0          Chandler Stuart          One request and one response class instead of loose arguments and an Object, so what is passed in and returned can grow after release.
*/

global interface IAIWorkflowActionExecutor {
  AIWorkflowActionResponse execute(AIWorkflowActionRequest request);
}
