/*
Class Name: AIModelsController

=================================================================
=================================================================

Description: The Apex controller behind the AI Agent Models tab.

Step 1: Read the models, the providers and the named credentials
Step 2: Test a connection and save a model
Step 3: Read where agents can move, and switch a model off
Step 4: Show an expected refusal as it is, and log anything unexpected once and show the generic label

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIModelsController {

    public class AIModelsControllerException extends Exception {}

    // The models, the providers and the named credentials for the tab.
    @AuraEnabled
    public static AIModelsDataStructure.ModelsPage getModelsPage() {

        try {

            // [1] Do the work
            return AIModelsEditorService.getModelsPage();

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getModelsPage');
        }
    }

    // Tests the connection of the model as the form shows it.
    @AuraEnabled
    public static AIModelsDataStructure.TestResult testConnection(AIModelsDataStructure.ModelView model) {

        try {

            // [1] Do the work
            return AIModelsEditorService.testConnection(model);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'testConnection');
        }
    }

    // Saves one model, creating it when it has no Id.
    @AuraEnabled
    public static AIModelsDataStructure.SaveResult saveModel(AIModelsDataStructure.ModelView model) {

        try {

            // [1] Do the work
            return AIModelsEditorService.saveModel(model);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'saveModel');
        }
    }

    // The agents that use a model and the models they can move to.
    @AuraEnabled
    public static AIModelsDataStructure.SwitchOffOptions getSwitchOffOptions(Id modelId) {

        try {

            // [1] Do the work
            return AIModelsEditorService.getSwitchOffOptions(modelId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getSwitchOffOptions');
        }
    }

    // Moves the agents of a model and switches the model off. Returns the models as they are now.
    @AuraEnabled
    public static List<AIModelsDataStructure.ModelView> switchOffModel(Id modelId, List<AIModelsDataStructure.SwitchOffMove> moves) {

        try {

            // [1] Do the work
            return AIModelsEditorService.switchOffModel(modelId, moves);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'switchOffModel');
        }
    }

    // Shows a package refusal as it is, which is already a Custom Label, and logs anything else once so the tab gets the generic label.
    private static AuraHandledException buildAuraException(Exception ex, String methodName) {

        // [1] Choose the text
        String errorText = Label.AI_Error_Generic;
        if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
        else AIPlatformLogManager.logException(ex, 'AIModelsController', methodName);

        // [2] Build the exception the tab can read
        AuraHandledException auraException = new AuraHandledException(errorText);
        auraException.setMessage(errorText);

        return auraException;
    }
}
