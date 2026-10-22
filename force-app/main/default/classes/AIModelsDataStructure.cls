/*
Class Name: AIModelsDataStructure

=================================================================
=================================================================

Description: The shapes the AI Agent Models tab (aiModels) sends to and receives from Apex.

Step 1: ModelView is one model with every field the form changes, and ProviderOption and CredentialOption fill the provider cards and the named credential box
Step 2: ModelsPage carries all of those to the tab in one call
Step 3: TestResult and SaveResult carry the connection test and the save
Step 4: AgentUse, ModelOption, SwitchOffMove and SwitchOffOptions carry the switch off dialog

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIModelsDataStructure {

    // One model: a line of the list, and every field the form changes. The form sends it back to be tested or saved.
    public class ModelView {

        @AuraEnabled public Id modelId; // Blank for a model that is not saved yet.
        @AuraEnabled public String modelName;
        @AuraEnabled public String provider; // An AIModelConfiguration__c.AIProvider__c value.
        @AuraEnabled public String modelIdentifier; // The provider's own model ID.
        @AuraEnabled public String namedCredential; // The API name of the Named Credential. The API key is never on the record.
        @AuraEnabled public String apiPath;
        @AuraEnabled public String versionHeaderName;
        @AuraEnabled public String versionHeaderValue;
        @AuraEnabled public String environmentId; // Anthropic Agent only.
        @AuraEnabled public Decimal maxOutputTokens;
        @AuraEnabled public Decimal temperature;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Integer agentCount; // Active agents that use the model.
    }

    // A provider the cards offer, with the connection settings a new model of that provider starts from.
    public class ProviderOption {

        @AuraEnabled public String provider; // An AIModelConfiguration__c.AIProvider__c value.
        @AuraEnabled public String apiPath;
        @AuraEnabled public String versionHeaderName;
        @AuraEnabled public String versionHeaderValue;
        @AuraEnabled public Boolean needsEnvironmentId;
        @AuraEnabled public Decimal maxTemperature;
    }

    // A named credential the admin can pick.
    public class CredentialOption {

        @AuraEnabled public String credentialName; // The API name.
        @AuraEnabled public String label;
    }

    // Everything the tab needs when it opens.
    public class ModelsPage {

        @AuraEnabled public List<ModelView> models = new List<ModelView>();
        @AuraEnabled public List<ProviderOption> providers = new List<ProviderOption>();
        @AuraEnabled public List<CredentialOption> credentials = new List<CredentialOption>();
    }

    // What one connection test found. It never carries the provider's own error text, which can hold configuration.
    public class TestResult {

        @AuraEnabled public Boolean isSuccessful;
        @AuraEnabled public Integer httpStatusCode; // Blank when no reply came back.
        @AuraEnabled public Decimal latencyMilliseconds;
        @AuraEnabled public Decimal inputTokens;
        @AuraEnabled public Decimal outputTokens;
        @AuraEnabled public String failureReason; // An AIConversationMessage__c.FailureReason__c value, blank on success.
        @AuraEnabled public String namedCredential;
    }

    // What a save did. isSaved is false only when a model that is already switched on failed the test after its connection changed, so nothing was written.
    public class SaveResult {

        @AuraEnabled public Boolean isSaved = false;
        @AuraEnabled public Boolean isActivationRefused = false; // The model was saved, but switched off because the test failed.
        @AuraEnabled public ModelView model;
        @AuraEnabled public TestResult testResult; // Blank when no test was needed.
    }

    // An active agent that uses the model being switched off.
    public class AgentUse {

        @AuraEnabled public Id agentId;
        @AuraEnabled public String agentName;
        @AuraEnabled public Integer userCount; // Users who have had a conversation with the agent.
    }

    // A model an agent can be moved to.
    public class ModelOption {

        @AuraEnabled public Id modelId;
        @AuraEnabled public String label;
    }

    // Where an agent goes when its model is switched off.
    public class SwitchOffMove {

        @AuraEnabled public Id agentId;
        @AuraEnabled public Id newModelId;
    }

    // What the switch off dialog shows.
    public class SwitchOffOptions {

        @AuraEnabled public List<AgentUse> agentUses = new List<AgentUse>();
        @AuraEnabled public List<ModelOption> modelOptions = new List<ModelOption>();
    }
}
