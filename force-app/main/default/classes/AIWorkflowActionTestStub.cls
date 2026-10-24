/*
Class Name: AIWorkflowActionTestStub

=================================================================
=================================================================

Description: A small Apex workflow action to try the AI Tools tab with: it says hello, can create an Account to show a roll back, and can fail on purpose.

Step 1: The AI Tools tab finds this class as an executor
Step 2: The tab asks it to describe its inputs: the open record, a note, and two switches
Step 3: Running it returns a message, creating an Account first when asked, or failing when asked

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public class AIWorkflowActionTestStub implements IAIWorkflowActionExecutor, IAIWorkflowActionInputDescriber {

    public class AIWorkflowActionTestStubException extends Exception {}

    public AIWorkflowActionResponse execute(AIWorkflowActionRequest request) {

        // [1] Read the inputs
        Map<String, Object> inputs = request.inputParameters == null ? new Map<String, Object>() : request.inputParameters;
        String note = inputs.get('note') == null ? 'no note' : String.valueOf(inputs.get('note'));
        Boolean shouldCreateAccount = inputs.get('createAccount') == true;
        Boolean shouldFail = inputs.get('shouldFail') == true;

        // [2] Fail on purpose, to see how a failed test looks
        if (shouldFail) throw new AIWorkflowActionTestStubException('The test action was asked to fail.');

        // [3] Create an Account, to see what a roll back undoes
        String createdText = NO_ACCOUNT;

        if (shouldCreateAccount) {

            Account testAccount = new Account(Name = 'AI Workflow Test ' + note);
            insert testAccount;
            createdText = 'Created Account ' + testAccount.Id + '.';
        }

        // [4] Say what happened
        return new AIWorkflowActionResponse('Hello from the test action. Record: ' + request.recordId + '. Note: ' + note + '. ' + createdText);
    }

    public String describeInputs() {

        return '{"type":"object","properties":{"recordId":{"type":"string","x-source":"page"},"note":{"type":"string","description":"Any text, which the action repeats back."},"createAccount":{"type":"boolean","description":"Creates an Account, so a roll back has something to undo."},"shouldFail":{"type":"boolean","description":"Makes the action fail on purpose."}},"required":[]}';
    }

    private static final String NO_ACCOUNT = 'No Account created.';
}
