/*
Class Name: AIPromptTemplatesController

=================================================================
=================================================================

Description: The Apex controller behind the AI Prompt Templates tab.

Step 1: Read the templates, the agents that use them, the merge fields and the saved test messages
Step 2: Check, preview and save a template
Step 3: Archive, bring back or make default a template
Step 4: Run a message with the saved and the edited wording
Step 5: Show an expected refusal as it is, and log anything unexpected once and show the generic label

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPromptTemplatesController {

    public class AIPromptTemplatesControllerException extends Exception {}

    // The templates for the list.
    @AuraEnabled
    public static List<AIPromptTemplatesDataStructure.TemplateRow> getTemplateRows() {

        try {

            // [1] Do the work
            return AIPromptTemplatesEditorService.getTemplateRows();

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getTemplateRows');
        }
    }

    // One template with every field the editor changes.
    @AuraEnabled
    public static AIPromptTemplatesDataStructure.TemplateDetail getTemplateDetail(Id templateId) {

        try {

            // [1] Do the work
            return AIPromptTemplatesEditorService.getTemplateDetail(templateId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getTemplateDetail');
        }
    }

    // The merge fields the Insert bar offers.
    @AuraEnabled
    public static List<AIPromptTemplatesDataStructure.MergeFieldOption> getMergeFieldOptions() {

        try {

            // [1] Do the work
            return AIPromptTemplatesEditorService.getMergeFieldOptions();

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getMergeFieldOptions');
        }
    }

    // The agents the Try it tab can run a message as.
    @AuraEnabled
    public static List<AIPromptTemplatesDataStructure.AgentOption> getAgentOptions() {

        try {

            // [1] Do the work
            return AIPromptTemplatesEditorService.getAgentOptions();

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getAgentOptions');
        }
    }

    // Checks a template, saved or not, and shows what the model would receive from it.
    @AuraEnabled
    public static AIPromptTemplatesDataStructure.PreviewResult getPreview(Map<String, Object> templateDetail, Id agentId, Id recordId) {

        try {

            // [1] Do the work
            return AIPromptTemplatesEditorService.getPreview(buildTemplateDetail(templateDetail), agentId, recordId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getPreview');
        }
    }

    // What a save would change and which agents it reaches, for the publish dialog.
    @AuraEnabled
    public static AIPromptTemplatesDataStructure.PublishImpact getPublishImpact(Map<String, Object> templateDetail) {

        try {

            // [1] Do the work
            return AIPromptTemplatesEditorService.getPublishImpact(buildTemplateDetail(templateDetail));

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getPublishImpact');
        }
    }

    // Saves a template, or returns the problems that stopped it.
    @AuraEnabled
    public static AIPromptTemplatesDataStructure.SaveResult saveTemplate(Map<String, Object> templateDetail) {

        try {

            // [1] Do the work
            return AIPromptTemplatesEditorService.saveTemplate(buildTemplateDetail(templateDetail));

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'saveTemplate');
        }
    }

    // The agents that answer with a template.
    @AuraEnabled
    public static List<AIPromptTemplatesDataStructure.AgentUse> getAgentUses(Id templateId) {

        try {

            // [1] Do the work
            return AIPromptTemplatesEditorService.getAgentUses(templateId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getAgentUses');
        }
    }

    // The agents that move and the templates they can move to, for the archive dialog.
    @AuraEnabled
    public static AIPromptTemplatesDataStructure.ArchiveOptions getArchiveOptions(Id templateId) {

        try {

            // [1] Do the work
            return AIPromptTemplatesEditorService.getArchiveOptions(templateId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getArchiveOptions');
        }
    }

    // Archives a template after moving its agents.
    @AuraEnabled
    public static void archiveTemplate(Id templateId, List<Map<String, Object>> moves) {

        try {

            // [1] Do the work
            AIPromptTemplatesEditorService.archiveTemplate(templateId, buildArchiveMoves(moves));

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'archiveTemplate');
        }
    }

    // Brings an archived template back.
    @AuraEnabled
    public static void activateTemplate(Id templateId) {

        try {

            // [1] Do the work
            AIPromptTemplatesEditorService.activateTemplate(templateId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'activateTemplate');
        }
    }

    // Makes a template the default.
    @AuraEnabled
    public static void setDefaultTemplate(Id templateId) {

        try {

            // [1] Do the work
            AIPromptTemplatesEditorService.setDefaultTemplate(templateId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'setDefaultTemplate');
        }
    }

    // The saved test messages of a template.
    @AuraEnabled
    public static List<AIPromptTemplatesDataStructure.TestMessage> getTestMessages(Id templateId) {

        try {

            // [1] Do the work
            return AIPromptTemplatesEditorService.getTestMessages(templateId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getTestMessages');
        }
    }

    // Saves a test message against a template.
    @AuraEnabled
    public static AIPromptTemplatesDataStructure.TestMessage saveTestMessage(Id templateId, String messageBody) {

        try {

            // [1] Do the work
            return AIPromptTemplatesEditorService.saveTestMessage(templateId, messageBody);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'saveTestMessage');
        }
    }

    // Deletes a saved test message.
    @AuraEnabled
    public static void deleteTestMessage(Id testMessageId) {

        try {

            // [1] Do the work
            AIPromptTemplatesEditorService.deleteTestMessage(testMessageId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'deleteTestMessage');
        }
    }

    // Marks a reply of a saved test message as Better or Worse. The side is saved or edited.
    @AuraEnabled
    public static AIPromptTemplatesDataStructure.TestMessage setVerdict(Id testMessageId, String side, String verdict) {

        try {

            // [1] Do the work
            return AIPromptTemplatesEditorService.setVerdict(testMessageId, side, verdict);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'setVerdict');
        }
    }

    // Runs a message with the saved and the edited wording of a template.
    @AuraEnabled
    public static AIPromptTemplatesDataStructure.TryItResult runTryIt(Map<String, Object> templateDetail, String messageBody, Id agentId, Id recordId, Id testMessageId) {

        try {

            // [1] Do the work
            return AIPromptTemplatesTryItService.runTryIt(buildTemplateDetail(templateDetail), messageBody, agentId, recordId, testMessageId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'runTryIt');
        }
    }

    // Reads the template the tab sent as plain values. The tab sends plain values because the platform did not fill in a class passed straight from the page.
    private static AIPromptTemplatesDataStructure.TemplateDetail buildTemplateDetail(Map<String, Object> values) {

        // [1] No values mean no template
        if (values == null) return null;

        // [2] Read the values into the class
        return (AIPromptTemplatesDataStructure.TemplateDetail) JSON.deserialize(JSON.serialize(values), AIPromptTemplatesDataStructure.TemplateDetail.class);
    }

    // Reads the moves the tab sent as plain values.
    private static List<AIPromptTemplatesDataStructure.ArchiveMove> buildArchiveMoves(List<Map<String, Object>> values) {

        // [1] No values mean no moves
        if (values == null) return new List<AIPromptTemplatesDataStructure.ArchiveMove>();

        // [2] Read the values into the class
        return (List<AIPromptTemplatesDataStructure.ArchiveMove>) JSON.deserialize(JSON.serialize(values), List<AIPromptTemplatesDataStructure.ArchiveMove>.class);
    }

    // Shows a package refusal as it is, which is already a Custom Label, and logs anything else once so the tab gets the generic label.
    private static AuraHandledException buildAuraException(Exception ex, String methodName) {

        // [1] Choose the text
        String errorText = Label.AI_Error_Generic;
        if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
        else AIPlatformLogManager.logException(ex, 'AIPromptTemplatesController', methodName);

        // [2] Build the exception the tab can read
        AuraHandledException auraException = new AuraHandledException(errorText);
        auraException.setMessage(errorText);

        return auraException;
    }
}
