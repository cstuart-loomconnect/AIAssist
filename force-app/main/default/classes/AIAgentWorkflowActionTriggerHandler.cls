/*
Class Name: AIAgentWorkflowActionTriggerHandler

=================================================================
=================================================================

Description: Fills in AIAgentWorkflowAction__c.AssignmentKey__c from the agent and the workflow action, before insert and before update. The field is unique, so the database then refuses one agent being given the same workflow action twice. A lookup cannot be made unique, which is why the key exists (docs/SECURITY_MODEL.md, section 6).

The key is always worked out again, so it cannot be typed in or left stale by an edit.

Safe in the subscriber's transactions: the trigger is on the package's own object, makes no query and
no DML, and cannot recurse. Not behind the application switch: a duplicate created while the
application is off would still be there when it is switched back on.

A failure is logged and the record still saves.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public inherited sharing class AIAgentWorkflowActionTriggerHandler {
  public class AIAgentWorkflowActionTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleBeforeInsert(
    List<AIAgentWorkflowAction__c> newRecords
  ) {
    stampKey(newRecords, 'handleBeforeInsert');
  }

  public static void handleBeforeUpdate(
    List<AIAgentWorkflowAction__c> newRecords
  ) {
    stampKey(newRecords, 'handleBeforeUpdate');
  }

  private static void stampKey(
    List<AIAgentWorkflowAction__c> newRecords,
    String methodName
  ) {
    try {
      if (isTestCustomExceptionThrown) {
        throw new AIAgentWorkflowActionTriggerHandlerException(
          'Test exception for AIAgentWorkflowActionTriggerHandler.' + methodName
        );
      }

      if (newRecords == null)
        return;

      for (AIAgentWorkflowAction__c link : newRecords)
        link.AssignmentKey__c = link.AIAgent__c == null ||
          link.AIWorkflowAction__c == null
          ? null
          : link.AIAgent__c + '|' + link.AIWorkflowAction__c;
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIAgentWorkflowActionTriggerHandler',
        methodName
      );
    }
  }
}
