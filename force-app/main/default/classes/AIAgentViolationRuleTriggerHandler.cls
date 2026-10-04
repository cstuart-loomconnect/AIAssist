/*
Class Name: AIAgentViolationRuleTriggerHandler

=================================================================
=================================================================

Description: Fills in AIAgentViolationRule__c.AssignmentKey__c from the agent and the violation rule, before insert and before update. The field is unique, so the database then refuses one agent being given the same rule twice. A lookup cannot be made unique, which is why the key exists (docs/SECURITY_MODEL.md, section 6).

The key is always worked out again, so it cannot be typed in or left stale by an edit.

Safe in the subscriber's transactions: the trigger is on the package's own object, makes no query and no DML, and cannot recurse. Not behind the application switch: a duplicate created while the application is off would still be there when it is switched back on.

A failure of the check itself is logged and the save is refused (AI_Error_Integrity_Check): a record saved without its unique key would allow duplicates.

=================================================================
=================================================================
Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          After save, warns (in the Platform Log) when an agent now has more AI evaluated rules than are used; see AIViolationRuleCapService.
3.0          Chandler Stuart          Fails closed: if the key or name check cannot run, the save is refused instead of letting an unchecked record through.
*/

public inherited sharing class AIAgentViolationRuleTriggerHandler {
  public class AIAgentViolationRuleTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleBeforeInsert(
    List<AIAgentViolationRule__c> newRecords
  ) {
    stampKey(newRecords, 'handleBeforeInsert');
  }

  public static void handleBeforeUpdate(
    List<AIAgentViolationRule__c> newRecords
  ) {
    stampKey(newRecords, 'handleBeforeUpdate');
  }

  private static void stampKey(
    List<AIAgentViolationRule__c> newRecords,
    String methodName
  ) {
    try {
      if (isTestCustomExceptionThrown) {
        throw new AIAgentViolationRuleTriggerHandlerException(
          'Test exception for AIAgentViolationRuleTriggerHandler.' + methodName
        );
      }

      if (newRecords == null)
        return;

      for (AIAgentViolationRule__c link : newRecords)
        link.AssignmentKey__c = link.AIAgent__c == null ||
          link.AIViolationRule__c == null
          ? null
          : link.AIAgent__c + '|' + link.AIViolationRule__c;
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIAgentViolationRuleTriggerHandler',
        methodName
      );
      AIAssistGlobalUtility.refuseSave(newRecords); // Fails closed: an unchecked record must not be saved.
    }
  }

  // After insert and update: assigning a rule to an agent can push it over the limit.
  public static void handleAfterSave(List<AIAgentViolationRule__c> savedLinks) {
    try {
      if (
        !AIAssistSettingsService.isEnabled() ||
        savedLinks == null ||
        savedLinks.isEmpty()
      )
        return;

      AIViolationRuleCapService.warnWhenOverLimit();
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIAgentViolationRuleTriggerHandler',
        'handleAfterSave'
      );
    }
  }
}
