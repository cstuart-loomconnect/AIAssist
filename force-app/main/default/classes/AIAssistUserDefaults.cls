/*
Class Name: AIAssistUserDefaults

=================================================================
=================================================================

Description: Builds the default AIUserSettings__c record for a User, with the starting values kept in one place.

Step 1: A caller passes in the User the settings are for
Step 2: Each section holds the starting values for one area of the settings
Step 3: The sections are copied onto a new AIUserSettings__c, linked to the User, and returned

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAssistUserDefaults {

    // The starting values for a new user, grouped into the sections below.
    public class AIAssistUser {

        public Boolean isActive = true;
        public LimitsSection limits = new LimitsSection();
        public AccessSection access = new AccessSection();
        public WorkflowSection workflow = new WorkflowSection();

        // Copies the starting values onto a new settings record for the user.
        public AIUserSettings__c buildSettings(User user) {

            // [1] Copy each section onto the record, linked to the user
            return new AIUserSettings__c(User__c = user.Id, IsActive__c = isActive, AllowedChannels__c = access.allowedChannels, DebugModeEnabled__c = workflow.debugModeEnabled, MaxTokensPer24Hours__c = limits.maxTokensPer24Hours, WorkflowActionsEnabled__c = workflow.workflowActionsEnabled, UsageLimitReachedBehavior__c = limits.usageLimitReachedBehavior, MaxConcurrentConversations__c = limits.maxConcurrentConversations, MaxConversationsPer24Hours__c = limits.maxConversationsPer24Hours, ConversationExportEnabled__c = workflow.conversationExportEnabled, ConversationVisibilityScope__c = access.conversationVisibilityScope);
        }
    }

    // Who can see conversations and where the assistant can be used.
    public class AccessSection {

        public String conversationVisibilityScope = AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN;
        public String allowedChannels = AIAssistApplicationConstants.CHANNEL_RECORD_PAGE_CHAT + AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR + AIAssistApplicationConstants.CHANNEL_UTILITY_BAR;
    }

    // Feature switches that change how the assistant behaves day to day.
    public class WorkflowSection {

        public Boolean debugModeEnabled = false;
        public Boolean workflowActionsEnabled = false;
        public Boolean conversationExportEnabled = false;
    }

    // Rate and usage limits. A null limit means no limit.
    public class LimitsSection {

        public Decimal maxTokensPer24Hours = null;
        public Decimal maxConcurrentConversations = null;
        public Decimal maxConversationsPer24Hours = null;
        public String usageLimitReachedBehavior = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY;
    }

    // Builds the default settings record for the user. It is not saved.
    public static AIUserSettings__c build(User user) {

        // [1] Build the record from the starting values
        return new AIAssistUser().buildSettings(user);
    }
}
