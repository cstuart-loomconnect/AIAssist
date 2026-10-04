/*
Class Name: AIViolationRuleTriggerHandler

=================================================================
=================================================================

Description: Business logic for AIViolationRule__c, before insert and update.

On insert the Public Id and Developer Name are stamped, once, so a rule can be matched across orgs when configuration is exported and imported.

An active AI evaluated rule needs a plan that includes them (AIEvaluatedRulesAllowed); on a plan that
does not, the rule is refused with the plan label. A Signal Tag used by one rule only is enforced by the
field itself (it is unique), so no code is needed for it: the old
handler's duplicate check was dropped because the object model now does it.

Does nothing while the application is switched off. No queries.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from the old handler. The duplicate tag check, Public Id and Developer Name stamps are gone because the object model covers them; the plan check is new.
3.0          Chandler Stuart          Restructured to the standard pattern: the trigger only routes by context to handleBeforeInsert, handleAfterUpdate and so on, each handler has its own exception type and a test seam, and a failure is logged and never stops the save.
4.0          Chandler Stuart          Public Id and Developer Name stamped on insert, now that a rule is defined once and shared by many agents.
5.0          Chandler Stuart          After save, warns (in the Platform Log) when an agent now has more AI evaluated rules than are used; see AIViolationRuleCapService.
*/

public inherited sharing class AIViolationRuleTriggerHandler {
  public class AIViolationRuleTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  // Both contexts apply the same plan check: an active AI evaluated rule needs a plan that includes them.
  public static void handleBeforeInsert(List<AIViolationRule__c> newRules) {
    try {
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIViolationRuleTriggerHandlerException(
          'Test exception for AIViolationRuleTriggerHandler.handleBeforeInsert'
        );
      }

      if (newRules != null && !newRules.isEmpty()) {
        AIAssistGlobalUtility.generatePublicId(newRules);
        AIAssistGlobalUtility.generateDeveloperName(newRules);
      }

      if (
        newRules == null ||
        newRules.isEmpty() ||
        AIPlanLimitService.isAiRulesAllowed()
      )
        return;

      for (AIViolationRule__c rule : newRules) {
        if (
          rule.IsActive__c == true &&
          rule.DetectionMethod__c ==
          AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED
        )
          rule.addError(Label.AI_Error_Plan_AI_Rules_Not_Included);
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIViolationRuleTriggerHandler',
        'handleBeforeInsert'
      );
    }
  }

  public static void handleBeforeUpdate(List<AIViolationRule__c> newRules) {
    try {
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIViolationRuleTriggerHandlerException(
          'Test exception for AIViolationRuleTriggerHandler.handleBeforeUpdate'
        );
      }

      if (
        newRules == null ||
        newRules.isEmpty() ||
        AIPlanLimitService.isAiRulesAllowed()
      )
        return;

      for (AIViolationRule__c rule : newRules) {
        if (
          rule.IsActive__c == true &&
          rule.DetectionMethod__c ==
          AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED
        )
          rule.addError(Label.AI_Error_Plan_AI_Rules_Not_Included);
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIViolationRuleTriggerHandler',
        'handleBeforeUpdate'
      );
    }
  }

  // After insert and update: a new or changed active AI evaluated rule can push an agent over the limit.
  public static void handleAfterSave(List<AIViolationRule__c> savedRules) {
    try {
      if (!AIAssistSettingsService.isEnabled() || savedRules == null)
        return;

      for (AIViolationRule__c rule : savedRules) {
        if (
          rule.IsActive__c == true &&
          rule.DetectionMethod__c ==
          AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED
        ) {
          AIViolationRuleCapService.warnWhenOverLimit();
          return;
        }
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIViolationRuleTriggerHandler',
        'handleAfterSave'
      );
    }
  }
}
