/*
Class Name: AIConfigurationAccess

=================================================================
=================================================================

Description: Who may call the set-up controllers. Every one of them asks here first:
- the AIAssistManageConfiguration custom permission, always;
- the Customize Application system permission as well, for anything that creates or changes a credential,
  because that is the permission Setup itself asks for.
A caller without them gets the Not Authorised refusal and nothing is read or changed. The package's
permission sets carry no system permission, so Customize Application comes from the administrator's own
profile or permission set.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public with sharing class AIConfigurationAccess {
  // A test cannot rely on what the user running it happens to hold.
  @TestVisible
  private static Boolean canManageForTest;
  @TestVisible
  private static Boolean canCustomizeForTest;

  public static void assertCanManage(Boolean needsCustomizeApplication) {
    Boolean canManage = canManageForTest != null
      ? canManageForTest
      : FeatureManagement.checkPermission(
          AIAssistApplicationConstants.PERMISSION_MANAGE_CONFIGURATION
        );
    Boolean canCustomize =
      !needsCustomizeApplication ||
      (canCustomizeForTest != null
        ? canCustomizeForTest
        : [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE
              AssigneeId = :UserInfo.getUserId()
              AND PermissionSet.PermissionsCustomizeApplication = TRUE
            WITH SYSTEM_MODE
          ] > 0);

    if (!canManage || !canCustomize)
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_NOT_AUTHORISED,
        Label.AI_Error_Not_Authorised
      );
  }

  // What an Aura caller is shown: a refusal's own text, and for anything unexpected the generic label, with the real error in the Platform Log.
  public static AuraHandledException toAura(
    Exception caughtException,
    String className,
    String methodName
  ) {
    String errorText = Label.AI_Error_Generic;

    if (caughtException instanceof AIMessagingException)
      errorText = caughtException.getMessage();
    else
      AIPlatformLogManager.logException(caughtException, className, methodName);

    AuraHandledException auraException = new AuraHandledException(errorText);
    auraException.setMessage(errorText);

    return auraException;
  }
}
