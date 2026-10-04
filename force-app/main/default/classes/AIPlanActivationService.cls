/*
Class Name: AIPlanActivationService

=================================================================
=================================================================

Description: Refuses configuration the customer's plan does not include, at the moment it is saved.
Called by the triggers on the four configuration objects, before insert and before update:
- AIAgent__c: no more active agents than MaxActiveAgents, and no retention longer than
  MaxConversationRetentionDays (blank retention means keep indefinitely, so it is over any cap).
- AIDataSource__c: no more active data sources than MaxActiveDataSources, and an active Apex data
  source only when ApexDataSourcesAllowed.
- AIWorkflowAction__c: an active action only when WorkflowActionsAllowed, an active Apex action only
  when ApexDataSourcesAllowed, and no more active actions than MaxActiveWorkflowActions.
- AIModelConfiguration__c: active model configurations of one provider only, unless
  MultipleProvidersAllowed.

Only what is being switched on is refused. A record that was already active stays as it is, so a
plan that is reduced later never blocks an unrelated edit; it only stops anything more being
activated. Each refusal is the matching AI_Error_Plan_* Custom Label on the record.

Not behind the application switch (AIAssistSettings__c.IsEnabled__c): switching the application off
must not be a way to activate more than the plan includes.

Counts are of every record in the org, whatever the running user can see, so they are explicit
system mode. One query per save, and only when something is being activated under a limit.

A failure of the check itself is logged and the save goes ahead; the same limits are checked again
when a message is sent or an action is run.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public inherited sharing class AIPlanActivationService {
  // oldAgentsById is null on insert.
  public static void checkAgents(
    List<AIAgent__c> newAgents,
    Map<Id, AIAgent__c> oldAgentsById
  ) {
    try {
      if (
        newAgents == null ||
        newAgents.isEmpty() ||
        !AIPlanLimitService.isActivationChecked()
      )
        return;

      Integer retentionCap = AIPlanLimitService.getRetentionDayCap();
      List<SObject> newlyActive = new List<SObject>();
      Integer stillActive = 0;

      for (AIAgent__c agent : newAgents) {
        AIAgent__c previous = oldAgentsById == null
          ? null
          : oldAgentsById.get(agent.Id);

        // Only when the retention is being set or changed. Blank means keep indefinitely.
        if (
          retentionCap != null &&
          (previous == null ||
          previous.ConversationRetentionDays__c !=
          agent.ConversationRetentionDays__c) &&
          (agent.ConversationRetentionDays__c == null ||
          agent.ConversationRetentionDays__c > retentionCap)
        )
          agent.addError(Label.AI_Error_Plan_Retention_Cap);

        if (agent.IsActive__c != true)
          continue;

        if (previous != null && previous.IsActive__c == true)
          stillActive++;
        else
          newlyActive.add(agent);
      }

      Integer agentLimit = AIPlanLimitService.getActiveAgentLimit();
      if (agentLimit == null || newlyActive.isEmpty())
        return;

      Set<Id> savedIds = oldAgentsById == null
        ? new Set<Id>()
        : oldAgentsById.keySet();
      Integer activeElsewhere = [
        SELECT COUNT()
        FROM AIAgent__c
        WHERE IsActive__c = TRUE AND Id NOT IN :savedIds
        WITH SYSTEM_MODE
      ];

      refuseBeyondLimit(
        newlyActive,
        agentLimit - activeElsewhere - stillActive,
        Label.AI_Error_Plan_Limit_Agents
      );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIPlanActivationService',
        'checkAgents'
      );
    }
  }

  // oldDataSourcesById is null on insert.
  public static void checkDataSources(
    List<AIDataSource__c> newDataSources,
    Map<Id, AIDataSource__c> oldDataSourcesById
  ) {
    try {
      if (
        newDataSources == null ||
        newDataSources.isEmpty() ||
        !AIPlanLimitService.isActivationChecked()
      )
        return;

      List<SObject> newlyActive = new List<SObject>();
      Integer stillActive = 0;

      for (AIDataSource__c dataSource : newDataSources) {
        if (dataSource.IsActive__c != true)
          continue;

        AIDataSource__c previous = oldDataSourcesById == null
          ? null
          : oldDataSourcesById.get(dataSource.Id);
        Boolean wasActive = previous != null && previous.IsActive__c == true;

        // An active source that is, or is being changed to, Apex.
        if (
          dataSource.SourceType__c ==
          AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX &&
          (!wasActive || previous.SourceType__c != dataSource.SourceType__c) &&
          !AIFeatureService.isFeatureEnabled(
            AIAssistApplicationConstants.APP_FEATURE_APEX
          )
        ) {
          dataSource.addError(Label.AI_Error_Plan_Apex_Not_Included);
          continue;
        }

        if (wasActive)
          stillActive++;
        else
          newlyActive.add(dataSource);
      }

      Integer dataSourceLimit = AIPlanLimitService.getActiveDataSourceLimit();
      if (dataSourceLimit == null || newlyActive.isEmpty())
        return;

      Set<Id> savedIds = oldDataSourcesById == null
        ? new Set<Id>()
        : oldDataSourcesById.keySet();
      Integer activeElsewhere = [
        SELECT COUNT()
        FROM AIDataSource__c
        WHERE IsActive__c = TRUE AND Id NOT IN :savedIds
        WITH SYSTEM_MODE
      ];

      refuseBeyondLimit(
        newlyActive,
        dataSourceLimit - activeElsewhere - stillActive,
        Label.AI_Error_Plan_Limit_Data_Sources
      );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIPlanActivationService',
        'checkDataSources'
      );
    }
  }

  // oldActionsById is null on insert.
  public static void checkWorkflowActions(
    List<AIWorkflowAction__c> newActions,
    Map<Id, AIWorkflowAction__c> oldActionsById
  ) {
    try {
      if (
        newActions == null ||
        newActions.isEmpty() ||
        !AIPlanLimitService.isActivationChecked()
      )
        return;

      List<SObject> newlyActive = new List<SObject>();
      Integer stillActive = 0;

      for (AIWorkflowAction__c action : newActions) {
        if (action.IsActive__c != true)
          continue;

        AIWorkflowAction__c previous = oldActionsById == null
          ? null
          : oldActionsById.get(action.Id);
        Boolean wasActive = previous != null && previous.IsActive__c == true;

        if (
          !wasActive &&
          !AIFeatureService.isFeatureEnabled(
            AIAssistApplicationConstants.APP_FEATURE_WORKFLOW_ACTIONS
          )
        ) {
          action.addError(Label.AI_Error_Plan_Actions_Not_Included);
          continue;
        }

        // An active action that is, or is being changed to, Apex.
        if (
          action.ActionType__c ==
          AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX &&
          (!wasActive || previous.ActionType__c != action.ActionType__c) &&
          !AIFeatureService.isFeatureEnabled(
            AIAssistApplicationConstants.APP_FEATURE_APEX
          )
        ) {
          action.addError(Label.AI_Error_Plan_Apex_Not_Included);
          continue;
        }

        if (wasActive)
          stillActive++;
        else
          newlyActive.add(action);
      }

      Integer actionLimit = AIPlanLimitService.getActiveActionLimit();
      if (actionLimit == null || newlyActive.isEmpty())
        return;

      Set<Id> savedIds = oldActionsById == null
        ? new Set<Id>()
        : oldActionsById.keySet();
      Integer activeElsewhere = [
        SELECT COUNT()
        FROM AIWorkflowAction__c
        WHERE IsActive__c = TRUE AND Id NOT IN :savedIds
        WITH SYSTEM_MODE
      ];

      refuseBeyondLimit(
        newlyActive,
        actionLimit - activeElsewhere - stillActive,
        Label.AI_Error_Plan_Limit_Actions
      );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIPlanActivationService',
        'checkWorkflowActions'
      );
    }
  }

  // oldConfigurationsById is null on insert.
  public static void checkModelConfigurations(
    List<AIModelConfiguration__c> newConfigurations,
    Map<Id, AIModelConfiguration__c> oldConfigurationsById
  ) {
    try {
      if (
        newConfigurations == null ||
        newConfigurations.isEmpty() ||
        !AIPlanLimitService.isActivationChecked() ||
        AIFeatureService.isFeatureEnabled(
          AIAssistApplicationConstants.APP_FEATURE_MULTIPLE_PROVIDERS
        )
      )
        return;

      // The providers already in use: by active configurations this save leaves as they are, and by the rest of the org.
      Set<String> providersInUse = new Set<String>();
      List<AIModelConfiguration__c> changedConfigurations = new List<AIModelConfiguration__c>();

      for (AIModelConfiguration__c configuration : newConfigurations) {
        if (configuration.IsActive__c != true)
          continue;

        AIModelConfiguration__c previous = oldConfigurationsById == null
          ? null
          : oldConfigurationsById.get(configuration.Id);

        if (
          previous != null &&
          previous.IsActive__c == true &&
          previous.AIProvider__c == configuration.AIProvider__c
        )
          providersInUse.add(configuration.AIProvider__c);
        else
          changedConfigurations.add(configuration);
      }

      if (changedConfigurations.isEmpty())
        return;

      Set<Id> savedIds = oldConfigurationsById == null
        ? new Set<Id>()
        : oldConfigurationsById.keySet();
      for (AggregateResult providerRow : [
        SELECT AIProvider__c provider
        FROM AIModelConfiguration__c
        WHERE IsActive__c = TRUE AND Id NOT IN :savedIds
        WITH SYSTEM_MODE
        GROUP BY AIProvider__c
      ])
        providersInUse.add((String) providerRow.get('provider'));

      // With none in use yet, the first one activated becomes the organisation's provider.
      for (AIModelConfiguration__c configuration : changedConfigurations) {
        if (providersInUse.isEmpty())
          providersInUse.add(configuration.AIProvider__c);
        else if (!providersInUse.contains(configuration.AIProvider__c))
          configuration.addError(Label.AI_Error_Plan_Providers_Limit);
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIPlanActivationService',
        'checkModelConfigurations'
      );
    }
  }

  // room is how many more may be activated; the records past it are refused.
  private static void refuseBeyondLimit(
    List<SObject> newlyActive,
    Integer room,
    String userMessage
  ) {
    for (
      Integer recordIndex = Math.max(room, 0);
      recordIndex < newlyActive.size();
      recordIndex++
    )
      newlyActive[recordIndex].addError(userMessage);
  }
}
