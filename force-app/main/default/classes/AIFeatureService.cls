/*
Class Name: AIFeatureService

=================================================================
=================================================================

Description: The one answer to "may this feature be used here, now, by this user". Two layers are
checked in order, and the first that says no decides:
[1] Org: the application is switched on in this org (AIAssistSettingsService.isEnabled, which includes
    the sandbox guard).
[2] User: the user holds the feature's custom permission, or their usage policy or user settings row
    switches it on (AIUsagePolicyResolver, through AIMessagingSelector.getUserSettings).

Feature                Org   User
RunActions             on    AIAssistRunActions or Workflow Actions Enabled
DebugMode              on    AIAssistDebugMode or Debug Mode Enabled
ConversationExport     on    Conversation Export Enabled

An unknown feature is not enabled. getBlockingLayer says which layer refused, for a caller that tells the
user why.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          The plan layer and the plan-only features removed: this is no longer a licensed product.
*/

public inherited sharing class AIFeatureService {
  public static final String LAYER_ORG = 'Org';
  public static final String LAYER_USER = 'User';

  // Features a user uses, so the application must be on.
  private static final Set<String> NEEDS_APPLICATION_ON = new Set<String>{
    AIAssistApplicationConstants.APP_FEATURE_RUN_ACTIONS,
    AIAssistApplicationConstants.APP_FEATURE_DEBUG_MODE,
    AIAssistApplicationConstants.APP_FEATURE_EXPORT
  };
  // Features granted per user: the custom permission (null when there is none) and the field on the user's resolved settings.
  private static final Map<String, String> PERMISSION_BY_FEATURE = new Map<String, String>{
    AIAssistApplicationConstants.APP_FEATURE_RUN_ACTIONS => AIAssistApplicationConstants.PERMISSION_RUN_ACTIONS,
    AIAssistApplicationConstants.APP_FEATURE_DEBUG_MODE => AIAssistApplicationConstants.PERMISSION_DEBUG_MODE,
    AIAssistApplicationConstants.APP_FEATURE_EXPORT => null
  };
  private static final Map<String, Schema.SObjectField> SETTING_BY_FEATURE = new Map<String, Schema.SObjectField>{
    AIAssistApplicationConstants.APP_FEATURE_RUN_ACTIONS => AIUserSettings__c.WorkflowActionsEnabled__c,
    AIAssistApplicationConstants.APP_FEATURE_DEBUG_MODE => AIUserSettings__c.DebugModeEnabled__c,
    AIAssistApplicationConstants.APP_FEATURE_EXPORT => AIUserSettings__c.ConversationExportEnabled__c
  };

  // A test cannot grant itself a custom permission without a permission set: permission name => held.
  @TestVisible
  private static Map<String, Boolean> permissionForTest = new Map<String, Boolean>();

  // For the signed-in user. Their settings are read only when the feature is granted per user and the permission does not already grant it.
  public static Boolean isFeatureEnabled(String feature) {
    return getBlockingLayer(feature, null) == null;
  }

  // As above, for a caller that already has the user's resolved settings.
  public static Boolean isFeatureEnabled(
    String feature,
    AIUserSettings__c userSettings
  ) {
    return getBlockingLayer(feature, userSettings) == null;
  }

  // Null when the feature is enabled; otherwise the first layer that refuses it: Org or User.
  public static String getBlockingLayer(
    String feature,
    AIUserSettings__c userSettings
  ) {
    if (!SETTING_BY_FEATURE.containsKey(feature))
      return LAYER_USER; // Not a feature this package has.

    // [1]
    if (
      NEEDS_APPLICATION_ON.contains(feature) &&
      !AIAssistSettingsService.isEnabled()
    )
      return LAYER_ORG;

    // [2]
    String permission = PERMISSION_BY_FEATURE.get(feature);
    if (
      permission != null &&
      (permissionForTest.containsKey(permission)
        ? permissionForTest.get(permission)
        : FeatureManagement.checkPermission(permission))
    )
      return null;

    AIUserSettings__c settings = userSettings == null
      ? AIMessagingSelector.getUserSettings(UserInfo.getUserId())
      : userSettings;
    // Running an action also needs the settings to be active, as before; debug and export never did.
    Boolean isSwitchedOn =
      settings != null &&
      settings.get(SETTING_BY_FEATURE.get(feature)) == true &&
      (feature != AIAssistApplicationConstants.APP_FEATURE_RUN_ACTIONS ||
      settings.IsActive__c == true);

    return isSwitchedOn ? null : LAYER_USER;
  }
}
