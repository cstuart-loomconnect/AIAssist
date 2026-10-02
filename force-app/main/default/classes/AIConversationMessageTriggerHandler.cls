/*
Class Name: AIConversationMessageTriggerHandler

=================================================================
=================================================================

Description: Business logic that runs when an AIConversationMessage__c is saved.

Before insert: only the package may write a message from the AI Agent or the System. The AI Assist
User permission set can create messages and edit Sender, so without this check a user could insert
a message that looks like the assistant's. That would be shown to colleagues as the assistant's
words and replayed to the model as its own earlier answer, which is a way of steering it. Package
writes go through AIMessagingDataService, which marks itself as the package; anything else must be
a User message. This check is not behind the application switch: switching the application off
must not open a way to forge the assistant.

After insert: rolls the new messages up onto their conversations.
- ConversationTokenUsage__c grows by each message's TokenCount__c.
- LastMessageTimestamp__c moves to the newest User or AI Agent message.
- For an agent whose retention counts from the last message, RetentionExpiryDate__c moves forward
  from that message.
MessageCount__c is a native roll-up summary and needs nothing here.

The conversations are read FOR UPDATE and the totals added to what is stored, so messages inserted
into one conversation by different transactions at once add to each other instead of overwriting.

Safe in the subscriber's transactions: the trigger is on the package's own object and writes only
to AIConversation__c. A message already rolled up in this transaction (tracked by Id, not by a
single on/off flag, which would skip every chunk of 200 after the first) is never counted twice.

Failures are logged and the message still saves.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Run-once flag replaced by a set of handled Ids. Roll-up locks the parent rows. Sender integrity check, LastMessageTimestamp__c and Last Message Date retention added. Methods shortened.
3.0          Chandler Stuart          Restructured to the standard pattern: the trigger only routes by context to handleBeforeInsert, handleAfterUpdate and so on, each handler has its own exception type and a test seam, and a failure is logged and never stops the save.
*/

public inherited sharing class AIConversationMessageTriggerHandler {
  public class AIConversationMessageTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  private static Set<Id> handledMessageIds = new Set<Id>();

  // Not behind the application switch: switching the application off must not open a way to forge the assistant. If the check itself fails, every message is refused rather than let through.
  public static void handleBeforeInsert(
    List<AIConversationMessage__c> newMessages
  ) {
    try {
      if (newMessages == null || AIMessagingDataService.isPackageWriting())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIConversationMessageTriggerHandlerException(
          'Test exception for AIConversationMessageTriggerHandler.handleBeforeInsert'
        );
      }

      for (AIConversationMessage__c message : newMessages) {
        if (message.Sender__c == null)
          message.Sender__c = AIAssistApplicationConstants.SENDER_USER;

        if (message.Sender__c != AIAssistApplicationConstants.SENDER_USER)
          message.addError(Label.AI_Error_Not_Authorised);
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIConversationMessageTriggerHandler',
        'handleBeforeInsert'
      );
      for (AIConversationMessage__c message : newMessages)
        message.addError(Label.AI_Error_Generic);
    }
  }

  public static void handleAfterInsert(
    List<AIConversationMessage__c> newMessages
  ) {
    try {
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIConversationMessageTriggerHandlerException(
          'Test exception for AIConversationMessageTriggerHandler.handleAfterInsert'
        );
      }

      if (newMessages == null || newMessages.isEmpty())
        return;

      Map<Id, Decimal> tokensByConversationId = new Map<Id, Decimal>();
      Map<Id, Datetime> lastMessageByConversationId = new Map<Id, Datetime>();

      for (AIConversationMessage__c message : newMessages) {
        if (
          message.AIConversation__c == null ||
          handledMessageIds.contains(message.Id)
        )
          continue;
        handledMessageIds.add(message.Id);

        if (message.TokenCount__c != null && message.TokenCount__c > 0) {
          tokensByConversationId.put(
            message.AIConversation__c,
            (tokensByConversationId.containsKey(message.AIConversation__c)
              ? tokensByConversationId.get(message.AIConversation__c)
              : 0) + message.TokenCount__c
          );
        }

        // The failed-turn System message records tokens; it is not a conversation event, so it does not move the last message time.
        if (
          message.Sender__c != AIAssistApplicationConstants.SENDER_SYSTEM &&
          message.CreatedDate != null &&
          (!lastMessageByConversationId.containsKey(
            message.AIConversation__c
          ) ||
          message.CreatedDate >
          lastMessageByConversationId.get(message.AIConversation__c))
        ) {
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

      List<AIConversation__c> conversations = AIMessagingSelector.lockConversationsForRollup(
        conversationIds
      );

      Set<Id> agentIds = new Set<Id>();
      for (AIConversation__c conversation : conversations) {
        if (conversation.AIAgent__c != null)
          agentIds.add(conversation.AIAgent__c);
      }

      Map<Id, AIAgent__c> agentsById = AIMessagingSelector.getAgentRetentionSettings(
        agentIds
      );
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

          if (
            agent != null &&
            agent.RetentionTrigger__c ==
            AIAssistApplicationConstants.RETENTION_TRIGGER_LAST_MESSAGE_DATE &&
            agent.ConversationRetentionDays__c != null &&
            agent.ConversationRetentionDays__c >= 1
          ) {
            rollup.RetentionExpiryDate__c = newestMessage.dateGmt()
              .addDays(Integer.valueOf(agent.ConversationRetentionDays__c));
          }
        }

        if (hasChange)
          conversationsToUpdate.add(rollup);
      }

      AIMessagingDataService.updateAndLogFailures(
        conversationsToUpdate,
        'AIConversationMessageTriggerHandler',
        'handleAfterInsert'
      );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIConversationMessageTriggerHandler',
        'handleAfterInsert'
      );
    }
  }
}
