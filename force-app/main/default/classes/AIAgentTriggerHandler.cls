/*
Class Name: AIAgentTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Agent events related to AI Assist,
performing the business logic that runs on the AI Agent trigger.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAgentTriggerHandler {
  public class AIAgentTriggerHandlerException extends Exception {
  }

  private static Boolean isAfterUpdateHandlerRunning = false;

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleAfterUpdate(
    Map<Id, AIAgent__c> oldAgentsById,
    List<AIAgent__c> newAgents
  ) {
    try {
      if (!isAfterUpdateHandlerRunning) {
        isAfterUpdateHandlerRunning = true;

        if (isTestCustomExceptionThrown) {
          throw new AIAgentTriggerHandlerException(
            'Test exception for AIAgentTriggerHandler.handleAfterUpdate'
          );
        }

        Map<Id, AIAgent__c> agentsWithChangedRetentionById = getAgentsWithChangedRetention(
          oldAgentsById,
          newAgents
        );

        if (!agentsWithChangedRetentionById.isEmpty()) {
          Database.executeBatch(
            new AIConversationRetentionRecalcBatch(
              agentsWithChangedRetentionById.keySet()
            ),
            AIAssistApplicationConstants.HOUSEKEEPING_BATCH_SIZE
          );
        }

        isAfterUpdateHandlerRunning = false;
      }
    } catch (Exception e) {
      AIPlatformLogManager.logException(
        e,
        'AIAgentTriggerHandler',
        'handleAfterUpdate'
      );
    }
  }

  // Agents whose retention days or retention trigger just changed.
  private static Map<Id, AIAgent__c> getAgentsWithChangedRetention(
    Map<Id, AIAgent__c> oldAgentsById,
    List<AIAgent__c> newAgents
  ) {
    Map<Id, AIAgent__c> agentsWithChangedRetentionById = new Map<Id, AIAgent__c>();

    if (oldAgentsById == null || newAgents == null)
      return agentsWithChangedRetentionById;

    for (AIAgent__c newAgent : newAgents) {
      AIAgent__c oldAgent = oldAgentsById.get(newAgent.Id);
      if (oldAgent == null)
        continue;

      Boolean hasRetentionChanged =
        newAgent.ConversationRetentionDays__c !=
        oldAgent.ConversationRetentionDays__c ||
        newAgent.RetentionTrigger__c != oldAgent.RetentionTrigger__c;
      if (hasRetentionChanged) {
        agentsWithChangedRetentionById.put(newAgent.Id, newAgent);
      }
    }

    return agentsWithChangedRetentionById;
  }
}
