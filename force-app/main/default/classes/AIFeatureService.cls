/*
Class Name: AIFeatureService

=================================================================
=================================================================

Description: The one answer to "may this feature be used here, now, by this user". Three layers are
checked in order, and the first that says no decides:
[1] Plan: the Feature Management parameter the licence sets for the customer (AIPlanLimitService).
[2] Org: the application is switched on in this org (AIAssistSettingsService.isEnabled, which includes
    the sandbox guard). Only for features a user uses; configuring a feature does not need the
    application to be on.
[3] User: the user holds the feature's custom permission, or their usage policy or user settings row
    switches it on (AIUsagePolicyResolver, through AIMessagingSelector.getUserSettings). Only for
    features that are granted per user.

Feature                Plan parameter              Org   User
WorkflowActions        WorkflowActionsAllowed      -     -      (configuring an action)
RunActions             WorkflowActionsAllowed      on    AIAssistRunActions or Workflow Actions Enabled
Apex                   ApexDataSourcesAllowed      -     -
AIEvaluatedRules       AIEvaluatedRulesAllowed     -     -
MultipleProviders      MultipleProvidersAllowed    -     -
DebugMode              -                           on    AIAssistDebugMode or Debug Mode Enabled
ConversationExport     -                           on    Conversation Export Enabled
BetaFeatures           BetaFeaturesEnabled         on    -
ContinuationChat       ContinuationChatEnabled     on    -

An unknown feature is not enabled. getBlockingLayer says which layer refused, for a caller that tells the
user why.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public inherited sharing class AIFeatureService {
  public static final String LAYER_PLAN = 'Plan';
  public static final String LAYER_ORG = 'Org';
  public static final String LAYER_USER = 'User';

  private static final Map<String, String> PLAN_PARAMETER_BY_FEATURE = new Map<String, String>{
    AIAssistApplicationConstants.APP_FEATURE_WORKFLOW_ACTIONS => AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
    AIAssistApplicationConstants.APP_FEATURE_RUN_ACTIONS => AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
    AIAssistApplicationConstants.APP_FEATURE_APEX => AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
    AIAssistApplicationConstants.APP_FEATURE_AI_RULES => AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
    AIAssistApplicationConstants.APP_FEATURE_MULTIPLE_PROVIDERS => AIAssistApplicationConstants.FEATURE_MULTIPLE_PROVIDERS_ALLOWED,
    AIAssistApplicationConstants.APP_FEATURE_DEBUG_MODE => null,
    AIAssistApplicationConstants.APP_FEATURE_EXPORT => null,
    AIAssistApplicationConstants.APP_FEATURE_BETA => AIAssistApplicationConstants.FEATURE_BETA_FEATURES_ENABLED,
    AIAssistApplicationConstants.APP_FEATURE_CONTINUATION_CHAT => AIAssistApplicationConstants.FEATURE_CONTINUATION_CHAT_ENABLED
  };
  // Features a user uses, so the application must be on.
  private static final Set<String> NEEDS_APPLICATION_ON = new Set<String>{
    AIAssistApplicationConstants.APP_FEATURE_RUN_ACTIONS,
    AIAssistApplicationConstants.APP_FEATURE_DEBUG_MODE,
    AIAssistApplicationConstants.APP_FEATURE_EXPORT,
    AIAssistApplicationConstants.APP_FEATURE_BETA,
    AIAssistApplicationConstants.APP_FEATURE_CONTINUATION_CHAT
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

  // Null when the feature is enabled; otherwise the first layer that refuses it: Plan, Org or User.
  public static String getBlockingLayer(
    String feature,
    AIUserSettings__c userSettings
  ) {
    if (!PLAN_PARAMETER_BY_FEATURE.containsKey(feature))
      return LAYER_PLAN; // Not a feature this package has.

    // [1]
    String planParameter = PLAN_PARAMETER_BY_FEATURE.get(feature);
    if (planParameter != null && !AIPlanLimitService.isAllowed(planParameter))
      return LAYER_PLAN;

    // [2]
    if (
      NEEDS_APPLICATION_ON.contains(feature) &&
      !AIAssistSettingsService.isEnabled()
    )
      return LAYER_ORG;

    // [3]
    if (!SETTING_BY_FEATURE.containsKey(feature))
      return null;

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
