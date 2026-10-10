/*
Class Name: AIConversationMessageTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Conversation Message events related to AI Assist,
performing the business logic that runs on the AI Conversation Message trigger.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIConversationMessageTriggerHandler {
  public class AIConversationMessageTriggerHandlerException extends Exception {
  }

  private static Boolean isAfterInsertHandlerRunning = false;

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleAfterInsert(
    List<AIConversationMessage__c> newMessages
  ) {
    try {
      if (!isAfterInsertHandlerRunning) {
        isAfterInsertHandlerRunning = true;

        if (isTestCustomExceptionThrown) {
          throw new AIConversationMessageTriggerHandlerException(
            'Test exception for AIConversationMessageTriggerHandler.handleAfterInsert'
          );
        }

        List<AIConversationMessage__c> messagesToRollUp = getMessagesInAConversation(
          newMessages
        );

        if (!messagesToRollUp.isEmpty()) {
          rollUpMessagesOntoConversations(messagesToRollUp);
        }

        isAfterInsertHandlerRunning = false;
      }
    } catch (Exception e) {
      AIPlatformLogManager.logException(
        e,
        'AIConversationMessageTriggerHandler',
        'handleAfterInsert'
      );
    }
  }

  // The messages that belong to a conversation.
  private static List<AIConversationMessage__c> getMessagesInAConversation(
    List<AIConversationMessage__c> newMessages
  ) {
    List<AIConversationMessage__c> messagesToRollUp = new List<AIConversationMessage__c>();

    if (newMessages == null)
      return messagesToRollUp;

    for (AIConversationMessage__c message : newMessages) {
      if (message.AIConversation__c == null)
        continue;

      messagesToRollUp.add(message);
    }

    return messagesToRollUp;
  }

  // Adds each message's tokens to its conversation's total and moves the conversation's last message time (and, for an agent that keeps conversations from the last message, its retention date).
  private static void rollUpMessagesOntoConversations(
    List<AIConversationMessage__c> messagesToRollUp
  ) {
    try {
      Map<Id, Decimal> tokensByConversationId = new Map<Id, Decimal>(); // Conversations that have tokens to add.
      Map<Id, Datetime> lastMessageByConversationId = new Map<Id, Datetime>(); // Conversations whose last message time moves.

      for (AIConversationMessage__c message : messagesToRollUp) {
        if (message.TokenCount__c != null && message.TokenCount__c > 0) {
          Decimal tokensSoFar = tokensByConversationId.containsKey(
              message.AIConversation__c
            )
            ? tokensByConversationId.get(message.AIConversation__c)
            : 0;
          tokensByConversationId.put(
            message.AIConversation__c,
            tokensSoFar + message.TokenCount__c
          );
        }

        // The failed-turn System message records tokens; it is not a conversation event, so it does not move the last message time.
        Boolean movesLastMessageTime =
          message.Sender__c != AIAssistApplicationConstants.SENDER_SYSTEM &&
          message.CreatedDate != null;
        Boolean isNewest =
          !lastMessageByConversationId.containsKey(message.AIConversation__c) ||
          message.CreatedDate >
          lastMessageByConversationId.get(message.AIConversation__c);

        if (movesLastMessageTime && isNewest) {
          lastMessageByConversationId.put(
            message.AIConversation__c,
            message.CreatedDate
          );
        }
      }

      Set<Id> conversationIds = new Set<Id>(tokensByConversationId.keySet());
      conversationIds.addAll(lastMessageByConversationId.keySet());

      if (conversationIds.isEmpty())
        return;

      List<AIConversation__c> conversations = lockConversationsForRollup(
        conversationIds
      );

      Set<Id> agentIds = new Set<Id>();

      for (AIConversation__c conversation : conversations) {
        if (conversation.AIAgent__c != null) {
          agentIds.add(conversation.AIAgent__c);
        }
      }

      Map<Id, AIAgent__c> agentsById = getAgentRetentionSettings(agentIds);
      List<AIConversation__c> conversationsToUpdate = new List<AIConversation__c>();

      for (AIConversation__c conversation : conversations) {
        AIConversation__c rollup = new AIConversation__c(Id = conversation.Id);
        Decimal tokensAdded = tokensByConversationId.get(conversation.Id);
        Datetime newestMessage = lastMessageByConversationId.get(
          conversation.Id
        );
        Boolean hasChange = false;

        if (tokensAdded != null) {
          rollup.ConversationTokenUsage__c =
            (conversation.ConversationTokenUsage__c == null
              ? 0
              : conversation.ConversationTokenUsage__c) + tokensAdded;
          hasChange = true;
        }

        if (
          newestMessage != null &&
          (conversation.LastMessageTimestamp__c == null ||
          newestMessage > conversation.LastMessageTimestamp__c)
        ) {
          rollup.LastMessageTimestamp__c = newestMessage;
          hasChange = true;

          AIAgent__c agent = conversation.AIAgent__c == null
            ? null
            : agentsById.get(conversation.AIAgent__c);
          Boolean isCountedFromLastMessage =
            agent != null &&
            agent.RetentionTrigger__c ==
            AIAssistApplicationConstants.RETENTION_TRIGGER_LAST_MESSAGE_DATE &&
            agent.ConversationRetentionDays__c != null &&
            agent.ConversationRetentionDays__c >= 1;

          if (isCountedFromLastMessage) {
            rollup.RetentionExpiryDate__c = newestMessage.dateGmt()
              .addDays(Integer.valueOf(agent.ConversationRetentionDays__c));
          }
        }

        if (hasChange) {
          conversationsToUpdate.add(rollup);
        }
      }

      AIMessagingDataService.updateAndLogFailures(
        conversationsToUpdate,
        'AIConversationMessageTriggerHandler',
        'rollUpMessagesOntoConversations'
      );
    } catch (Exception e) {
      AIPlatformLogManager.logException(
        e,
        'AIConversationMessageTriggerHandler',
        'rollUpMessagesOntoConversations'
      );
    }
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

  // The conversations a batch of messages belongs to, locked while their totals change, so two transactions inserting into one conversation add to each other instead of overwriting.
  @TestVisible
  private static List<AIConversation__c> lockConversationsForRollup(
    Set<Id> conversationIds
  ) {
    if (conversationIds == null || conversationIds.isEmpty())
      return new List<AIConversation__c>();

    return [
      SELECT
        Id,
        ConversationTokenUsage__c,
        LastMessageTimestamp__c,
        RetentionExpiryDate__c,
        AIAgent__c
      FROM AIConversation__c
      WHERE Id IN :conversationIds
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
  }
}
