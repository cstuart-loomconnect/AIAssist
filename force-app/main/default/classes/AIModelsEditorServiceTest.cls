/*
Class Name: AIModelsEditorServiceTest

=================================================================
=================================================================

Description: Testing utility for AIModelsEditorService: reading, testing, saving and switching off models.

=================================================================
=================================================================
Applicable Classes:

AIModelsEditorService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIModelsEditorServiceTest {

    // testScenario1: A manager reads the page with an active model, an inactive model and an agent -> active models come first, the agent is counted, and the three providers are offered with their presets.
    // testScenario2: A manager saves a new model that is switched off -> it is saved with the provider's API path when none was typed, and no test is run.
    // testScenario3: A manager saves a new model that is switched on and the provider replies -> the test passes and the model is saved active.
    // testScenario4: A manager saves a new model that is switched on and the provider refuses -> the model is saved switched off and the activation is refused.
    // testScenario5: A manager changes the connection of a live model and the provider refuses -> nothing is saved and the live model keeps its connection.
    // testScenario6: A manager saves values the object would refuse -> each is refused with its own message.
    // testScenario7: A manager switches off a model that active agents use by saving it -> the save is refused.
    // testScenario8: A manager tests a connection from the form, then tests an invalid one -> the first reports the result and saves nothing, the second is refused.
    // testScenario9: A manager reads the switch off options and switches the model off -> the agents move to the chosen model and the model is switched off.
    // testScenario10: A manager switches a model off with an agent that has no place to go, and with a place that is not active -> each is refused and nothing changes.
    // testScenario11: A user without the Manage Settings permission calls the service -> the access label is shown.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an inactive model, an active model and an active agent that uses the active one
            AIModelConfiguration__c inactiveModel = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            inactiveModel.Name = 'AAA Inactive Model';
            inactiveModel.IsActive__c = false;
            insert inactiveModel;
            AIModelConfiguration__c activeModel = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAssistTestDataFactory.createAIAgents(1, activeModel.Id, true);

            // [2] Read the page
            Test.startTest();
                AIModelsDataStructure.ModelsPage page = AIModelsEditorService.getModelsPage();
            Test.stopTest();

            // [3] Find the providers by name
            Map<String, AIModelsDataStructure.ProviderOption> optionByProvider = new Map<String, AIModelsDataStructure.ProviderOption>();

            for (AIModelsDataStructure.ProviderOption option : page.providers) {

                optionByProvider.put(option.provider, option);
            }

            // [4] Check the outcome
            Assert.areEqual(2, page.models.size(), 'Both models should be listed.');
            Assert.areEqual(activeModel.Id, page.models[0].modelId, 'The active model should come first.');
            Assert.areEqual(1, page.models[0].agentCount, 'The active agent should be counted.');
            Assert.areEqual(0, page.models[1].agentCount, 'A model no agent uses should have a count of zero.');
            Assert.areEqual(3, page.providers.size(), 'The three providers should be offered.');
            Assert.areEqual('/v1/messages', optionByProvider.get(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC).apiPath, 'Anthropic should start from the Messages API path.');
            Assert.areEqual(1, optionByProvider.get(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC).maxTemperature, 'Anthropic should accept a temperature up to 1.');
            Assert.areEqual(2, optionByProvider.get(AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI).maxTemperature, 'OpenAI should accept a temperature up to 2.');
            Assert.isTrue(optionByProvider.get(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT).needsEnvironmentId, 'Anthropic Agent should need an environment ID.');
            Assert.isFalse(optionByProvider.get(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC).needsEnvironmentId, 'Anthropic should not need an environment ID.');
            Assert.isNotNull(page.credentials, 'The named credential list should never be null.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a new model that is switched off and has no API path
            AIModelsDataStructure.ModelView view = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI, false);
            view.apiPath = '  ';
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

            // [2] Save it
            Test.startTest();
                AIModelsDataStructure.SaveResult result = AIModelsEditorService.saveModel(view);
            Test.stopTest();

            // [3] Read the saved model
            AIModelConfiguration__c saved = [SELECT Name, ApiPath__c, IsActive__c, Temperature__c FROM AIModelConfiguration__c WHERE Id = :result.model.modelId];

            // [4] Check the outcome
            Assert.isTrue(result.isSaved, 'The model should be saved.');
            Assert.isFalse(result.isActivationRefused, 'Nothing was refused.');
            Assert.isNull(result.testResult, 'A model that stays off should not be tested.');
            Assert.areEqual(0, AIAssistTestProviderMock.callCount, 'No callout should be made.');
            Assert.areEqual('/v1/chat/completions', saved.ApiPath__c, 'A blank API path should take the provider\'s own.');
            Assert.isFalse(saved.IsActive__c, 'The model should stay off.');
            Assert.areEqual(view.modelName, result.model.modelName, 'The saved model should be returned.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a new model that is switched on, and install a provider that answers
            AIModelsDataStructure.ModelView view = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, true);
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

            // [2] Save it
            Test.startTest();
                AIModelsDataStructure.SaveResult result = AIModelsEditorService.saveModel(view);
            Test.stopTest();

            // [3] Read the saved model
            AIModelConfiguration__c saved = [SELECT IsActive__c FROM AIModelConfiguration__c WHERE Id = :result.model.modelId];

            // [4] Check the outcome
            Assert.isTrue(result.isSaved, 'The model should be saved.');
            Assert.isTrue(result.testResult.isSuccessful, 'The test should pass.');
            Assert.isTrue(saved.IsActive__c, 'The model should be active after a passing test.');
            Assert.isTrue(result.model.isActive, 'The returned model should be active.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a new model that is switched on, and install a provider that refuses
            AIModelsDataStructure.ModelView view = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, true);
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_FAIL);

            // [2] Save it
            Test.startTest();
                AIModelsDataStructure.SaveResult result = AIModelsEditorService.saveModel(view);
            Test.stopTest();

            // [3] Read the saved model
            AIModelConfiguration__c saved = [SELECT IsActive__c FROM AIModelConfiguration__c WHERE Id = :result.model.modelId];

            // [4] Check the outcome
            Assert.isTrue(result.isSaved, 'The model should still be saved.');
            Assert.isTrue(result.isActivationRefused, 'The activation should be refused.');
            Assert.isFalse(result.testResult.isSuccessful, 'The test should fail.');
            Assert.isFalse(saved.IsActive__c, 'The model should be saved switched off.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a live model and change its model ID in the form
            AIModelConfiguration__c liveModel = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIModelsDataStructure.ModelView view = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, true);
            view.modelId = liveModel.Id;
            view.modelName = liveModel.Name;
            view.modelIdentifier = 'a-model-that-does-not-exist';
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_FAIL);

            // [2] Save it
            Test.startTest();
                AIModelsDataStructure.SaveResult result = AIModelsEditorService.saveModel(view);
            Test.stopTest();

            // [3] Read the model again
            AIModelConfiguration__c saved = [SELECT ModelIdentifier__c, IsActive__c FROM AIModelConfiguration__c WHERE Id = :liveModel.Id];

            // [4] Check the outcome
            Assert.isFalse(result.isSaved, 'Nothing should be saved when a live model fails its test.');
            Assert.isFalse(result.testResult.isSuccessful, 'The test should fail.');
            Assert.areEqual('test-model', saved.ModelIdentifier__c, 'The live model should keep its model ID.');
            Assert.isTrue(saved.IsActive__c, 'The live model should stay active.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build values that are each wrong in one way
            AIModelsDataStructure.ModelView noName = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, false);
            noName.modelName = ' ';
            AIModelsDataStructure.ModelView noModel = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, false);
            noModel.modelIdentifier = null;
            AIModelsDataStructure.ModelView noCredential = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, false);
            noCredential.namedCredential = '';
            AIModelsDataStructure.ModelView badCredential = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, false);
            badCredential.namedCredential = 'not a credential';
            AIModelsDataStructure.ModelView badProvider = AIAssistTestDataFactory.createAIModelView('Unknown', false);
            AIModelsDataStructure.ModelView noEnvironment = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT, false);
            noEnvironment.environmentId = null;
            AIModelsDataStructure.ModelView badPath = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, false);
            badPath.apiPath = 'https://example.com/v1';
            AIModelsDataStructure.ModelView badTokens = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, false);
            badTokens.maxOutputTokens = 0;
            AIModelsDataStructure.ModelView decimalTokens = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, false);
            decimalTokens.maxOutputTokens = 10.5;
            AIModelsDataStructure.ModelView hotAnthropic = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, false);
            hotAnthropic.temperature = 1.5;
            AIModelsDataStructure.ModelView hotOpenAi = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI, false);
            hotOpenAi.temperature = 2.5;
            List<AIModelsDataStructure.ModelView> views = new List<AIModelsDataStructure.ModelView>{noName, noModel, noCredential, badCredential, badProvider, noEnvironment, badPath, badTokens, decimalTokens, hotAnthropic, hotOpenAi};
            List<String> refusals = new List<String>();

            // [2] Save each one and keep the message
            Test.startTest();
                for (AIModelsDataStructure.ModelView view : views) {

                    try {

                        AIModelsEditorService.saveModel(view);
                    } catch (AIModelsEditorService.AIModelsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(11, refusals.size(), 'Every wrong value should be refused.');
            Assert.areEqual(Label.AI_Models_Error_Name_Required, refusals[0], 'A missing name should be refused.');
            Assert.areEqual(Label.AI_Models_Error_Model_Required, refusals[1], 'A missing model ID should be refused.');
            Assert.areEqual(Label.AI_Models_Error_Credential_Required, refusals[2], 'A missing credential should be refused.');
            Assert.areEqual(Label.AI_Models_Error_Credential_Format, refusals[3], 'A credential of the wrong shape should be refused.');
            Assert.areEqual(Label.AI_Models_Error_Provider_Invalid, refusals[4], 'An unknown provider should be refused.');
            Assert.areEqual(Label.AI_Models_Error_Environment_Required, refusals[5], 'A missing environment ID should be refused for Anthropic Agent.');
            Assert.areEqual(Label.AI_Models_Error_Path_Format, refusals[6], 'An API path with a host should be refused.');
            Assert.areEqual(Label.AI_Models_Error_Tokens_Invalid, refusals[7], 'Zero tokens should be refused.');
            Assert.areEqual(Label.AI_Models_Error_Tokens_Invalid, refusals[8], 'A fraction of a token should be refused.');
            Assert.areEqual(Label.AI_Models_Error_Temperature_Invalid, refusals[9], 'A temperature over 1 should be refused for Anthropic.');
            Assert.areEqual(Label.AI_Models_Error_Temperature_Invalid, refusals[10], 'A temperature over 2 should be refused.');
            Assert.areEqual(0, [SELECT COUNT() FROM AIModelConfiguration__c], 'Nothing should be saved.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a live model that an active agent uses, and a form that switches it off
            AIModelConfiguration__c liveModel = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAssistTestDataFactory.createAIAgents(1, liveModel.Id, true);
            AIModelsDataStructure.ModelView view = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, false);
            view.modelId = liveModel.Id;
            view.modelName = liveModel.Name;
            String refusal;

            // [2] Save it
            Test.startTest();
                try {

                    AIModelsEditorService.saveModel(view);
                } catch (AIModelsEditorService.AIModelsEditorServiceException ex) {

                    refusal = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(Label.AI_Models_Error_Switch_Off_Has_Agents, refusal, 'Saving a model off while agents use it should be refused.');
            Assert.isTrue([SELECT IsActive__c FROM AIModelConfiguration__c WHERE Id = :liveModel.Id].IsActive__c, 'The model should stay active.');
        }
    }

    @IsTest static void testScenario8() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a valid form and a form with no model ID, and install a provider that answers
            AIModelsDataStructure.ModelView view = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, true);
            AIModelsDataStructure.ModelView invalidView = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, true);
            invalidView.modelIdentifier = '';
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);
            String refusal;

            // [2] Test both
            Test.startTest();
                AIModelsDataStructure.TestResult result = AIModelsEditorService.testConnection(view);

                try {

                    AIModelsEditorService.testConnection(invalidView);
                } catch (AIModelsEditorService.AIModelsEditorServiceException ex) {

                    refusal = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.isTrue(result.isSuccessful, 'The test of a valid form should pass.');
            Assert.areEqual(0, [SELECT COUNT() FROM AIModelConfiguration__c], 'Testing should not save anything.');
            Assert.areEqual(Label.AI_Models_Error_Model_Required, refusal, 'A form with no model ID should be refused.');
            Assert.areEqual(1, AIAssistTestProviderMock.callCount, 'Only the valid form should call the provider.');
        }
    }

    @IsTest static void testScenario9() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a live model with two active agents, one other active model, and a conversation for one agent
            List<AIModelConfiguration__c> models = AIAssistTestDataFactory.createAIModelConfigurations(2, true);
            List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, models[0].Id, true);
            AIAssistTestDataFactory.createAIConversations(agents[0].Id, superUser.Id, 1, true);
            List<AIModelsDataStructure.SwitchOffMove> moves = new List<AIModelsDataStructure.SwitchOffMove>();

            // [2] Read the options, then move both agents and switch the model off
            Test.startTest();
                AIModelsDataStructure.SwitchOffOptions options = AIModelsEditorService.getSwitchOffOptions(models[0].Id);

                for (AIModelsDataStructure.AgentUse agentUse : options.agentUses) {

                    AIModelsDataStructure.SwitchOffMove move = new AIModelsDataStructure.SwitchOffMove();
                    move.agentId = agentUse.agentId;
                    move.newModelId = options.modelOptions[0].modelId;
                    moves.add(move);
                }

                List<AIModelsDataStructure.ModelView> views = AIModelsEditorService.switchOffModel(models[0].Id, moves);
            Test.stopTest();

            // [3] Read the agents and the model again
            Integer movedCount = [SELECT COUNT() FROM AIAgent__c WHERE AIModelConfiguration__c = :models[1].Id];
            Boolean isStillActive = [SELECT IsActive__c FROM AIModelConfiguration__c WHERE Id = :models[0].Id].IsActive__c;
            Integer totalUsers = 0;

            for (AIModelsDataStructure.AgentUse agentUse : options.agentUses) {

                totalUsers += agentUse.userCount;
            }

            // [4] Check the outcome
            Assert.areEqual(2, options.agentUses.size(), 'Both active agents should be listed.');
            Assert.areEqual(1, options.modelOptions.size(), 'Only the other active model should be offered.');
            Assert.areEqual(models[1].Id, options.modelOptions[0].modelId, 'The other active model should be the choice.');
            Assert.areEqual(1, totalUsers, 'The one user who talked to an agent should be counted.');
            Assert.areEqual(2, movedCount, 'Both agents should have moved.');
            Assert.isFalse(isStillActive, 'The model should be switched off.');
            Assert.areEqual(2, views.size(), 'The models should be returned.');
            Assert.areEqual(2, views[0].agentCount, 'The model that took the agents should count them.');
        }
    }

    @IsTest static void testScenario10() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a live model with an agent, another active model and an inactive model
            List<AIModelConfiguration__c> models = AIAssistTestDataFactory.createAIModelConfigurations(2, true);
            AIModelConfiguration__c inactiveModel = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            inactiveModel.IsActive__c = false;
            insert inactiveModel;
            List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(1, models[0].Id, true);
            AIModelsDataStructure.SwitchOffMove moveToInactive = new AIModelsDataStructure.SwitchOffMove();
            moveToInactive.agentId = agents[0].Id;
            moveToInactive.newModelId = inactiveModel.Id;
            List<String> refusals = new List<String>();

            // [2] Switch off with no move, then with a move to a model that is off
            Test.startTest();
                try {

                    AIModelsEditorService.switchOffModel(models[0].Id, null);
                } catch (AIModelsEditorService.AIModelsEditorServiceException ex) {

                    refusals.add(ex.getMessage());
                }

                try {

                    AIModelsEditorService.switchOffModel(models[0].Id, new List<AIModelsDataStructure.SwitchOffMove>{moveToInactive});
                } catch (AIModelsEditorService.AIModelsEditorServiceException ex) {

                    refusals.add(ex.getMessage());
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(2, refusals.size(), 'Both should be refused.');
            Assert.areEqual(Label.AI_Models_Error_Move_Missing, refusals[0], 'An agent with no place to go should be refused.');
            Assert.areEqual(Label.AI_Models_Error_Move_Target_Invalid, refusals[1], 'A model that is off should not be a place to go.');
            Assert.areEqual(models[0].Id, [SELECT AIModelConfiguration__c FROM AIAgent__c WHERE Id = :agents[0].Id].AIModelConfiguration__c, 'The agent should not move.');
            Assert.isTrue([SELECT IsActive__c FROM AIModelConfiguration__c WHERE Id = :models[0].Id].IsActive__c, 'The model should stay active.');
        }
    }

    @IsTest static void testScenario11() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            AIModelsDataStructure.ModelView view = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, false);
            List<String> refusals = new List<String>();

            // [2] Call each method as that user and keep each message
            Test.startTest();
                System.runAs(users[0]) {
                    try {

                        AIModelsEditorService.getModelsPage();
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIModelsEditorService.testConnection(view);
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIModelsEditorService.saveModel(view);
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIModelsEditorService.switchOffModel(null, null);
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(4, refusals.size(), 'Every call should be refused.');

            for (String refusal : refusals) {

                Assert.areEqual(Label.AI_Settings_Error_Access, refusal, 'The access label should be shown.');
            }
        }
    }
}
