/*
Class Name: AIAgentTriggerHandler

=================================================================
=================================================================

Description: Stamps the Public Id and Developer Name on a new agent. The Public Id is how an external system refers to the agent; the Developer Name is its unique External Id, derived from its name so it can move between orgs.

Safe in the subscriber's transactions: the trigger is on the package's own AIAgent__c object, does no
DML of its own and cannot recurse. It does nothing while AIAssistSettings__c.IsEnabled__c is off.
A failure is logged and the record still saves.

An agent the plan does not include (too many active, or a retention longer than the cap) is refused with the plan label; see AIPlanActivationService.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
3.0          Chandler Stuart          Restructured to the standard pattern: the trigger only routes by context to handleBeforeInsert, handleAfterUpdate and so on, each handler has its own exception type and a test seam, and a failure is logged and never stops the save.
4.0          Chandler Stuart          Plan check added, before insert and before update. It is not behind the application switch and it does stop the save.
5.0          Chandler Stuart          After update: a change to the retention settings recalculates the expiry date of the agent's conversations in a batch.
*/

public inherited sharing class AIAgentTriggerHandler {
  public class AIAgentTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleBeforeInsert(List<AIAgent__c> newRecords) {
    AIPlanActivationService.checkAgents(newRecords, null);

    try {
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIAgentTriggerHandlerException(
          'Test exception for AIAgentTriggerHandler.handleBeforeInsert'
        );
      }

      if (newRecords == null || newRecords.isEmpty())
        return;

      AIAssistGlobalUtility.generatePublicId(newRecords);
      AIAssistGlobalUtility.generateDeveloperName(newRecords);
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIAgentTriggerHandler',
        'handleBeforeInsert'
      );
    }
  }

  // Only the plan check: identifiers are stamped once, on insert.
  public static void handleBeforeUpdate(
    Map<Id, AIAgent__c> oldRecordsById,
    List<AIAgent__c> newRecords
  ) {
    AIPlanActivationService.checkAgents(newRecords, oldRecordsById);
  }

  // A change to an agent's retention settings is applied to the conversations it already has, in a batch (AIConversationRetentionRecalcBatch). Not behind the application switch: retention is housekeeping. A failure to start the batch is logged and the agent still saves.
  public static void handleAfterUpdate(
    Map<Id, AIAgent__c> oldRecordsById,
    List<AIAgent__c> newRecords
  ) {
    try {
      if (isTestCustomExceptionThrown) {
        throw new AIAgentTriggerHandlerException(
          'Test exception for AIAgentTriggerHandler.handleAfterUpdate'
        );
      }

      if (oldRecordsById == null || newRecords == null)
        return;

      Set<Id> changedAgentIds = new Set<Id>();
      for (AIAgent__c agent : newRecords) {
        AIAgent__c previous = oldRecordsById.get(agent.Id);
        if (
          previous != null &&
          (agent.ConversationRetentionDays__c !=
          previous.ConversationRetentionDays__c ||
          agent.RetentionTrigger__c != previous.RetentionTrigger__c)
        )
          changedAgentIds.add(agent.Id);
      }

      if (!changedAgentIds.isEmpty())
        Database.executeBatch(
          new AIConversationRetentionRecalcBatch(changedAgentIds),
          AIAssistApplicationConstants.HOUSEKEEPING_BATCH_SIZE
        );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIAgentTriggerHandler',
        'handleAfterUpdate'
      );
    }
  }
}
