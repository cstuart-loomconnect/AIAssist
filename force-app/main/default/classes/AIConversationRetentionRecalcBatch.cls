/*
Class Name: AIConversationRetentionRecalcBatch

=================================================================
=================================================================

Description: Recalculates RetentionExpiryDate__c on every conversation of the agents whose retention settings changed.

Step 1: Query every conversation of the agents whose retention days or trigger changed
Step 2: Work out the date each conversation's retention is counted from, using the agent's trigger (blank or under 1 day means no expiry date)
Step 3: Add the retention days to that date (GMT) to get the new expiry date
Step 4: Write only the conversations whose expiry date changed, logging any failures

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIConversationRetentionRecalcBatch implements Database.Batchable<SObject> {

    private Set<Id> agentIds;

    public AIConversationRetentionRecalcBatch(Set<Id> agentIds) {

        this.agentIds = agentIds == null ? new Set<Id>() : agentIds;
    }

    // Finds every conversation belonging to the agents whose retention settings changed.
    public Database.QueryLocator start(Database.BatchableContext context) {

        // [1] Query the conversations with the agent's retention settings
        return Database.getQueryLocator([SELECT Id, CreatedDate, LastMessageTimestamp__c, ConversationClosedTimestamp__c, Status__c, RetentionExpiryDate__c, AIAgent__r.ConversationRetentionDays__c, AIAgent__r.RetentionTrigger__c FROM AIConversation__c WHERE AIAgent__c IN :agentIds WITH SYSTEM_MODE]);
    }

    // Recalculates the expiry date of each conversation and saves the ones that changed.
    public void execute(Database.BatchableContext context, List<AIConversation__c> scope) {

        // [1] Collect the conversations whose expiry date needs to change
        List<AIConversation__c> changed = new List<AIConversation__c>();

        for (AIConversation__c conversation : scope) {

            // [2] Read the agent's retention settings
            Decimal retentionDays = conversation.AIAgent__r.ConversationRetentionDays__c;
            String retentionTrigger = conversation.AIAgent__r.RetentionTrigger__c;
            Datetime countedFrom = null;

            // [3] Pick the date to count from, only when the agent keeps conversations for a set time
            if (retentionDays != null && retentionDays >= 1) {

                if (retentionTrigger == AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE) countedFrom = conversation.CreatedDate;
                else if (retentionTrigger == AIAssistApplicationConstants.RETENTION_TRIGGER_LAST_MESSAGE_DATE) countedFrom = conversation.LastMessageTimestamp__c == null ? conversation.CreatedDate : conversation.LastMessageTimestamp__c;
                else if (retentionTrigger == AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE && conversation.Status__c == AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED) countedFrom = conversation.ConversationClosedTimestamp__c;
            }

            // [4] Add the retention days to get the new expiry date (none when there is nothing to count from)
            Date expiryDate = countedFrom == null ? null : countedFrom.dateGmt().addDays(Integer.valueOf(retentionDays));

            // [5] Keep the conversation only if its expiry date is different
            if (expiryDate != conversation.RetentionExpiryDate__c) changed.add(new AIConversation__c(Id = conversation.Id, RetentionExpiryDate__c = expiryDate));
        }

        // [6] Save the changes and log any failures
        AIMessagingDataService.updateAndLogFailures(changed, 'AIConversationRetentionRecalcBatch', 'execute');
    }

    // Nothing to do when the batch finishes.
    public void finish(Database.BatchableContext context) {
    }
}
