/*
Class Name: IAIWorkflowActionExecutor

=================================================================
=================================================================

Description: Contract for the Apex class named in AIWorkflowAction__c.ApexClassName__c when the action type is
Apex. The class performs the action and returns its result, which is shown to the user as text.

The class runs as the signed-in user, in the sharing mode it declares for itself, so it should be
"with sharing" and use user mode for its own queries and DML. The dispatcher checks that the class
implements this interface before it is instantiated.

Global: this is part of the package's permanent API. Once a version is released the method cannot
be changed or removed, only added to.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Global, so a class in the subscriber's org can implement it. A public interface is visible only inside the package's namespace.
*/

global interface IAIWorkflowActionExecutor {
  Object execute(Id recordId, Map<String, Object> inputParameters);
}
