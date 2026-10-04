/*
Class Name: AIUsagePolicyAssignmentTriggerHandler

=================================================================
=================================================================

Description: Fills in AIUsagePolicyAssignment__c.AssignmentKey__c from the usage policy and the assignee (a user, or a permission set by name), before insert and before update. The field is unique, so the database then refuses the same policy being assigned to the same user or permission set twice.

The key is always worked out again, so it cannot be typed in or left stale by an edit.

Safe in the subscriber's transactions: the trigger is on the package's own object, makes no query and no DML, and cannot recurse. Not behind the application switch.

A failure of the check itself is logged and the save is refused (AI_Error_Integrity_Check): a record saved without its unique key would allow duplicates.

=================================================================
=================================================================
Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Fails closed: if the key or name check cannot run, the save is refused instead of letting an unchecked record through.
*/

public inherited sharing class AIUsagePolicyAssignmentTriggerHandler {
  public class AIUsagePolicyAssignmentTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleBeforeInsert(
    List<AIUsagePolicyAssignment__c> newRecords
  ) {
    stampKey(newRecords, 'handleBeforeInsert');
  }

  public static void handleBeforeUpdate(
    List<AIUsagePolicyAssignment__c> newRecords
  ) {
    stampKey(newRecords, 'handleBeforeUpdate');
  }

  private static void stampKey(
    List<AIUsagePolicyAssignment__c> newRecords,
    String methodName
  ) {
    try {
      if (isTestCustomExceptionThrown) {
        throw new AIUsagePolicyAssignmentTriggerHandlerException(
          'Test exception for AIUsagePolicyAssignmentTriggerHandler.' +
          methodName
        );
      }

      if (newRecords == null)
        return;

      for (AIUsagePolicyAssignment__c assignment : newRecords)
        assignment.AssignmentKey__c = assignment.AIUsagePolicy__c == null
          ? null
          : (assignment.AIUsagePolicy__c +
              '|' +
              (assignment.AssigneeType__c ==
                AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET
                ? 'PS:' + assignment.PermissionSetName__c
                : 'U:' + assignment.User__c))
              .left(120);
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIUsagePolicyAssignmentTriggerHandler',
        methodName
      );
      AIAssistGlobalUtility.refuseSave(newRecords); // Fails closed: an unchecked record must not be saved.
    }
  }
}
