/*
Class Name: AIToolsSkillController

=================================================================
=================================================================

Description: The Apex controller behind the Skills panel of the AI Tools tab.

Step 1: Read the list of skills and one skill in full
Step 2: List the existing data sources, workflow actions and agents the wizard can choose from
Step 3: Save a skill and test it
Step 4: Show an expected refusal as it is, and log anything unexpected once and show the generic label

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIToolsSkillController {

    public class AIToolsSkillControllerException extends Exception {}

    // Every skill, for the list.
    @AuraEnabled
    public static List<AIToolsSkillDataStructure.SkillRow> getSkills() {

        try {

            // [1] Do the work
            return AIToolsSkillEditorService.getSkills();

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getSkills');
        }
    }

    // One skill with everything the wizard edits.
    @AuraEnabled
    public static AIToolsSkillDataStructure.SkillDetail getSkill(Id skillId) {

        try {

            // [1] Do the work
            return AIToolsSkillEditorService.getSkill(skillId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getSkill');
        }
    }

    // The existing data sources and workflow actions to put in a skill.
    @AuraEnabled
    public static List<AIToolsSkillDataStructure.ToolOption> getToolOptions() {

        try {

            // [1] Do the work
            return AIToolsSkillEditorService.getToolOptions();

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getToolOptions');
        }
    }

    // The agents to test a skill with.
    @AuraEnabled
    public static List<AIToolsSkillDataStructure.AgentOption> getTestAgents() {

        try {

            // [1] Do the work
            return AIToolsSkillEditorService.getTestAgents();

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getTestAgents');
        }
    }

    // Saves one skill and its tools, creating it when it is new, and returns it as a list row.
    @AuraEnabled
    public static AIToolsSkillDataStructure.SkillRow saveSkill(Map<String, Object> skillDetail) {

        try {

            // [1] Do the work
            return AIToolsSkillEditorService.saveSkill(buildSkillDetail(skillDetail));

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'saveSkill');
        }
    }

    // Asks an agent's model one question with the skill as it is in the wizard offered on its own.
    @AuraEnabled
    public static AIToolsSkillDataStructure.TestResult runTest(Map<String, Object> skillDetail, Map<String, Object> testRequest) {

        try {

            // [1] Do the work
            return AIToolsSkillTestService.runTest(buildSkillDetail(skillDetail), buildTestRequest(testRequest));

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'runTest');
        }
    }

    // Reads the skill the tab sent as plain values. The tab sends plain values because the platform did not fill in a class passed straight from the page.
    private static AIToolsSkillDataStructure.SkillDetail buildSkillDetail(Map<String, Object> values) {

        // [1] No values mean no skill
        if (values == null) return null;

        // [2] Read the values into the class
        return (AIToolsSkillDataStructure.SkillDetail) JSON.deserialize(JSON.serialize(values), AIToolsSkillDataStructure.SkillDetail.class);
    }

    // Reads the test request the tab sent as plain values.
    private static AIToolsSkillDataStructure.TestRequest buildTestRequest(Map<String, Object> values) {

        // [1] No values mean no test request
        if (values == null) return null;

        // [2] Read the values into the class
        return (AIToolsSkillDataStructure.TestRequest) JSON.deserialize(JSON.serialize(values), AIToolsSkillDataStructure.TestRequest.class);
    }

    // Shows a package refusal as it is, which is already a Custom Label, and logs anything else once so the tab gets the generic label.
    private static AuraHandledException buildAuraException(Exception ex, String methodName) {

        // [1] Choose the text
        String errorText = Label.AI_Error_Generic;
        if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
        else AIPlatformLogManager.logException(ex, 'AIToolsSkillController', methodName);

        // [2] Build the exception the tab can read
        AuraHandledException auraException = new AuraHandledException(errorText);
        auraException.setMessage(errorText);

        return auraException;
    }
}
