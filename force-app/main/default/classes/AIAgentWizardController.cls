/*
Class Name: AIAgentWizardController

=================================================================
=================================================================

Description: The Apex controller behind the AI Agent Wizard tab.

Step 1: Read the page, the list of agents, a copy of an agent, the objects and the assignees the steps offer
Step 2: Check a draft or a user, test a model and try the agent
Step 3: Save the agent in one call, and switch an agent on or off from the list
Step 4: Show an expected refusal as it is, and log anything unexpected once and show the generic label

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAgentWizardController {

    // Everything the tab needs when it opens. A blank agent id is a new agent.
    @AuraEnabled
    public static AIAgentWizardDataStructure.WizardPage getWizardPage(Id agentId) {

        try {

            // [1] Do the work
            return AIAgentWizardEditorService.getWizardPage(agentId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getWizardPage');
        }
    }

    // Every agent as one line of the list the tab opens on.
    @AuraEnabled
    public static List<AIAgentWizardDataStructure.AgentRow> getAgentList() {

        try {

            // [1] Do the work
            return AIAgentWizardEditorService.getAgentList();

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getAgentList');
        }
    }

    // Switches an agent on or off, and gives back its new line of the list.
    @AuraEnabled
    public static AIAgentWizardDataStructure.AgentRow setAgentActive(Id agentId, Boolean isActive) {

        try {

            // [1] Do the work
            return AIAgentWizardSaveService.setAgentActive(agentId, isActive);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'setAgentActive');
        }
    }

    // A saved agent as the draft of a new agent.
    @AuraEnabled
    public static AIAgentWizardDataStructure.AgentDraft getCopyDraft(Id agentId) {

        try {

            // [1] Do the work
            return AIAgentWizardEditorService.getCopyDraft(agentId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getCopyDraft');
        }
    }

    // The objects an agent can appear on that match the text.
    @AuraEnabled
    public static List<AIAgentWizardDataStructure.ObjectOption> searchObjects(String term) {

        try {

            // [1] Do the work
            return AIAgentWizardEditorService.searchObjects(term);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'searchObjects');
        }
    }

    // Every blocker and warning of the draft.
    @AuraEnabled
    public static AIAgentWizardDataStructure.DraftCheck checkDraft(String draftJson) {

        try {

            // [1] Do the work
            return AIAgentWizardCheckService.checkDraft(readDraft(draftJson));

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'checkDraft');
        }
    }

    // The connection check of the Model step.
    @AuraEnabled
    public static AIModelsDataStructure.TestResult testModel(Id modelId) {

        try {

            // [1] Do the work
            return AIAgentWizardEditorService.testModel(modelId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'testModel');
        }
    }

    // The users and permission sets the Add dialog offers.
    @AuraEnabled
    public static List<AIAgentWizardDataStructure.AssigneeOption> searchAssignees(String term) {

        try {

            // [1] Do the work
            return AIAgentWizardCheckService.searchAssignees(term);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'searchAssignees');
        }
    }

    // Whether one user would have the agent.
    @AuraEnabled
    public static AIAgentWizardDataStructure.UserCheck checkUser(String draftJson, Id userId) {

        try {

            // [1] Do the work
            return AIAgentWizardCheckService.checkUser(readDraft(draftJson), userId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'checkUser');
        }
    }

    // Runs one trial message through the draft.
    @AuraEnabled
    public static AIAgentWizardDataStructure.TryResult tryAgent(String draftJson, String message, Id recordId) {

        try {

            // [1] Do the work
            return AIAgentWizardTryService.tryAgent(readDraft(draftJson), message, recordId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'tryAgent');
        }
    }

    // Saves the agent, its links and its access list in one call.
    @AuraEnabled
    public static AIAgentWizardDataStructure.SaveResult saveAgent(String draftJson, Boolean shouldActivate) {

        try {

            // [1] Do the work
            return AIAgentWizardSaveService.saveAgent(readDraft(draftJson), shouldActivate);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'saveAgent');
        }
    }

    // Reads the draft the tab sends as text. The tab sends text because Aura left a typed draft empty.
    private static AIAgentWizardDataStructure.AgentDraft readDraft(String draftJson) {

        // [1] A missing draft stays missing, so the services refuse it
        if (String.isBlank(draftJson)) return null;

        return (AIAgentWizardDataStructure.AgentDraft) JSON.deserialize(draftJson, AIAgentWizardDataStructure.AgentDraft.class);
    }

    // Shows a package refusal as it is, which is already a Custom Label, and logs anything else once so the tab gets the generic label.
    private static AuraHandledException buildAuraException(Exception ex, String methodName) {

        // [1] Choose the text
        String errorText = Label.AI_Error_Generic;
        if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
        else AIPlatformLogManager.logException(ex, 'AIAgentWizardController', methodName);

        // [2] Build the exception the tab can read
        AuraHandledException auraException = new AuraHandledException(errorText);
        auraException.setMessage(errorText);

        return auraException;
    }
}
