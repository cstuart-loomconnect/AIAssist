/*
Class Name: AIModelsConnectionTestServiceTest

=================================================================
=================================================================

Description: Testing utility for AIModelsConnectionTestService: the connection test of a model.

=================================================================
=================================================================
Applicable Classes:

AIModelsConnectionTestService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIModelsConnectionTestServiceTest {

    // testScenario1: An Anthropic model is tested and the provider replies -> the test passes with the status, the tokens and a time, and nothing is saved.
    // testScenario2: An Anthropic Agent model is tested and the agent replies -> the test passes.
    // testScenario3: The provider refuses the call -> the test fails with the status and the reason, and no provider text is returned.
    // testScenario4: A model with an unsupported provider is tested -> the test fails with a reason and no callout is made.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Anthropic model that is not saved, and install a provider that answers
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

            // [2] Run the test
            Test.startTest();
                AIModelsDataStructure.TestResult result = AIModelsConnectionTestService.runTest(model);
            Test.stopTest();

            // [3] Count what was saved
            Integer savedCount = [SELECT COUNT() FROM AIModelConfiguration__c];

            // [4] Check the outcome
            Assert.isTrue(result.isSuccessful, 'The test should pass when the provider replies.');
            Assert.areEqual(200, result.httpStatusCode, 'The status of the reply should be reported.');
            Assert.areEqual(10, result.inputTokens, 'The input tokens should be reported.');
            Assert.areEqual(5, result.outputTokens, 'The output tokens should be reported.');
            Assert.isNotNull(result.latencyMilliseconds, 'The time the reply took should be reported.');
            Assert.isNull(result.failureReason, 'A passing test should have no failure reason.');
            Assert.areEqual(model.NamedCredential__c, result.namedCredential, 'The named credential tested should be reported.');
            Assert.areEqual(1, AIAssistTestProviderMock.callCount, 'One callout should be made.');
            Assert.areEqual(0, savedCount, 'The test should not save the model.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Anthropic Agent model that is not saved, and install an agent that answers
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT;
            model.ApiPath__c = '/v1/sessions';
            model.EnvironmentId__c = 'env_1';
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_AGENT);

            // [2] Run the test
            Test.startTest();
                AIModelsDataStructure.TestResult result = AIModelsConnectionTestService.runTest(model);
            Test.stopTest();

            // [3] Check the outcome
            Assert.isTrue(result.isSuccessful, 'The test should pass when the agent replies.');
            Assert.isNull(result.failureReason, 'A passing test should have no failure reason.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a model that is not saved, and install a provider that refuses every call
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_FAIL);

            // [2] Run the test
            Test.startTest();
                AIModelsDataStructure.TestResult result = AIModelsConnectionTestService.runTest(model);
            Test.stopTest();

            // [3] Check the outcome
            Assert.isFalse(result.isSuccessful, 'The test should fail when the provider refuses the call.');
            Assert.areEqual(400, result.httpStatusCode, 'The status the provider sent should be reported.');
            Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR, result.failureReason, 'The reason should be a provider error.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a model with a provider this package does not know
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = null;
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

            // [2] Run the test
            Test.startTest();
                AIModelsDataStructure.TestResult result = AIModelsConnectionTestService.runTest(model);
            Test.stopTest();

            // [3] Check the outcome
            Assert.isFalse(result.isSuccessful, 'A model with no usable provider should fail the test.');
            Assert.isNotNull(result.failureReason, 'A failed test should always have a reason.');
            Assert.areEqual(0, AIAssistTestProviderMock.callCount, 'No callout should be made.');
        }
    }
}
