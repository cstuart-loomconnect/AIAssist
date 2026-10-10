/*
Class Name: AIDataSourceRequestTest

=================================================================
=================================================================

Description: Testing utility for AIDataSourceRequest: a request can be built from outside the class, as a subscriber's test must to call its own data source.

=================================================================
=================================================================
Applicable Classes:

AIDataSourceRequest: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIDataSourceRequestTest {

    // testScenario1: A request is built with the no-argument constructor and values are set on it -> it starts with an empty input map and keeps what is set.

    private static final String DATA_SOURCE_NAME = 'Example';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Declare what the test reads back
        AIDataSourceRequest request;
        Integer inputsAtStart;

        // [2] Build a request with the no-argument constructor and set values on it
        Test.startTest();
            request = new AIDataSourceRequest();
            inputsAtStart = request.inputParameters.size();
            request.recordId = UserInfo.getUserId();
            request.userId = UserInfo.getUserId();
            request.dataSourceName = DATA_SOURCE_NAME;
            request.inputParameters.put('x', 1);
        Test.stopTest();

        // [3] Check the request starts empty and keeps what was set
        Assert.areEqual(0, inputsAtStart, 'The input map is never null.');
        Assert.areEqual(UserInfo.getUserId(), request.recordId, 'Record kept.');
        Assert.areEqual(UserInfo.getUserId(), request.userId, 'User kept.');
        Assert.areEqual(DATA_SOURCE_NAME, request.dataSourceName, 'Name kept.');
        Assert.areEqual(1, request.inputParameters.get('x'), 'Input kept.');
    }
}
