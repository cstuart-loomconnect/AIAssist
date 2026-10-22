/*
Class Name: IAIWorkflowActionInputDescriber

=================================================================
=================================================================

Description: Optional contract for an Apex class that is also an IAIWorkflowActionExecutor, so the AI Tools tab can fill in its inputs for the administrator. It is part of the package's permanent API: after release the method cannot be changed or removed, only added to.

Step 1: The AI Tools tab lists the classes that implement IAIWorkflowActionExecutor
Step 2: For a class that also implements this interface, the tab calls describeInputs
Step 3: The tab reads the input schema it gets back and pre-fills the Inputs step

The text returned is a JSON Schema object, the same shape as AIWorkflowAction__c.InputSchema__c. A top-level "x-callouts" text or list says what the class does that cannot be rolled back, such as sending email.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

global interface IAIWorkflowActionInputDescriber {

    String describeInputs();
}
