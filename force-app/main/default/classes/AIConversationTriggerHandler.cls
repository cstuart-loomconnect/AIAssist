/*
Class Name: AIConversationTriggerHandler

=================================================================
=================================================================

Description: Business logic that runs before an AIConversation__c is saved.

Insert:  stamps PublicId__c and calculates RetentionExpiryDate__c from the agent's retention
         settings.
Update:  the moment a conversation becomes Closed, stamps ConversationClosedTimestamp__c (the
         model's validation rule requires it with the close reason) and, for an agent that counts
         retention from the close, calculates RetentionExpiryDate__c.

Retention starts from one of three events, chosen on the agent (RetentionTrigger__c):
- Conversation Created Date: the day the conversation is created.
- Conversation Closed Date:  the day it is closed. Until then it has no expiry.
- Last Message Date:         the day of the latest message. It starts from the creation date and
                             AIConversationMessageTriggerHandler moves it forward with every
                             message, so a conversation that never gets a message still expires.
A blank ConversationRetentionDays__c on the agent means keep indefinitely.

Dates are calculated in GMT so the result does not depend on the timezone of whoever saves the record.

Safe in the subscriber's transactions: the trigger is on the package's own object, does no DML of
its own, and cannot recurse. A record already handled in this transaction (tracked by Id, not a
single on/off flag, which would skip every chunk of 200 after the first) is not handled twice.

Failures are logged and the record still saves: a missing retention date must not stop a user
starting a conversation.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Run-once flags replaced by a set of handled Ids. Last Message Date retention starts from creation. Dates in GMT. Agent retention read through AIMessagingSelector. Methods shortened.
3.0          Chandler Stuart          Restructured to the standard pattern: the trigger only routes by context to handleBeforeInsert, handleAfterUpdate and so on, each handler has its own exception type and a test seam, and a failure is logged and never stops the save.
*/

public inherited sharing class AIConversationTriggerHandler {
  public class AIConversationTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  private static Set<Id> closedIdsHandled = new Set<Id>();

  public static void handleBeforeInsert(
    List<AIConversation__c> newConversations
  ) {
    try {
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIConversationTriggerHandlerException(
          'Test exception for AIConversationTriggerHandler.handleBeforeInsert'
        );
      }

      if (newConversations == null || newConversations.isEmpty())
        return;

      AIAssistGlobalUtility.generatePublicId(newConversations);

      Set<Id> agentIds = new Set<Id>();
      for (AIConversation__c conversation : newConversations) {
        if (conversation.AIAgent__c != null)
          agentIds.add(conversation.AIAgent__c);
      }

      Map<Id, AIAgent__c> agentsById = AIMessagingSelector.getAgentRetentionSettings(
        agentIds
      );

      // Retention counted from the creation date, or from the last message (which starts at creation), is known now.
      for (AIConversation__c conversation : newConversations) {
        AIAgent__c agent = conversation.AIAgent__c == null
          ? null
          : agentsById.get(conversation.AIAgent__c);
        if (
          agent == null ||
          agent.ConversationRetentionDays__c == null ||
          agent.ConversationRetentionDays__c < 1
        )
          continue; // Blank means retain indefinitely.

        if (
          agent.RetentionTrigger__c ==
          AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE ||
          agent.RetentionTrigger__c ==
          AIAssistApplicationConstants.RETENTION_TRIGGER_LAST_MESSAGE_DATE
        ) {
          conversation.RetentionExpiryDate__c = Datetime.now()
            .dateGmt()
            .addDays(Integer.valueOf(agent.ConversationRetentionDays__c));
        }
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
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
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIConversationTriggerHandlerException(
          'Test exception for AIConversationTriggerHandler.handleBeforeUpdate'
        );
      }

      if (
        newConversationsById == null ||
        newConversationsById.isEmpty() ||
        oldConversationsById == null
      )
        return;

      List<AIConversation__c> newlyClosed = new List<AIConversation__c>();

      for (AIConversation__c newConversation : newConversationsById.values()) {
        AIConversation__c oldConversation = oldConversationsById.get(
          newConversation.Id
        );

        // Only the moment a conversation newly closes, and only once per transaction.
        if (
          oldConversation == null ||
          oldConversation.Status__c ==
          AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED ||
          newConversation.Status__c !=
          AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED ||
          closedIdsHandled.contains(newConversation.Id)
        )
          continue;

        closedIdsHandled.add(newConversation.Id);
        if (newConversation.ConversationClosedTimestamp__c == null)
          newConversation.ConversationClosedTimestamp__c = Datetime.now();
        newlyClosed.add(newConversation);
      }

      if (newlyClosed.isEmpty())
        return;

      Set<Id> agentIds = new Set<Id>();
      for (AIConversation__c closedConversation : newlyClosed) {
        if (closedConversation.AIAgent__c != null)
          agentIds.add(closedConversation.AIAgent__c);
      }

      Map<Id, AIAgent__c> agentsById = AIMessagingSelector.getAgentRetentionSettings(
        agentIds
      );

      // Retention counted from the close date can be calculated now that the conversation has closed.
      for (AIConversation__c closedConversation : newlyClosed) {
        AIAgent__c agent = closedConversation.AIAgent__c == null
          ? null
          : agentsById.get(closedConversation.AIAgent__c);
        if (
          agent == null ||
          agent.ConversationRetentionDays__c == null ||
          agent.ConversationRetentionDays__c < 1
        )
          continue; // Blank means retain indefinitely.

        if (
          agent.RetentionTrigger__c ==
          AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE &&
          closedConversation.ConversationClosedTimestamp__c != null
        ) {
          closedConversation.RetentionExpiryDate__c = closedConversation.ConversationClosedTimestamp__c.dateGmt()
            .addDays(Integer.valueOf(agent.ConversationRetentionDays__c));
        }
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIConversationTriggerHandler',
        'handleBeforeUpdate'
      );
    }
  }
}
