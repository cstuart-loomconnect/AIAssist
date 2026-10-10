/*
Class Name: AIConversationMessageTriggerHandler

=================================================================
=================================================================

Description: Rolls new AI Conversation Messages up onto their AI Conversation.

Step 1: Skip if the handler is already running in this transaction
Step 2: Keep only the messages that belong to a conversation
Step 3: Lock the conversations and work out the new token total and last message time
Step 4: Move the retention expiry for agents that count from the last message
Step 5: Update the conversations and log any failures

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

  // Runs after messages are inserted and rolls them up onto their conversations. Never blocks the save.
  public static void handleAfterInsert(
    List<AIConversationMessage__c> newMessages
  ) {
    try {
      // [1] Do nothing if the handler is already running in this transaction
      if (isAfterInsertHandlerRunning)
        return;

      isAfterInsertHandlerRunning = true;

      // [2] Throw on purpose when a test asks for it
      if (isTestCustomExceptionThrown) {
        throw new AIConversationMessageTriggerHandlerException(
          'Test exception for AIConversationMessageTriggerHandler.handleAfterInsert'
        );
      }

      // [3] Roll up the messages that belong to a conversation
      List<AIConversationMessage__c> messagesToRollUp = getMessagesInAConversation(
        newMessages
      );

      if (!messagesToRollUp.isEmpty()) {
        rollUpMessagesOntoConversations(messagesToRollUp);
      }

      // [4] Allow the handler to run again
      isAfterInsertHandlerRunning = false;
    } catch (Exception ex) {
      AIPlatformLogManager.logException(
        ex,
        'AIConversationMessageTriggerHandler',
        'handleAfterInsert'
      );
    }
  }

  // The messages that belong to a conversation.
  private static List<AIConversationMessage__c> getMessagesInAConversation(
    List<AIConversationMessage__c> newMessages
  ) {
    // [1] Start with an empty list so a null input returns nothing
    List<AIConversationMessage__c> messagesToRollUp = new List<AIConversationMessage__c>();

    if (newMessages == null)
      return messagesToRollUp;

    // [2] Keep each message that has a conversation
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
      // [1] Work out the tokens to add and the newest message time for each conversation
      Map<Id, Decimal> tokensByConversationId = new Map<Id, Decimal>();
      Map<Id, Datetime> lastMessageByConversationId = new Map<Id, Datetime>();

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

        // [2] The failed-turn System message records tokens but is not a conversation event, so it does not move the last message time
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

      // [3] Nothing to change if no conversation has tokens or a new message time
      Set<Id> conversationIds = new Set<Id>(tokensByConversationId.keySet());
      conversationIds.addAll(lastMessageByConversationId.keySet());

      if (conversationIds.isEmpty())
        return;

      // [4] Lock the conversations so two transactions add to each other instead of overwriting
      List<AIConversation__c> conversations = lockConversationsForRollup(
        conversationIds
      );

      // [5] Load the retention settings of the agents on those conversations
      Set<Id> agentIds = new Set<Id>();

      for (AIConversation__c conversation : conversations) {
        if (conversation.AIAgent__c != null) {
          agentIds.add(conversation.AIAgent__c);
        }
      }

      Map<Id, AIAgent__c> agentsById = getAgentRetentionSettings(agentIds);
      List<AIConversation__c> conversationsToUpdate = new List<AIConversation__c>();

      // [6] Build the update for each conversation that changes
      for (AIConversation__c conversation : conversations) {
        AIConversation__c rollup = new AIConversation__c(Id = conversation.Id);
        Decimal tokensAdded = tokensByConversationId.get(conversation.Id);
        Datetime newestMessage = lastMessageByConversationId.get(
          conversation.Id
        );
        Boolean hasChange = false;

        // [7] Add the new tokens to the running total
        if (tokensAdded != null) {
          rollup.ConversationTokenUsage__c =
            (conversation.ConversationTokenUsage__c == null
              ? 0
              : conversation.ConversationTokenUsage__c) + tokensAdded;
          hasChange = true;
        }

        // [8] Move the last message time forward only when the new message is newer
        if (
          newestMessage != null &&
          (conversation.LastMessageTimestamp__c == null ||
          newestMessage > conversation.LastMessageTimestamp__c)
        ) {
          rollup.LastMessageTimestamp__c = newestMessage;
          hasChange = true;

          // [9] Move the retention expiry when the agent counts retention from the last message
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

      // [10] Save the changes and log any that fail
      AIMessagingDataService.updateAndLogFailures(
        conversationsToUpdate,
        'AIConversationMessageTriggerHandler',
        'rollUpMessagesOntoConversations'
      );
    } catch (Exception ex) {
      AIPlatformLogManager.logException(
        ex,
        'AIConversationMessageTriggerHandler',
        'rollUpMessagesOntoConversations'
      );
    }
  }

  // The retention settings of the agents with these ids.
  @TestVisible
  private static Map<Id, AIAgent__c> getAgentRetentionSettings(
    Set<Id> agentIds
  ) {
    // [1] Nothing to look up
    if (agentIds == null || agentIds.isEmpty())
      return new Map<Id, AIAgent__c>();

    // [2] Query the agents
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
    // [1] Nothing to lock
    if (conversationIds == null || conversationIds.isEmpty())
      return new List<AIConversation__c>();

    // [2] Query and lock the conversations
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
