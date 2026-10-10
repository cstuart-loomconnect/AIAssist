/*
Class Name: AIConversationTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Conversation events related to AI Assist,
performing the business logic that runs on the AI Conversation trigger.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIConversationTriggerHandler {
  public class AIConversationTriggerHandlerException extends Exception {
  }

  private static Boolean isBeforeInsertHandlerRunning = false;
  private static Boolean isBeforeUpdateHandlerRunning = false;

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleBeforeInsert(
    List<AIConversation__c> newConversations
  ) {
    try {
      if (!isBeforeInsertHandlerRunning) {
        isBeforeInsertHandlerRunning = true;

        if (isTestCustomExceptionThrown) {
          throw new AIConversationTriggerHandlerException(
            'Test exception for AIConversationTriggerHandler.handleBeforeInsert'
          );
        }

        if (newConversations != null && !newConversations.isEmpty()) {
          calculateRetentionExpiryDateOnCreate(newConversations);
        }

        isBeforeInsertHandlerRunning = false;
      }
    } catch (Exception e) {
      AIPlatformLogManager.logException(
        e,
        'AIConversationTriggerHandler',
        'handleBeforeInsert'
      );
    }
  }

  public static void handleBeforeUpdate(
    Map<Id, AIConversation__c> oldConversationsById,
    Map<Id, AIConversation__c> newConversationsById
  ) {
    try {
      if (!isBeforeUpdateHandlerRunning) {
        isBeforeUpdateHandlerRunning = true;

        if (isTestCustomExceptionThrown) {
          throw new AIConversationTriggerHandlerException(
            'Test exception for AIConversationTriggerHandler.handleBeforeUpdate'
          );
        }

        Map<Id, AIConversation__c> conversationsNewlyClosedById = markConversationsNewlyClosed(
          oldConversationsById,
          newConversationsById
        );

        if (!conversationsNewlyClosedById.isEmpty()) {
          calculateRetentionExpiryDateOnClose(conversationsNewlyClosedById);
        }

        isBeforeUpdateHandlerRunning = false;
      }
    } catch (Exception e) {
      AIPlatformLogManager.logException(
        e,
        'AIConversationTriggerHandler',
        'handleBeforeUpdate'
      );
    }
  }

  // Retention counted from the creation date, or from the last message (which starts at creation), is known as soon as the conversation is created.
  private static void calculateRetentionExpiryDateOnCreate(
    List<AIConversation__c> newConversations
  ) {
    try {
      if (newConversations == null || newConversations.isEmpty())
        return;

      Map<Id, AIAgent__c> agentsById = getAgentsById(newConversations);

      for (AIConversation__c conversation : newConversations) {
        AIAgent__c agent = getAgentWithRetention(conversation, agentsById);
        if (agent == null)
          continue;

        Boolean isCountedFromCreation =
          agent.RetentionTrigger__c ==
          AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE ||
          agent.RetentionTrigger__c ==
          AIAssistApplicationConstants.RETENTION_TRIGGER_LAST_MESSAGE_DATE;

        if (isCountedFromCreation) {
          conversation.RetentionExpiryDate__c = Datetime.now()
            .dateGmt()
            .addDays(Integer.valueOf(agent.ConversationRetentionDays__c));
        }
      }
    } catch (Exception e) {
      AIPlatformLogManager.logException(
        e,
        'AIConversationTriggerHandler',
        'calculateRetentionExpiryDateOnCreate'
      );
    }
  }

  // The conversations whose Status__c just changed to Closed, with their close time filled in.
  private static Map<Id, AIConversation__c> markConversationsNewlyClosed(
    Map<Id, AIConversation__c> oldConversationsById,
    Map<Id, AIConversation__c> newConversationsById
  ) {
    Map<Id, AIConversation__c> conversationsNewlyClosedById = new Map<Id, AIConversation__c>();

    if (
      newConversationsById == null ||
      newConversationsById.isEmpty() ||
      oldConversationsById == null
    )
      return conversationsNewlyClosedById;

    for (AIConversation__c newConversation : newConversationsById.values()) {
      AIConversation__c oldConversation = oldConversationsById.get(
        newConversation.Id
      );
      if (oldConversation == null)
        continue;

      Boolean wasAlreadyClosed =
        oldConversation.Status__c ==
        AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
      Boolean isNowClosed =
        newConversation.Status__c ==
        AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;

      if (wasAlreadyClosed || !isNowClosed)
        continue; // Only act the moment a conversation newly closes.

      if (newConversation.ConversationClosedTimestamp__c == null) {
        newConversation.ConversationClosedTimestamp__c = Datetime.now();
      }

      conversationsNewlyClosedById.put(newConversation.Id, newConversation);
    }

    return conversationsNewlyClosedById;
  }

  // Retention counted from the close date can be calculated the moment a conversation newly closes.
  private static void calculateRetentionExpiryDateOnClose(
    Map<Id, AIConversation__c> conversationsNewlyClosedById
  ) {
    try {
      Map<Id, AIAgent__c> agentsById = getAgentsById(
        conversationsNewlyClosedById.values()
      );

      for (
        AIConversation__c closedConversation : conversationsNewlyClosedById.values()
      ) {
        AIAgent__c agent = getAgentWithRetention(
          closedConversation,
          agentsById
        );
        if (agent == null)
          continue;

        Boolean isCountedFromClose =
          agent.RetentionTrigger__c ==
          AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE &&
          closedConversation.ConversationClosedTimestamp__c != null;

        if (isCountedFromClose) {
          closedConversation.RetentionExpiryDate__c = closedConversation.ConversationClosedTimestamp__c.dateGmt()
            .addDays(Integer.valueOf(agent.ConversationRetentionDays__c));
        }
      }
    } catch (Exception e) {
      AIPlatformLogManager.logException(
        e,
        'AIConversationTriggerHandler',
        'calculateRetentionExpiryDateOnClose'
      );
    }
  }

  private static Map<Id, AIAgent__c> getAgentsById(
    List<AIConversation__c> conversations
  ) {
    Set<Id> agentIds = new Set<Id>();

    for (AIConversation__c conversation : conversations) {
      if (conversation.AIAgent__c != null) {
        agentIds.add(conversation.AIAgent__c);
      }
    }

    return getAgentRetentionSettings(agentIds);
  }

  // The conversation's agent, or null when it has none or keeps its conversations indefinitely (blank, or less than one day).
  private static AIAgent__c getAgentWithRetention(
    AIConversation__c conversation,
    Map<Id, AIAgent__c> agentsById
  ) {
    AIAgent__c agent = conversation.AIAgent__c == null
      ? null
      : agentsById.get(conversation.AIAgent__c);

    if (
      agent == null ||
      agent.ConversationRetentionDays__c == null ||
      agent.ConversationRetentionDays__c < 1
    )
      return null;

    return agent;
  }

  @TestVisible
  private static Map<Id, AIAgent__c> getAgentRetentionSettings(
    Set<Id> agentIds
  ) {
    if (agentIds == null || agentIds.isEmpty())
      return new Map<Id, AIAgent__c>();

    return new Map<Id, AIAgent__c>(
      [
        SELECT Id, ConversationRetentionDays__c, RetentionTrigger__c
        FROM AIAgent__c
        WHERE Id IN :agentIds
        WITH SYSTEM_MODE
      ]
    );
  }
}
