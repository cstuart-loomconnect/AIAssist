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
