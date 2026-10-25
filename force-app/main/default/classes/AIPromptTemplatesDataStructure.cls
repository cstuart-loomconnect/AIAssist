/*
Class Name: AIPromptTemplatesDataStructure

=================================================================
=================================================================

Description: The shapes the AI Prompt Templates tab (aiPromptTemplates) sends to and receives from Apex.

Step 1: TemplateRow is one line of the list, and TemplateDetail is one template with every field the editor changes
Step 2: MergeFieldOption, FieldProblem, PreviewSegment, PreviewSection and PreviewResult carry the Insert bar, the checks and the "What the model receives" preview
Step 3: AgentUse, PublishImpact, SaveResult, ArchiveMove and ArchiveOptions carry the Used by tab, the publish dialog and the archive dialog
Step 4: AgentOption, TestMessage, RunResult and TryItResult carry the Try it tab

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPromptTemplatesDataStructure {

    // One line of the template list.
    public class TemplateRow {

        @AuraEnabled public Id templateId;
        @AuraEnabled public String templateName;
        @AuraEnabled public String developerName;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean isDefault; // The fallback template for agents with none of their own.
        @AuraEnabled public Decimal version;
        @AuraEnabled public Integer agentCount; // Active agents that answer with this template, counting the ones that fall back to it when it is the default.
    }

    // One template with every field the editor changes. The editor sends it back to be previewed, tried or saved.
    public class TemplateDetail {

        @AuraEnabled public Id templateId; // Blank for a template that is not saved yet.
        @AuraEnabled public String templateName;
        @AuraEnabled public String developerName;
        @AuraEnabled public Decimal maxResponseLength; // Words.
        @AuraEnabled public String systemContext; // The Context section.
        @AuraEnabled public String tone; // The Tone section.
        @AuraEnabled public String prompt; // The Instructions section.
        @AuraEnabled public String exclusionRules; // The Never section.
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean isDefault;
        @AuraEnabled public Decimal version;
        @AuraEnabled public Integer agentCount;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public String lastModifiedByName;
    }

    // A merge field the Insert bar offers.
    public class MergeFieldOption {

        @AuraEnabled public String token; // Such as {!Agent.Name}.
        @AuraEnabled public String description;
    }

    // One thing wrong with a template. fieldName is the editor field that shows it: templateName, developerName, maxResponseLength, systemContext, tone, prompt or exclusionRules.
    public class FieldProblem {

        @AuraEnabled public String fieldName;
        @AuraEnabled public String message;
    }

    // A piece of a section's text. isValue is true when it is a merge field that was filled in, so the preview can colour it.
    public class PreviewSegment {

        @AuraEnabled public String text;
        @AuraEnabled public Boolean isValue;
    }

    // One section of what the model receives, such as Context or Never.
    public class PreviewSection {

        @AuraEnabled public String heading;
        @AuraEnabled public List<PreviewSegment> segments = new List<PreviewSegment>();
    }

    // What the model receives, with the checks the editor shows above the form.
    public class PreviewResult {

        @AuraEnabled public List<PreviewSection> sections = new List<PreviewSection>();
        @AuraEnabled public Integer estimatedTokens;
        @AuraEnabled public List<FieldProblem> problems = new List<FieldProblem>();
    }

    // An agent that answers with a template, for the Used by tab and the dialogs.
    public class AgentUse {

        @AuraEnabled public Id agentId;
        @AuraEnabled public String agentName;
        @AuraEnabled public Integer userCount; // Users who have had a conversation with the agent.
        @AuraEnabled public Integer openConversationCount; // Active conversations with the agent.
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean usesFallback; // True when the agent has no template of its own and falls back to the default.
    }

    // What the publish dialog shows.
    public class PublishImpact {

        @AuraEnabled public Boolean isNew;
        @AuraEnabled public Decimal currentVersion;
        @AuraEnabled public Decimal nextVersion;
        @AuraEnabled public List<String> changedSections = new List<String>(); // The headings that changed, such as Instructions.
        @AuraEnabled public List<AgentUse> agentUses = new List<AgentUse>();
        @AuraEnabled public Integer testMessageCount;
        @AuraEnabled public Integer testPassedCount;
    }

    // What a save returns: the saved template, or the problems that stopped it.
    public class SaveResult {

        @AuraEnabled public Boolean isSaved = false;
        @AuraEnabled public TemplateDetail detail;
        @AuraEnabled public List<FieldProblem> problems = new List<FieldProblem>();
    }

    // Where an agent goes when its template is archived. A blank newTemplateId sends it to the default template.
    public class ArchiveMove {

        @AuraEnabled public Id agentId;
        @AuraEnabled public Id newTemplateId;
    }

    // A template an agent can be moved to.
    public class TemplateOption {

        @AuraEnabled public Id templateId;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isDefault;
    }

    // What the archive dialog shows.
    public class ArchiveOptions {

        @AuraEnabled public Boolean isDefault; // The default template cannot be archived.
        @AuraEnabled public String defaultName; // The name of the default (fallback) template, blank when there is none.
        @AuraEnabled public List<AgentUse> agentUses = new List<AgentUse>();
        @AuraEnabled public List<TemplateOption> templateOptions = new List<TemplateOption>();
    }

    // An agent the Try it tab can run a message as.
    public class AgentOption {

        @AuraEnabled public Id agentId;
        @AuraEnabled public String agentName;
        @AuraEnabled public String objectApiName; // The first object the agent works on, blank when it has none. Picks the "On record" object.
    }

    // A saved test message with the result of its last run.
    public class TestMessage {

        @AuraEnabled public Id testMessageId;
        @AuraEnabled public String messageBody;
        @AuraEnabled public Datetime lastRunOn;
        @AuraEnabled public String lastRunStatus; // Passed or Failed. Blank means never run.
        @AuraEnabled public String lastSavedReply;
        @AuraEnabled public String lastEditedReply;
        @AuraEnabled public String savedVerdict; // Better or Worse.
        @AuraEnabled public String editedVerdict;
    }

    // One run of a message against one wording.
    public class RunResult {

        @AuraEnabled public Boolean isSuccessful = false;
        @AuraEnabled public String replyText;
        @AuraEnabled public Decimal latencyMilliseconds;
        @AuraEnabled public Decimal totalTokens;
        @AuraEnabled public String errorMessage; // Text safe to show the administrator.
    }

    // A message run against the saved wording and the edited wording.
    public class TryItResult {

        @AuraEnabled public RunResult savedRun; // Blank for a template that is not saved yet.
        @AuraEnabled public RunResult editedRun;
        @AuraEnabled public TestMessage testMessage; // The saved message that was updated, when the run came from one.
    }
}
