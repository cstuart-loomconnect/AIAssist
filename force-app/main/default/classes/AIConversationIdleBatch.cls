/*
Class Name: AIConversationIdleBatch

=================================================================
=================================================================

Description: Closes active conversations that have sat idle longer than their agent's IdleTimeoutMinutes__c.

Step 1: Find the active conversations whose agent has an idle timeout
Step 2: Do nothing while the application is switched off
Step 3: Skip a conversation whose reply is still being produced, or that is still inside its timeout
Step 4: Close the rest as idle and log any that fail to save

Idle time runs from the conversation's last message (LastMessageTimestamp__c, kept by the message trigger) or, with no
messages yet, from its creation, so no second query on the messages is needed. It reads and writes only the package's
own conversations, in system mode because conversations are private to their owner and the job must see them all.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIConversationIdleBatch implements Database.Batchable<SObject> {

    // Finds the active conversations whose agent has an idle timeout.
    public Database.QueryLocator start(Database.BatchableContext context) {

        // [1] Query in system mode so every user's conversations are seen
        return Database.getQueryLocator([SELECT Id, CreatedDate, LastMessageTimestamp__c, ProcessingLockedUntil__c, AIAgent__r.IdleTimeoutMinutes__c FROM AIConversation__c WHERE Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE AND AIAgent__r.IdleTimeoutMinutes__c != NULL WITH SYSTEM_MODE]);
    }

    // Closes each conversation in the scope that has been idle for longer than its agent's timeout.
    public void execute(Database.BatchableContext context, List<AIConversation__c> scope) {

        // [1] Do nothing while the application is switched off
        if (!AIAssistSettingsService.isEnabled()) return;

        Datetime currentTime = System.now();
        List<AIConversation__c> conversationsToClose = new List<AIConversation__c>();

        for (AIConversation__c conversation : scope) {

            // [2] Skip a conversation whose reply is still being produced
            if (conversation.ProcessingLockedUntil__c != null && conversation.ProcessingLockedUntil__c > currentTime) continue;

            // [3] Measure idle time from the last message, or from creation when there are no messages
            Datetime lastActivity = conversation.LastMessageTimestamp__c == null ? conversation.CreatedDate : conversation.LastMessageTimestamp__c;

            // [4] Skip a conversation that is still inside its timeout
            if (lastActivity.addMinutes(Integer.valueOf(conversation.AIAgent__r.IdleTimeoutMinutes__c)) > currentTime) continue;

            // [5] Close the conversation as idle
            conversationsToClose.add(new AIConversation__c(Id = conversation.Id, Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED, ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_IDLE_TIMEOUT, ConversationClosedTimestamp__c = currentTime));
        }

        // [6] Save the closed conversations, logging any failure so one bad record does not stop the rest
        AIMessagingDataService.updateAndLogFailures(conversationsToClose, 'AIConversationIdleBatch', 'execute');
    }

    // Nothing to do when the batch finishes.
    public void finish(Database.BatchableContext context) {
    }
}
