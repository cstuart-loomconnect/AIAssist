/*
Class Name: AIViolationTriggerHandler

=================================================================
=================================================================

Description: Business logic for AIViolation__c.

Before update: when Review Status leaves New (someone marks the violation Reviewed or Dismissed) it
stamps who and when, so the audit trail does not depend on the person remembering.
After insert: adds the new violations to their rule's Trigger Count and sets its Last Triggered Date.
The rules are read FOR UPDATE and the count added to what is stored, so violations inserted by
different transactions at once add to each other instead of overwriting.

Does nothing while the application is switched off. Bulk-safe: one query and one update however
many violations arrive. Writes only to the package's own objects; a failure is logged and the
violation still saves.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from the old handler. Adds the review stamp the security model asks for, locks the rules, and drops the run-once flag.
3.0          Chandler Stuart          Restructured to the standard pattern: the trigger only routes by context to handleBeforeInsert, handleAfterUpdate and so on, each handler has its own exception type and a test seam, and a failure is logged and never stops the save.
*/

public inherited sharing class AIViolationTriggerHandler {
  public class AIViolationTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleBeforeUpdate(
    Map<Id, AIViolation__c> oldViolations,
    List<AIViolation__c> newViolations
  ) {
    try {
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIViolationTriggerHandlerException(
          'Test exception for AIViolationTriggerHandler.handleBeforeUpdate'
        );
      }

      if (oldViolations == null || newViolations == null)
        return;

      for (AIViolation__c violation : newViolations) {
        AIViolation__c previous = oldViolations.get(violation.Id);

        if (
          previous != null &&
          previous.ReviewStatus__c ==
          AIAssistApplicationConstants.REVIEW_STATUS_NEW &&
          violation.ReviewStatus__c !=
          AIAssistApplicationConstants.REVIEW_STATUS_NEW
        ) {
          violation.ReviewedBy__c = UserInfo.getUserId();
          violation.ReviewedDate__c = System.now();
        }
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIViolationTriggerHandler',
        'handleBeforeUpdate'
      );
    }
  }

  public static void handleAfterInsert(List<AIViolation__c> newViolations) {
    try {
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIViolationTriggerHandlerException(
          'Test exception for AIViolationTriggerHandler.handleAfterInsert'
        );
      }

      if (newViolations == null || newViolations.isEmpty())
        return;

      Map<Id, Integer> countByRuleId = new Map<Id, Integer>();

      for (AIViolation__c violation : newViolations) {
        if (violation.AIViolationRule__c != null)
          countByRuleId.put(
            violation.AIViolationRule__c,
            (countByRuleId.containsKey(violation.AIViolationRule__c)
              ? countByRuleId.get(violation.AIViolationRule__c)
              : 0) + 1
          );
      }

      if (countByRuleId.isEmpty())
        return;

      List<AIViolationRule__c> rules = [
        SELECT Id, TriggerCount__c
        FROM AIViolationRule__c
        WHERE Id IN :countByRuleId.keySet()
        WITH SYSTEM_MODE
        FOR UPDATE
      ];

      for (AIViolationRule__c rule : rules) {
        rule.TriggerCount__c =
          (rule.TriggerCount__c == null ? 0 : rule.TriggerCount__c) +
          countByRuleId.get(rule.Id);
        rule.LastTriggeredDate__c = System.now();
      }

      AIMessagingDataService.updateAndLogFailures(
        rules,
        'AIViolationTriggerHandler',
        'handleAfterInsert'
      );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIViolationTriggerHandler',
        'handleAfterInsert'
      );
    }
  }
}
