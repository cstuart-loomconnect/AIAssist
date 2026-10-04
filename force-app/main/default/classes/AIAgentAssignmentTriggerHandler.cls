/*
Class Name: AIAgentAssignmentTriggerHandler

=================================================================
=================================================================

Description: Fills in AIAgentAssignment__c.AssignmentKey__c from the agent and who it is assigned to (the user, or the permission set by name), before insert and before update. The field is unique, so the database then refuses the same user or permission set being assigned to one agent twice. A lookup cannot be made unique, which is why the key exists (docs/SECURITY_MODEL.md, section 6).

The key is always worked out again, so it cannot be typed in or left stale by an edit.

Safe in the subscriber's transactions: the trigger is on the package's own object, makes no query and
no DML, and cannot recurse. Not behind the application switch: a duplicate created while the
application is off would still be there when it is switched back on.

A failure of the check itself is logged and the save is refused (AI_Error_Integrity_Check): a record saved without its unique key would allow duplicates.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Fails closed: if the key or name check cannot run, the save is refused instead of letting an unchecked record through.
*/

public inherited sharing class AIAgentAssignmentTriggerHandler {
  public class AIAgentAssignmentTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleBeforeInsert(List<AIAgentAssignment__c> newRecords) {
    stampKey(newRecords, 'handleBeforeInsert');
  }

  public static void handleBeforeUpdate(List<AIAgentAssignment__c> newRecords) {
    stampKey(newRecords, 'handleBeforeUpdate');
  }

  private static void stampKey(
    List<AIAgentAssignment__c> newRecords,
    String methodName
  ) {
    try {
      if (isTestCustomExceptionThrown) {
        throw new AIAgentAssignmentTriggerHandlerException(
          'Test exception for AIAgentAssignmentTriggerHandler.' + methodName
        );
      }

      if (newRecords == null)
        return;

      for (AIAgentAssignment__c assignment : newRecords)
        assignment.AssignmentKey__c = assignment.AIAgent__c == null
          ? null
          : (assignment.AIAgent__c +
              '|' +
              (assignment.AssigneeType__c ==
                AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET
                ? 'PS:' + assignment.PermissionSetName__c
                : 'U:' + assignment.User__c))
              .left(120);
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIAgentAssignmentTriggerHandler',
        methodName
      );
      AIAssistGlobalUtility.refuseSave(newRecords); // Fails closed: an unchecked record must not be saved.
    }
  }
}
