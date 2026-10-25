/*
Class Name: AIModelsEditorService

=================================================================
=================================================================

Description: Reads, tests, saves and switches off the AI Agent Models (AIModelConfiguration__c) behind the AI Agent Models tab.

Step 1: Read every model with how many active agents use it, and the providers and named credentials the form offers
Step 2: Test a connection, and save a model, testing it first when it is being switched on or its connection changed
Step 3: Read where each agent can move, then move the agents and switch a model off

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIModelsEditorService {

    public class AIModelsEditorServiceException extends Exception {}

    // The providers the cards offer, in the order they appear.
    private static final List<String> PROVIDERS = new List<String>{
        AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC,
        AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT,
        AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI
    };

    // Everything the tab needs when it opens: the models, the providers and the named credentials.
    public static AIModelsDataStructure.ModelsPage getModelsPage() {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Read the three lists
        AIModelsDataStructure.ModelsPage page = new AIModelsDataStructure.ModelsPage();
        page.models = getModelViews();
        page.providers = getProviderOptions();
        page.credentials = getCredentialOptions(page.models);

        return page;
    }

    // Every model, active ones first, each with how many active agents use it.
    public static List<AIModelsDataStructure.ModelView> getModelViews() {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Count the active agents of each model
        Map<Id, Integer> agentCountByModelId = getAgentCounts();

        // [3] Build one view for each model
        List<AIModelsDataStructure.ModelView> views = new List<AIModelsDataStructure.ModelView>();

        for (AIModelConfiguration__c model : [SELECT Id, Name, AIProvider__c, ModelIdentifier__c, NamedCredential__c, ApiPath__c, ApiVersionHeaderName__c, ApiVersionHeaderValue__c, EnvironmentId__c, MaximumOutputTokens__c, Temperature__c, IsActive__c FROM AIModelConfiguration__c WITH SYSTEM_MODE ORDER BY IsActive__c DESC, Name LIMIT :AIAssistApplicationConstants.MODEL_LIST_MAX_RESULTS]) {

            views.add(buildModelView(model, agentCountByModelId.get(model.Id)));
        }

        return views;
    }

    // Tests the connection of a model as the form shows it, without saving anything.
    public static AIModelsDataStructure.TestResult testConnection(AIModelsDataStructure.ModelView view) {

        // [1] Refuse a user who may not use the tab, and a model that cannot be called
        AIAssistSettingsEditorService.requireManager();
        validateConnection(view);

        // [2] Test a copy of the model built from the form
        AIModelConfiguration__c model = new AIModelConfiguration__c();
        copyViewToModel(view, model);

        return AIModelsConnectionTestService.runTest(model);
    }

    // Saves a model, creating it when it is new. Switching a model on, or changing the connection of one that is on, needs a passing test first: a model that fails is saved switched off, and a live model keeps its saved connection.
    public static AIModelsDataStructure.SaveResult saveModel(AIModelsDataStructure.ModelView view) {

        // [1] Refuse a user who may not use the tab, and values the object would refuse
        AIAssistSettingsEditorService.requireManager();
        validateModel(view);

        // [2] Load the saved model, or start a new one
        AIModelConfiguration__c savedModel = view.modelId == null ? null : findModel(view.modelId);
        AIModelConfiguration__c model = savedModel == null ? new AIModelConfiguration__c() : savedModel;
        Boolean wasActive = savedModel != null && savedModel.IsActive__c == true;
        Boolean isConnectionChanged = savedModel == null || hasConnectionChanged(savedModel, view);

        // [3] Refuse to switch off a model that agents use, because the toggle moves them first
        if (wasActive && view.isActive != true && getAgentCounts().get(model.Id) != null) throw new AIModelsEditorServiceException(Label.AI_Models_Error_Switch_Off_Has_Agents);

        // [4] Copy the form onto the model
        copyViewToModel(view, model);
        AIModelsDataStructure.SaveResult result = new AIModelsDataStructure.SaveResult();

        // [5] Test the connection when the model is being switched on, or is on and its connection changed. The test comes before any save, because the platform refuses a callout after unsaved changes.
        if (model.IsActive__c == true && (!wasActive || isConnectionChanged)) {

            result.testResult = AIModelsConnectionTestService.runTest(model);

            // [6] A live model that fails keeps what is saved. A model that was off is saved, still off.
            if (!result.testResult.isSuccessful) {

                if (wasActive) return result;

                model.IsActive__c = false;
                result.isActivationRefused = true;
            }
        }

        // [7] Save and hand back the model as it is now
        upsert model;
        result.isSaved = true;
        result.model = buildModelView(findModel(model.Id), getAgentCounts().get(model.Id));

        return result;
    }

    // What the switch off dialog needs: the active agents that use the model, and the other active models they can move to.
    public static AIModelsDataStructure.SwitchOffOptions getSwitchOffOptions(Id modelId) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();
        findModel(modelId);

        // [2] List the active agents of the model
        AIModelsDataStructure.SwitchOffOptions options = new AIModelsDataStructure.SwitchOffOptions();
        Map<Id, AIModelsDataStructure.AgentUse> agentUseByAgentId = new Map<Id, AIModelsDataStructure.AgentUse>();

        for (AIAgent__c agent : [SELECT Id, Name FROM AIAgent__c WHERE AIModelConfiguration__c = :modelId AND IsActive__c = TRUE WITH SYSTEM_MODE ORDER BY Name LIMIT 2000]) {

            AIModelsDataStructure.AgentUse agentUse = new AIModelsDataStructure.AgentUse();
            agentUse.agentId = agent.Id;
            agentUse.agentName = agent.Name;
            agentUse.userCount = 0;
            options.agentUses.add(agentUse);
            agentUseByAgentId.put(agent.Id, agentUse);
        }

        // [3] Count the users who have had a conversation with each agent
        if (!agentUseByAgentId.isEmpty()) {

            for (AggregateResult userCountRow : [SELECT AIAgent__c agentId, COUNT_DISTINCT(OwnerId) userCount FROM AIConversation__c WHERE AIAgent__c IN :agentUseByAgentId.keySet() WITH SYSTEM_MODE GROUP BY AIAgent__c]) {

                agentUseByAgentId.get((Id) userCountRow.get('agentId')).userCount = (Integer) userCountRow.get('userCount');
            }
        }

        // [4] Offer the other active models
        for (AIModelConfiguration__c otherModel : [SELECT Id, Name FROM AIModelConfiguration__c WHERE IsActive__c = TRUE AND Id != :modelId WITH SYSTEM_MODE ORDER BY Name LIMIT :AIAssistApplicationConstants.MODEL_LIST_MAX_RESULTS]) {

            AIModelsDataStructure.ModelOption option = new AIModelsDataStructure.ModelOption();
            option.modelId = otherModel.Id;
            option.label = otherModel.Name;
            options.modelOptions.add(option);
        }

        return options;
    }

    // Moves each active agent of a model to the model chosen for it, then switches the model off, so no active agent is left on a model that is off. Returns the models as they are now.
    public static List<AIModelsDataStructure.ModelView> switchOffModel(Id modelId, List<AIModelsDataStructure.SwitchOffMove> moves) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();
        AIModelConfiguration__c model = findModel(modelId);

        // [2] Note where each agent goes, and check that place is another active model
        Set<Id> activeModelIds = new Map<Id, AIModelConfiguration__c>([SELECT Id FROM AIModelConfiguration__c WHERE IsActive__c = TRUE AND Id != :modelId WITH SYSTEM_MODE LIMIT :AIAssistApplicationConstants.MODEL_LIST_MAX_RESULTS]).keySet();
        Map<Id, Id> newModelIdByAgentId = new Map<Id, Id>();

        for (AIModelsDataStructure.SwitchOffMove move : moves == null ? new List<AIModelsDataStructure.SwitchOffMove>() : moves) {

            if (move.newModelId == null || !activeModelIds.contains(move.newModelId)) throw new AIModelsEditorServiceException(Label.AI_Models_Error_Move_Target_Invalid);

            newModelIdByAgentId.put(move.agentId, move.newModelId);
        }

        // [3] Move every active agent of the model, and refuse when one has no place to go
        List<AIAgent__c> agentsToMove = [SELECT Id FROM AIAgent__c WHERE AIModelConfiguration__c = :modelId AND IsActive__c = TRUE WITH SYSTEM_MODE LIMIT 2000];

        for (AIAgent__c agent : agentsToMove) {

            if (!newModelIdByAgentId.containsKey(agent.Id)) throw new AIModelsEditorServiceException(Label.AI_Models_Error_Move_Missing);

            agent.AIModelConfiguration__c = newModelIdByAgentId.get(agent.Id);
        }

        update agentsToMove;

        // [4] Switch the model off
        model.IsActive__c = false;
        update model;

        return getModelViews();
    }

    // Finds a model by Id, or refuses.
    private static AIModelConfiguration__c findModel(Id modelId) {

        // [1] Query it
        List<AIModelConfiguration__c> models = [SELECT Id, Name, AIProvider__c, ModelIdentifier__c, NamedCredential__c, ApiPath__c, ApiVersionHeaderName__c, ApiVersionHeaderValue__c, EnvironmentId__c, MaximumOutputTokens__c, Temperature__c, IsActive__c FROM AIModelConfiguration__c WHERE Id = :modelId WITH SYSTEM_MODE LIMIT 1];

        // [2] Refuse one that is not there
        if (models.isEmpty()) throw new AIModelsEditorServiceException(Label.AI_Models_Error_Not_Found);

        return models[0];
    }

    // How many active agents use each model.
    private static Map<Id, Integer> getAgentCounts() {

        // [1] Count the active agents of each model
        Map<Id, Integer> agentCountByModelId = new Map<Id, Integer>();

        for (AggregateResult countRow : [SELECT AIModelConfiguration__c modelId, COUNT(Id) agentCount FROM AIAgent__c WHERE IsActive__c = TRUE AND AIModelConfiguration__c != NULL WITH SYSTEM_MODE GROUP BY AIModelConfiguration__c]) {

            agentCountByModelId.put((Id) countRow.get('modelId'), (Integer) countRow.get('agentCount'));
        }

        return agentCountByModelId;
    }

    // The providers with the connection settings a new model starts from.
    private static List<AIModelsDataStructure.ProviderOption> getProviderOptions() {

        // [1] Build one option for each provider from its preset
        List<AIModelsDataStructure.ProviderOption> options = new List<AIModelsDataStructure.ProviderOption>();

        for (String provider : PROVIDERS) {

            AIProvider.Preset preset = AIProvider.getPreset(provider, null);

            AIModelsDataStructure.ProviderOption option = new AIModelsDataStructure.ProviderOption();
            option.provider = provider;
            option.apiPath = preset.apiPath;
            option.versionHeaderName = preset.versionHeaderName;
            option.versionHeaderValue = preset.versionHeaderValue;
            option.needsEnvironmentId = provider == AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT;
            option.maxTemperature = getMaxTemperature(provider);
            options.add(option);
        }

        return options;
    }

    // The named credentials in Setup. A credential a saved model uses is kept in the list even when Setup no longer has it, so the form can still show it.
    private static List<AIModelsDataStructure.CredentialOption> getCredentialOptions(List<AIModelsDataStructure.ModelView> models) {

        // [1] Read the named credentials
        Map<String, AIModelsDataStructure.CredentialOption> optionByName = new Map<String, AIModelsDataStructure.CredentialOption>();

        for (NamedCredential credential : [SELECT DeveloperName, MasterLabel FROM NamedCredential ORDER BY DeveloperName LIMIT :AIAssistApplicationConstants.MODEL_LIST_MAX_RESULTS]) {

            AIModelsDataStructure.CredentialOption option = new AIModelsDataStructure.CredentialOption();
            option.credentialName = credential.DeveloperName;
            option.label = credential.DeveloperName;
            optionByName.put(credential.DeveloperName, option);
        }

        // [2] Add the credentials the saved models use that Setup did not list
        for (AIModelsDataStructure.ModelView model : models) {

            if (String.isBlank(model.namedCredential) || optionByName.containsKey(model.namedCredential)) continue;

            AIModelsDataStructure.CredentialOption option = new AIModelsDataStructure.CredentialOption();
            option.credentialName = model.namedCredential;
            option.label = model.namedCredential;
            optionByName.put(model.namedCredential, option);
        }

        // [3] Put them in name order
        List<String> names = new List<String>(optionByName.keySet());
        names.sort();
        List<AIModelsDataStructure.CredentialOption> options = new List<AIModelsDataStructure.CredentialOption>();

        for (String name : names) {

            options.add(optionByName.get(name));
        }

        return options;
    }

    // Builds the view of a model.
    private static AIModelsDataStructure.ModelView buildModelView(AIModelConfiguration__c model, Integer agentCount) {

        // [1] Copy the fields across
        AIModelsDataStructure.ModelView view = new AIModelsDataStructure.ModelView();
        view.modelId = model.Id;
        view.modelName = model.Name;
        view.provider = model.AIProvider__c;
        view.modelIdentifier = model.ModelIdentifier__c;
        view.namedCredential = model.NamedCredential__c;
        view.apiPath = model.ApiPath__c;
        view.versionHeaderName = model.ApiVersionHeaderName__c;
        view.versionHeaderValue = model.ApiVersionHeaderValue__c;
        view.environmentId = model.EnvironmentId__c;
        view.maxOutputTokens = model.MaximumOutputTokens__c;
        view.temperature = model.Temperature__c;
        view.isActive = model.IsActive__c == true;
        view.agentCount = agentCount == null ? 0 : agentCount;

        return view;
    }

    // Copies the form onto a model. A blank text becomes empty, and a blank API path takes the provider's own.
    private static void copyViewToModel(AIModelsDataStructure.ModelView view, AIModelConfiguration__c model) {

        // [1] Copy the text fields
        model.Name = getTextOrNull(view.modelName);
        model.AIProvider__c = view.provider;
        model.ModelIdentifier__c = getTextOrNull(view.modelIdentifier);
        model.NamedCredential__c = getTextOrNull(view.namedCredential);
        model.ApiVersionHeaderName__c = getTextOrNull(view.versionHeaderName);
        model.ApiVersionHeaderValue__c = getTextOrNull(view.versionHeaderValue);
        model.EnvironmentId__c = getTextOrNull(view.environmentId);

        // [2] Fall back to the provider's API path when none was typed
        AIProvider.Preset preset = AIProvider.getPreset(view.provider, null);
        model.ApiPath__c = getTextOrNull(view.apiPath) == null && preset != null ? preset.apiPath : getTextOrNull(view.apiPath);

        // [3] Copy the numbers and the switch
        model.MaximumOutputTokens__c = view.maxOutputTokens;
        model.Temperature__c = view.temperature;
        model.IsActive__c = view.isActive == true;
    }

    // True when a field that decides where and how the provider is called differs from what is saved.
    private static Boolean hasConnectionChanged(AIModelConfiguration__c savedModel, AIModelsDataStructure.ModelView view) {

        // [1] Compare each connection field, treating blank and empty as the same
        AIModelConfiguration__c candidate = new AIModelConfiguration__c();
        copyViewToModel(view, candidate);

        Boolean isSame = savedModel.AIProvider__c == candidate.AIProvider__c && savedModel.ModelIdentifier__c == candidate.ModelIdentifier__c && savedModel.NamedCredential__c == candidate.NamedCredential__c && savedModel.ApiPath__c == candidate.ApiPath__c && savedModel.ApiVersionHeaderName__c == candidate.ApiVersionHeaderName__c && savedModel.ApiVersionHeaderValue__c == candidate.ApiVersionHeaderValue__c && savedModel.EnvironmentId__c == candidate.EnvironmentId__c;

        return !isSame;
    }

    // Refuses a model that cannot be called, which is what a test needs.
    private static void validateConnection(AIModelsDataStructure.ModelView view) {

        // [1] A provider this package supports
        if (view == null || !AIProvider.isSupported(view.provider)) throw new AIModelsEditorServiceException(Label.AI_Models_Error_Provider_Invalid);

        // [2] The model ID, the credential and the path
        if (String.isBlank(view.modelIdentifier)) throw new AIModelsEditorServiceException(Label.AI_Models_Error_Model_Required);
        if (String.isBlank(view.namedCredential)) throw new AIModelsEditorServiceException(Label.AI_Models_Error_Credential_Required);
        if (!Pattern.matches('^[A-Za-z][A-Za-z0-9_]*$', view.namedCredential.trim())) throw new AIModelsEditorServiceException(Label.AI_Models_Error_Credential_Format);

        AIProvider.Preset preset = AIProvider.getPreset(view.provider, null);
        String apiPath = String.isBlank(view.apiPath) ? preset.apiPath : view.apiPath.trim();
        if (!Pattern.matches('^/[A-Za-z0-9/_.~%?=&:-]*$', apiPath) || apiPath.contains('..') || apiPath.contains('//')) throw new AIModelsEditorServiceException(Label.AI_Models_Error_Path_Format);

        // [3] The environment ID of a provider that needs one
        if (view.provider == AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT && String.isBlank(view.environmentId)) throw new AIModelsEditorServiceException(Label.AI_Models_Error_Environment_Required);
    }

    // Refuses values the object would refuse, with a message the admin can read.
    private static void validateModel(AIModelsDataStructure.ModelView view) {

        // [1] The name, then everything a test needs
        if (view == null || String.isBlank(view.modelName)) throw new AIModelsEditorServiceException(Label.AI_Models_Error_Name_Required);

        validateConnection(view);

        // [2] A whole number of tokens of 1 or more
        if (view.maxOutputTokens != null && (view.maxOutputTokens < 1 || view.maxOutputTokens != view.maxOutputTokens.setScale(0))) throw new AIModelsEditorServiceException(Label.AI_Models_Error_Tokens_Invalid);

        // [3] A temperature the provider accepts
        if (view.temperature != null && (view.temperature < 0 || view.temperature > getMaxTemperature(view.provider))) throw new AIModelsEditorServiceException(Label.AI_Models_Error_Temperature_Invalid);
    }

    // The highest temperature a provider accepts.
    private static Decimal getMaxTemperature(String provider) {

        // [1] Anthropic accepts 0 to 1, the others 0 to 2
        Boolean isAnthropic = provider == AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC;

        return isAnthropic ? AIAssistApplicationConstants.MODEL_TEMPERATURE_MAX_ANTHROPIC : AIAssistApplicationConstants.MODEL_TEMPERATURE_MAX;
    }

    // Trims a text, and gives null when nothing is left.
    private static String getTextOrNull(String text) {

        // [1] Blank text is nothing
        if (String.isBlank(text)) return null;

        return text.trim();
    }
}
