/*
Class Name: AIUserSettingsTriggerHandler

=================================================================
=================================================================

Description: Fills in AIUserSettings__c.UserKey__c from the user the settings belong to, before insert and before update. The field is unique, so the database then refuses one user having two settings records, where which one applied would be chance. A lookup cannot be made unique, which is why the key exists (docs/SECURITY_MODEL.md, section 6).

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

public inherited sharing class AIUserSettingsTriggerHandler {
  public class AIUserSettingsTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleBeforeInsert(List<AIUserSettings__c> newRecords) {
    stampKey(newRecords, 'handleBeforeInsert');
  }

  public static void handleBeforeUpdate(List<AIUserSettings__c> newRecords) {
    stampKey(newRecords, 'handleBeforeUpdate');
  }

  private static void stampKey(
    List<AIUserSettings__c> newRecords,
    String methodName
  ) {
    try {
      if (isTestCustomExceptionThrown) {
        throw new AIUserSettingsTriggerHandlerException(
          'Test exception for AIUserSettingsTriggerHandler.' + methodName
        );
      }

      if (newRecords == null)
        return;

      for (AIUserSettings__c settings : newRecords)
        settings.UserKey__c = settings.User__c == null
          ? null
          : String.valueOf(settings.User__c);
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIUserSettingsTriggerHandler',
        methodName
      );
      AIAssistGlobalUtility.refuseSave(newRecords); // Fails closed: an unchecked record must not be saved.
    }
  }
}
