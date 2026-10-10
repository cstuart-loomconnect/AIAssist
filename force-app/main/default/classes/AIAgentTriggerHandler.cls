/*
Class Name: AIAgentTriggerHandler

=================================================================
=================================================================

Description: Runs the business logic for the AI Agent trigger.

Step 1: After an agent update, skip if this handler is already running
Step 2: Find the agents whose retention days or retention trigger changed
Step 3: Start the retention recalculation batch for those agents

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

  // Starts the retention recalculation for agents whose retention settings changed.
  public static void handleAfterUpdate(
    Map<Id, AIAgent__c> oldAgentsById,
    List<AIAgent__c> newAgents
  ) {
    try {
      // [1] Do nothing if this handler is already running, so the update cannot loop
      if (!isAfterUpdateHandlerRunning) {
        isAfterUpdateHandlerRunning = true;

        if (isTestCustomExceptionThrown)
          throw new AIAgentTriggerHandlerException(
            'Test exception for AIAgentTriggerHandler.handleAfterUpdate'
          );

        // [2] Find the agents whose retention settings changed
        Map<Id, AIAgent__c> agentsWithChangedRetentionById = getAgentsWithChangedRetention(
          oldAgentsById,
          newAgents
        );

        // [3] Start the recalculation batch for those agents
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
    } catch (Exception ex) {
      AIPlatformLogManager.logException(
        ex,
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
    // [1] Start with an empty result so a failure still returns something safe
    Map<Id, AIAgent__c> agentsWithChangedRetentionById = new Map<Id, AIAgent__c>();

    try {
      // [2] Stop if either list is missing
      if (oldAgentsById == null || newAgents == null)
        throw new AIAgentTriggerHandlerException(
          'Invalid input: oldAgentsById and newAgents cannot be null.'
        );

      // [3] Compare each agent with its old version and keep the ones whose retention changed
      for (AIAgent__c newAgent : newAgents) {
        AIAgent__c oldAgent = oldAgentsById.get(newAgent.Id);

        if (oldAgent == null)
          continue;

        Boolean hasRetentionChanged =
          newAgent.ConversationRetentionDays__c !=
          oldAgent.ConversationRetentionDays__c ||
          newAgent.RetentionTrigger__c != oldAgent.RetentionTrigger__c;

        if (hasRetentionChanged)
          agentsWithChangedRetentionById.put(newAgent.Id, newAgent);
      }
    } catch (Exception ex) {
      AIPlatformLogManager.logException(
        ex,
        'AIAgentTriggerHandler',
        'getAgentsWithChangedRetention'
      );
      return agentsWithChangedRetentionById;
    }

    // [4] Return the agents that changed
    return agentsWithChangedRetentionById;
  }
}
