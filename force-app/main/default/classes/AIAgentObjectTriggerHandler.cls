/*
Class Name: AIAgentObjectTriggerHandler

=================================================================
=================================================================

Description: Business logic for AIAgentObject__c, before insert and before update.

[1] Checks that the object API name exists in this org, and stores it as the org spells it (so "case" is saved as "Case"). A name that does not exist is refused with a label that says what to enter, because a typo here would otherwise only show up when someone opened chat and found the agent missing.
[2] Fills in AssignmentKey__c from the agent and the object, so the same object cannot be added to one agent twice (the field is unique).

Safe in the subscriber's transactions: the trigger is on the package's own object, does no DML of its own and cannot recurse. The object check uses AISchemaHelper, which caches describes. Not behind the application switch: a bad object name saved while the application is off would still be there when it is switched back on.

An unexpected failure of the check is logged and the save is refused (AI_Error_Integrity_Check), so an object name that was not checked is never saved. A refused object name stops the save the same way.

=================================================================
=================================================================
Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Fails closed: if the key or name check cannot run, the save is refused instead of letting an unchecked record through.
*/

public inherited sharing class AIAgentObjectTriggerHandler {
  public class AIAgentObjectTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleBeforeInsert(List<AIAgentObject__c> newRecords) {
    prepare(newRecords, 'handleBeforeInsert');
  }

  public static void handleBeforeUpdate(List<AIAgentObject__c> newRecords) {
    prepare(newRecords, 'handleBeforeUpdate');
  }

  private static void prepare(
    List<AIAgentObject__c> newRecords,
    String methodName
  ) {
    try {
      if (isTestCustomExceptionThrown) {
        throw new AIAgentObjectTriggerHandlerException(
          'Test exception for AIAgentObjectTriggerHandler.' + methodName
        );
      }

      if (newRecords == null)
        return;

      for (AIAgentObject__c agentObject : newRecords) {
        if (String.isNotBlank(agentObject.ObjectApiName__c)) {
          AISchemaHelper.ObjectInfo objectInfo = AISchemaHelper.getObjectInfo(
            agentObject.ObjectApiName__c.trim()
          );

          if (objectInfo == null) {
            agentObject.ObjectApiName__c.addError(
              String.format(
                Label.AI_Error_Object_Not_Found,
                new List<String>{ agentObject.ObjectApiName__c }
              )
            );
            continue;
          }

          agentObject.ObjectApiName__c = objectInfo.apiName;
        }

        agentObject.AssignmentKey__c = agentObject.AIAgent__c == null ||
          agentObject.ObjectApiName__c == null
          ? null
          : (agentObject.AIAgent__c +
              '|' +
              agentObject.ObjectApiName__c.toLowerCase())
              .left(120);
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIAgentObjectTriggerHandler',
        methodName
      );
      AIAssistGlobalUtility.refuseSave(newRecords); // Fails closed: an unchecked record must not be saved.
    }
  }
}
