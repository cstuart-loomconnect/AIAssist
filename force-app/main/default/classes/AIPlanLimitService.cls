/*
Class Name: AIPlanLimitService

=================================================================
=================================================================

Description: Reads the plan limits the package owner sets per customer in the License
Management Org, through Feature Management parameters.

A parameter that cannot be read (a developer or scratch org, or an install with no license data)
means no limit, so the package works unrestricted outside a managed install. Limits are read
once per transaction because they are asked for on every message.

Tests cannot change Feature Management parameters, so they use setLimitForTest.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, as AIPlanLimits.
2.0          Chandler Stuart          Renamed AIPlanLimitService. Method names shortened. Boolean parameters added for plan-gated features.
3.0          Chandler Stuart          The five activation parameters added: active agents, data sources and workflow actions, the retention cap and multiple providers.
*/

public inherited sharing class AIPlanLimitService {
  private static Map<String, Object> valueByName = new Map<String, Object>();

  // The plan's monthly message allowance, or null for unlimited.
  public static Integer getMessageLimit() {
    return (Integer) read(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_MESSAGES,
      false
    );
  }

  // The plan's monthly token allowance, or null for unlimited.
  public static Integer getUsageLimit() {
    return (Integer) read(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_USAGE,
      false
    );
  }

  // A Boolean plan parameter by name. One that cannot be read counts as allowed, except the spare ones, which stay off until the licence switches them on.
  public static Boolean isAllowed(String parameterName) {
    Object featureValue = read(parameterName, true);
    Boolean isOffUntilSet =
      parameterName ==
      AIAssistApplicationConstants.FEATURE_BETA_FEATURES_ENABLED ||
      parameterName ==
      AIAssistApplicationConstants.FEATURE_CONTINUATION_CHAT_ENABLED;

    return featureValue == null ? !isOffUntilSet : (Boolean) featureValue;
  }

  // Whether the plan includes Apex data sources. Allowed when the parameter cannot be read.
  public static Boolean isApexAllowed() {
    Object featureValue = read(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      true
    );
    return featureValue == null ? true : (Boolean) featureValue;
  }

  // Whether the plan includes Workflow Actions. Allowed when the parameter cannot be read.
  public static Boolean isWorkflowActionsAllowed() {
    Object featureValue = read(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );
    return featureValue == null ? true : (Boolean) featureValue;
  }

  // Whether the plan includes violation rules evaluated by the AI. Allowed when the parameter cannot be read.
  public static Boolean isAiRulesAllowed() {
    Object featureValue = read(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
    return featureValue == null ? true : (Boolean) featureValue;
  }

  // The most agents the plan lets be active at once, or null for unlimited.
  public static Integer getActiveAgentLimit() {
    return (Integer) read(
      AIAssistApplicationConstants.FEATURE_MAX_ACTIVE_AGENTS,
      false
    );
  }

  // The most data sources the plan lets be active at once, or null for unlimited.
  public static Integer getActiveDataSourceLimit() {
    return (Integer) read(
      AIAssistApplicationConstants.FEATURE_MAX_ACTIVE_DATA_SOURCES,
      false
    );
  }

  // The most workflow actions the plan lets be active at once, or null for unlimited.
  public static Integer getActiveActionLimit() {
    return (Integer) read(
      AIAssistApplicationConstants.FEATURE_MAX_ACTIVE_WORKFLOW_ACTIONS,
      false
    );
  }

  // The longest an agent may keep its conversations, in days, or null for no cap.
  public static Integer getRetentionDayCap() {
    return (Integer) read(
      AIAssistApplicationConstants.FEATURE_MAX_CONVERSATION_RETENTION_DAYS,
      false
    );
  }

  // Whether the plan lets model configurations of more than one provider be active. Allowed when the parameter cannot be read.
  public static Boolean isMultipleProvidersAllowed() {
    Object featureValue = read(
      AIAssistApplicationConstants.FEATURE_MULTIPLE_PROVIDERS_ALLOWED,
      true
    );
    return featureValue == null ? true : (Boolean) featureValue;
  }

  // A scratch or developer org answers with the package's default limits (three agents, no Apex), which would refuse the configuration almost every test builds. The activation checks therefore apply in a test only when it asks for them.
  @TestVisible
  private static Boolean isActivationCheckedInTest = false;

  public static Boolean isActivationChecked() {
    return !Test.isRunningTest() || isActivationCheckedInTest;
  }

  @TestVisible
  private static void setLimitForTest(String parameterName, Object value) {
    valueByName.put(parameterName, value);
  }

  @TestVisible
  private static void resetForTest() {
    valueByName.clear();
  }

  private static Object read(String parameterName, Boolean isBoolean) {
    if (valueByName.containsKey(parameterName))
      return valueByName.get(parameterName);

    Object packageValue = null;

    try {
      packageValue = isBoolean
        ? (Object) System.FeatureManagement.checkPackageBooleanValue(
            parameterName
          )
        : (Object) System.FeatureManagement.checkPackageIntegerValue(
            parameterName
          );
    } catch (Exception caughtException) {
      packageValue = null; // Parameter not defined for this org: unlimited.
    }

    valueByName.put(parameterName, packageValue);

    return packageValue;
  }
}
