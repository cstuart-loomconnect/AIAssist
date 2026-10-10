/*
Class Name: AIWorkflowActionRequestTest

=================================================================
=================================================================

Description: Testing utility for AIWorkflowActionRequest: a request can be built from outside the class, as a subscriber's test must to call its own action.

=================================================================
=================================================================
Applicable Classes:

AIWorkflowActionRequest: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIWorkflowActionRequestTest {

    // testScenario1: A request built with the no-argument constructor starts with an empty input map and carries what is set on it -> empty map at start, every value kept.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Prepare the request and the count to capture
        AIWorkflowActionRequest request;
        Integer inputsAtStart;

        // [2] Build the request and set its values
        Test.startTest();
            request = new AIWorkflowActionRequest();
            inputsAtStart = request.inputParameters.size();

            request.recordId = UserInfo.getUserId();
            request.userId = UserInfo.getUserId();
            request.actionName = 'Example';
            request.inputParameters.put('x', 1);
        Test.stopTest();

        // [3] Check the input map started empty and every value was kept
        Assert.areEqual(0, inputsAtStart, 'The input map is never null.');

        Assert.areEqual(UserInfo.getUserId(), request.recordId, 'Record kept.');
        Assert.areEqual(UserInfo.getUserId(), request.userId, 'User kept.');
        Assert.areEqual('Example', request.actionName, 'Name kept.');
        Assert.areEqual(1, request.inputParameters.get('x'), 'Input kept.');
    }
}
