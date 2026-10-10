/*
Class Name: AIConversationTriggerHandler

=================================================================
=================================================================

Description: Handler for the AI Conversation trigger: sets the retention expiry date and the close timestamp, and counts each new conversation in its owner's usage for the day.

Step 1: Before insert, set the expiry date for retention counted from creation or from the last message
Step 2: Before update, find the conversations that have just closed and stamp their close time
Step 3: Set the expiry date for retention counted from the close date
Step 4: After insert, add each new conversation to its owner's usage for today

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIConversationTriggerHandler {

    public class AIConversationTriggerHandlerException extends Exception {}

    private static Boolean isBeforeInsertHandlerRunning = false;
    private static Boolean isBeforeUpdateHandlerRunning = false;
    private static Boolean isAfterInsertHandlerRunning = false;

    @TestVisible
    private static Boolean isTestCustomExceptionThrown = false;

    // Runs before new conversations are saved and sets the retention expiry date where it is already known.
    public static void handleBeforeInsert(List<AIConversation__c> newConversations) {

        try {

            // [1] Do nothing if this handler is already running
            if (isBeforeInsertHandlerRunning) return;
            isBeforeInsertHandlerRunning = true;

            // [2] Throw on purpose when a test asks for it
            if (isTestCustomExceptionThrown) {

                throw new AIConversationTriggerHandlerException('Test exception for AIConversationTriggerHandler.handleBeforeInsert');
            }

            // [3] Set the expiry date on the new conversations
            if (newConversations != null && !newConversations.isEmpty()) {

                calculateRetentionExpiryDateOnCreate(newConversations);
            }

            // [4] Allow the handler to run again
            isBeforeInsertHandlerRunning = false;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIConversationTriggerHandler', 'handleBeforeInsert');
        }
    }

    // Runs before conversations are updated and handles the ones that have just closed.
    public static void handleBeforeUpdate(Map<Id, AIConversation__c> oldConversationsById, Map<Id, AIConversation__c> newConversationsById) {

        try {

            // [1] Do nothing if this handler is already running
            if (isBeforeUpdateHandlerRunning) return;
            isBeforeUpdateHandlerRunning = true;

            // [2] Throw on purpose when a test asks for it
            if (isTestCustomExceptionThrown) {

                throw new AIConversationTriggerHandlerException('Test exception for AIConversationTriggerHandler.handleBeforeUpdate');
            }

            // [3] Find the conversations that have just closed and stamp their close time
            Map<Id, AIConversation__c> conversationsNewlyClosedById = markConversationsNewlyClosed(oldConversationsById, newConversationsById);

            // [4] Set the expiry date on the conversations that have just closed
            if (!conversationsNewlyClosedById.isEmpty()) {

                calculateRetentionExpiryDateOnClose(oldConversationsById, conversationsNewlyClosedById);
            }

            // [5] Allow the handler to run again
            isBeforeUpdateHandlerRunning = false;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIConversationTriggerHandler', 'handleBeforeUpdate');
        }
    }

    // Runs after new conversations are saved and counts each one in its owner's usage for today. Never blocks the save.
    public static void handleAfterInsert(List<AIConversation__c> newConversations) {

        try {

            // [1] Do nothing if this handler is already running
            if (isAfterInsertHandlerRunning) return;
            isAfterInsertHandlerRunning = true;

            // [2] Throw on purpose when a test asks for it
            if (isTestCustomExceptionThrown) {

                throw new AIConversationTriggerHandlerException('Test exception for AIConversationTriggerHandler.handleAfterInsert');
            }

            // [3] Count the new conversations for each owner
            Map<Id, AIUsageService.UsageToAdd> additionsByUserId = new Map<Id, AIUsageService.UsageToAdd>();

            for (AIConversation__c conversation : newConversations == null ? new List<AIConversation__c>() : newConversations) {

                if (conversation.OwnerId == null) continue;

                if (!additionsByUserId.containsKey(conversation.OwnerId)) additionsByUserId.put(conversation.OwnerId, new AIUsageService.UsageToAdd());

                additionsByUserId.get(conversation.OwnerId).conversations++;
            }

            // [4] Add them to the owners' usage for today
            AIUsageService.addUsage(additionsByUserId);

            // [5] Allow the handler to run again
            isAfterInsertHandlerRunning = false;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIConversationTriggerHandler', 'handleAfterInsert');
        }
    }

    // Retention counted from the creation date, or from the last message (which starts at creation), is known as soon as the conversation is created.
    private static void calculateRetentionExpiryDateOnCreate(List<AIConversation__c> newConversations) {

        try {

            // [1] Nothing to do - no conversations
            if (newConversations == null || newConversations.isEmpty()) return;

            // [2] Load the retention settings of the agents involved
            Map<Id, AIAgent__c> agentsById = getAgentsById(newConversations);

            for (AIConversation__c conversation : newConversations) {

                // [3] Keep an expiry date that was already provided
                if (conversation.RetentionExpiryDate__c != null) continue;

                // [4] Skip conversations whose agent keeps them indefinitely
                AIAgent__c agent = getAgentWithRetention(conversation, agentsById);
                if (agent == null) continue;

                // [5] Check whether the retention is counted from creation
                Boolean isCountedFromCreation = agent.RetentionTrigger__c == AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE || agent.RetentionTrigger__c == AIAssistApplicationConstants.RETENTION_TRIGGER_LAST_MESSAGE_DATE;

                // [6] Set the expiry date from today
                if (isCountedFromCreation) {

                    conversation.RetentionExpiryDate__c = Datetime.now().dateGmt().addDays(Integer.valueOf(agent.ConversationRetentionDays__c));
                }
            }

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIConversationTriggerHandler', 'calculateRetentionExpiryDateOnCreate');
        }
    }

    // The conversations whose Status__c just changed to Closed, with their close time filled in.
    private static Map<Id, AIConversation__c> markConversationsNewlyClosed(Map<Id, AIConversation__c> oldConversationsById, Map<Id, AIConversation__c> newConversationsById) {

        // [1] Start with an empty result
        Map<Id, AIConversation__c> conversationsNewlyClosedById = new Map<Id, AIConversation__c>();

        // [2] Nothing to compare - no conversations or no old values
        if (newConversationsById == null || newConversationsById.isEmpty() || oldConversationsById == null) return conversationsNewlyClosedById;

        for (AIConversation__c newConversation : newConversationsById.values()) {

            // [3] Skip conversations with no old version
            AIConversation__c oldConversation = oldConversationsById.get(newConversation.Id);
            if (oldConversation == null) continue;

            // [4] Check whether the conversation was closed before and is closed now
            Boolean wasAlreadyClosed = oldConversation.Status__c == AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
            Boolean isNowClosed = newConversation.Status__c == AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;

            // [5] Only act the moment a conversation newly closes
            if (wasAlreadyClosed || !isNowClosed) continue;

            // [6] Stamp the close time if it has not been set
            if (newConversation.ConversationClosedTimestamp__c == null) {

                newConversation.ConversationClosedTimestamp__c = Datetime.now();
            }

            // [7] Add the conversation to the result
            conversationsNewlyClosedById.put(newConversation.Id, newConversation);
        }

        return conversationsNewlyClosedById;
    }

    // Retention counted from the close date can be calculated the moment a conversation newly closes.
    private static void calculateRetentionExpiryDateOnClose(Map<Id, AIConversation__c> oldConversationsById, Map<Id, AIConversation__c> conversationsNewlyClosedById) {

        try {

            // [1] Load the retention settings of the agents involved
            Map<Id, AIAgent__c> agentsById = getAgentsById(conversationsNewlyClosedById.values());

            for (AIConversation__c closedConversation : conversationsNewlyClosedById.values()) {

                // [2] Keep an expiry date that was set to a value in this update
                Boolean isExpiryDateSetToValue = closedConversation.RetentionExpiryDate__c != null && closedConversation.RetentionExpiryDate__c != oldConversationsById.get(closedConversation.Id).RetentionExpiryDate__c;
                if (isExpiryDateSetToValue) continue;

                // [3] Skip conversations whose agent keeps them indefinitely
                AIAgent__c agent = getAgentWithRetention(closedConversation, agentsById);
                if (agent == null) continue;

                // [4] Check whether the retention is counted from the close date
                Boolean isCountedFromClose = agent.RetentionTrigger__c == AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE && closedConversation.ConversationClosedTimestamp__c != null;

                // [5] Set the expiry date from the close date
                if (isCountedFromClose) {

                    closedConversation.RetentionExpiryDate__c = closedConversation.ConversationClosedTimestamp__c.dateGmt().addDays(Integer.valueOf(agent.ConversationRetentionDays__c));
                }
            }

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIConversationTriggerHandler', 'calculateRetentionExpiryDateOnClose');
        }
    }

    // The retention settings of every agent the conversations belong to.
    private static Map<Id, AIAgent__c> getAgentsById(List<AIConversation__c> conversations) {

        // [1] Collect the agent of each conversation
        Set<Id> agentIds = new Set<Id>();

        for (AIConversation__c conversation : conversations) {

            if (conversation.AIAgent__c != null) {

                agentIds.add(conversation.AIAgent__c);
            }
        }

        // [2] Load the agents
        return getAgentRetentionSettings(agentIds);
    }

    // The conversation's agent, or null when it has none or keeps its conversations indefinitely (blank, or less than one day).
    private static AIAgent__c getAgentWithRetention(AIConversation__c conversation, Map<Id, AIAgent__c> agentsById) {

        // [1] Find the agent of the conversation
        AIAgent__c agent = conversation.AIAgent__c == null ? null : agentsById.get(conversation.AIAgent__c);

        // [2] No agent, or no retention period, means keep indefinitely
        if (agent == null || agent.ConversationRetentionDays__c == null || agent.ConversationRetentionDays__c < 1) return null;

        return agent;
    }

    // The retention settings of the given agents, in one query.
    @TestVisible
    private static Map<Id, AIAgent__c> getAgentRetentionSettings(Set<Id> agentIds) {

        // [1] Nothing to load - no agents
        if (agentIds == null || agentIds.isEmpty()) return new Map<Id, AIAgent__c>();

        // [2] Load the agents
        return new Map<Id, AIAgent__c>([SELECT Id, ConversationRetentionDays__c, RetentionTrigger__c FROM AIAgent__c WHERE Id IN :agentIds WITH SYSTEM_MODE]);
    }
}
