/*
Class Name: AIFlowRunModeService

=================================================================
=================================================================

Description: Decides whether a Flow may be run as an AI Assist Workflow Action. A Flow's run mode decides
how much access it has: in the default mode it runs as the signed-in user, and in "System context without
sharing" it runs with every record visible and every change allowed, whatever the user's permissions.
An action the user triggers from a browser must not be a way round the user's own access, so a Flow in
that mode is refused.

Checked twice: when the action is saved (AIWorkflowActionTriggerHandler), so an administrator is told at
once, and again just before the Flow runs (AIWorkflowActionDispatcher), because the Flow can be edited
after the action was saved.

Fails closed. A Flow that cannot be found, or whose run mode cannot be read, is refused: an answer the
check could not get is not a reason to allow.

The run mode is read from FlowVersionView.RunInMode for the active version of the Flow, or the latest
version when none is active. A blank run mode is the default mode.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public inherited sharing class AIFlowRunModeService {
  public static final String RUN_MODE_SYSTEM_WITHOUT_SHARING = 'SystemModeWithoutSharing';

  // Test seam: Flow versions cannot be created in a test. When set, the Flow names in it are answered from here (null value = default mode) and any other name is "not found".
  @TestVisible
  private static Map<String, String> testRunModeByFlowName;

  @TestVisible
  private static void setRunModeForTest(String flowApiName, String runMode) {
    if (testRunModeByFlowName == null)
      testRunModeByFlowName = new Map<String, String>();
    testRunModeByFlowName.put(flowApiName, runMode);
  }

  // Throws a failure (logged by the dispatcher, shown to the user as Action Failed) unless the Flow may run.
  public static void assertAllowed(String flowApiName) {
    if (!getAllowedByFlowName(new Set<String>{ flowApiName }).get(flowApiName))
      throw AIMessagingException.newFailure(
        'Flow ' +
          flowApiName +
          ' runs in system context without sharing, or its run mode could not be confirmed.',
        null
      );
  }

  // For each name: true when the Flow exists and does not run in system context without sharing. Two queries however many names.
  public static Map<String, Boolean> getAllowedByFlowName(
    Set<String> flowApiNames
  ) {
    Map<String, Boolean> allowedByName = new Map<String, Boolean>();
    Map<String, String> runModeByName = getRunModes(flowApiNames);

    for (String flowApiName : flowApiNames)
      allowedByName.put(
        flowApiName,
        flowApiName != null &&
          runModeByName.containsKey(flowApiName.trim()) &&
          runModeByName.get(flowApiName.trim()) !=
          RUN_MODE_SYSTEM_WITHOUT_SHARING
      );

    return allowedByName;
  }

  // Run mode by the name as entered (trimmed). A Flow that does not exist is not in the map; a Flow in the default mode is in the map with a null run mode.
  private static Map<String, String> getRunModes(Set<String> flowApiNames) {
    Map<String, String> runModeByName = new Map<String, String>();

    Set<String> names = new Set<String>();
    for (String flowApiName : flowApiNames) {
      if (String.isNotBlank(flowApiName))
        names.add(flowApiName.trim());
    }
    if (names.isEmpty())
      return runModeByName;

    if (testRunModeByFlowName != null) {
      for (String name : names) {
        if (testRunModeByFlowName.containsKey(name))
          runModeByName.put(name, testRunModeByFlowName.get(name));
      }
      return runModeByName;
    }

    // "ns__Flow" is a Flow from a namespace; a name without one is the subscriber's own.
    Set<String> unprefixedNames = new Set<String>();
    for (String name : names)
      unprefixedNames.add(
        name.contains('__') ? name.substringAfter('__') : name
      );

    Map<String, String> versionIdByName = new Map<String, String>();
    for (FlowDefinitionView definition : [
      SELECT ApiName, NamespacePrefix, ActiveVersionId, LatestVersionId
      FROM FlowDefinitionView
      WHERE ApiName IN :unprefixedNames
      WITH SYSTEM_MODE
      LIMIT 2000
    ]) {
      String fullName = String.isBlank(definition.NamespacePrefix)
        ? definition.ApiName
        : definition.NamespacePrefix + '__' + definition.ApiName;
      String versionId = definition.ActiveVersionId != null
        ? definition.ActiveVersionId
        : definition.LatestVersionId;
      if (names.contains(fullName) && versionId != null)
        versionIdByName.put(fullName, versionId);
    }

    Map<String, String> runModeByVersionId = new Map<String, String>();
    if (!versionIdByName.isEmpty()) {
      for (FlowVersionView version : [
        SELECT DurableId, RunInMode
        FROM FlowVersionView
        WHERE DurableId IN :new Set<String>(versionIdByName.values())
        WITH SYSTEM_MODE
        LIMIT 2000
      ])
        runModeByVersionId.put(version.DurableId, version.RunInMode);
    }

    for (String name : versionIdByName.keySet()) {
      String versionId = versionIdByName.get(name);
      if (runModeByVersionId.containsKey(versionId))
        runModeByName.put(name, runModeByVersionId.get(versionId));
    }

    return runModeByName;
  }
}
