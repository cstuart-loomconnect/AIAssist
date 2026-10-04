/*
Class Name: AIWorkflowActionTriggerHandler

=================================================================
=================================================================

Description: Stamps the Developer Name on a new workflow action, derived from its required Action Name. The model names an action it suggests by this name.

Safe in the subscriber's transactions: the trigger is on the package's own AIWorkflowAction__c object, does no
DML of its own and cannot recurse. It does nothing while AIAssistSettings__c.IsEnabled__c is off.
A failure is logged and the record still saves.

An active action the plan does not include is refused with the plan label; see AIPlanActivationService.

A Flow action whose Flow runs in "System context without sharing" is refused (AIFlowRunModeService): the
user triggers the action from a browser, and that mode would let them do what their own access forbids.
Unlike the rest of this handler that check fails closed: if the run mode cannot be read the save is
refused, not allowed.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
3.0          Chandler Stuart          Restructured to the standard pattern: the trigger only routes by context to handleBeforeInsert, handleAfterUpdate and so on, each handler has its own exception type and a test seam, and a failure is logged and never stops the save.
4.0          Chandler Stuart          Plan check added, before insert and before update. It is not behind the application switch and it does stop the save.
5.0          Chandler Stuart          Flow run mode check added, before insert and before update. Not behind the application switch, and it fails closed.
6.0          Chandler Stuart          The Apex class named must exist and implement IAIWorkflowActionExecutor (AIConfigurationValidator).
*/

public inherited sharing class AIWorkflowActionTriggerHandler {
  public class AIWorkflowActionTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  @TestVisible
  private static Boolean isTestFlowCheckExceptionThrown = false;

  public static void handleBeforeInsert(List<AIWorkflowAction__c> newRecords) {
    AIPlanActivationService.checkWorkflowActions(newRecords, null);
    AIConfigurationValidator.checkApexClasses(
      newRecords,
      null,
      AIWorkflowAction__c.ApexClassName__c,
      AIWorkflowAction__c.ActionType__c,
      IAIWorkflowActionExecutor.class
    );
    checkFlowRunModes(newRecords, null);

    try {
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIWorkflowActionTriggerHandlerException(
          'Test exception for AIWorkflowActionTriggerHandler.handleBeforeInsert'
        );
      }

      if (newRecords == null || newRecords.isEmpty())
        return;

      AIAssistGlobalUtility.generateDeveloperName(newRecords);
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIWorkflowActionTriggerHandler',
        'handleBeforeInsert'
      );
    }
  }

  // Only the plan check: identifiers are stamped once, on insert.
  public static void handleBeforeUpdate(
    Map<Id, AIWorkflowAction__c> oldRecordsById,
    List<AIWorkflowAction__c> newRecords
  ) {
    AIPlanActivationService.checkWorkflowActions(newRecords, oldRecordsById);
    AIConfigurationValidator.checkApexClasses(
      newRecords,
      oldRecordsById,
      AIWorkflowAction__c.ApexClassName__c,
      AIWorkflowAction__c.ActionType__c,
      IAIWorkflowActionExecutor.class
    );
    checkFlowRunModes(newRecords, oldRecordsById);
  }

  // A Flow action is checked when it is new, when its Flow or type changes, and when it is switched on. oldRecordsById is null on insert.
  @TestVisible
  private static void checkFlowRunModes(
    List<AIWorkflowAction__c> newRecords,
    Map<Id, AIWorkflowAction__c> oldRecordsById
  ) {
    List<AIWorkflowAction__c> toCheck = new List<AIWorkflowAction__c>();

    if (newRecords == null)
      return;

    for (AIWorkflowAction__c action : newRecords) {
      if (
        action.ActionType__c !=
        AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW ||
        String.isBlank(action.FlowAPIName__c)
      )
        continue;

      AIWorkflowAction__c previous = oldRecordsById == null
        ? null
        : oldRecordsById.get(action.Id);
      if (
        previous == null ||
        previous.ActionType__c != action.ActionType__c ||
        previous.FlowAPIName__c != action.FlowAPIName__c ||
        (action.IsActive__c == true &&
        previous.IsActive__c != true)
      )
        toCheck.add(action);
    }

    if (toCheck.isEmpty())
      return;

    try {
      if (isTestFlowCheckExceptionThrown) {
        throw new AIWorkflowActionTriggerHandlerException(
          'Test exception for AIWorkflowActionTriggerHandler.checkFlowRunModes'
        );
      }

      Set<String> flowNames = new Set<String>();
      for (AIWorkflowAction__c action : toCheck)
        flowNames.add(action.FlowAPIName__c);

      Map<String, Boolean> allowedByName = AIFlowRunModeService.getAllowedByFlowName(
        flowNames
      );
      for (AIWorkflowAction__c action : toCheck) {
        if (allowedByName.get(action.FlowAPIName__c) != true)
          action.FlowAPIName__c.addError(Label.AI_Error_Flow_Run_Mode);
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIWorkflowActionTriggerHandler',
        'checkFlowRunModes'
      );
      for (AIWorkflowAction__c action : toCheck)
        action.addError(Label.AI_Error_Flow_Run_Mode);
    }
  }
}
