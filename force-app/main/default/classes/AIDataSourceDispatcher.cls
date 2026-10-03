/*
Class Name: AIDataSourceDispatcher

=================================================================
=================================================================

Description: Runs a data source when the model calls it as a tool, and returns the masked result.

The definition is configuration the end user cannot read (the AI Assist User permission set has
no access to AIDataSource__c), so it is loaded in system mode - but only if it is active AND
assigned to the agent running the turn. A name the model made up, an inactive source or one
belonging to another agent is refused with one message that says which of these it was not.
Then the work is done as the user:
- SOQL sources run in user mode (AISoqlTemplateRunner).
- Apex sources run only if the class named by the subscriber implements IAIDataSourceExecutor,
  checked before any of its code runs, and only if the plan allows Apex data sources.
- The result is flattened and masked (AIDataSourceResultProcessor).

A bound data source needs the record the chat is about; an unbound one does not.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Definition loaded in system mode and checked against the agent; data runs in user mode; plan gate for Apex sources; row cap; single-use helpers inlined.
3.0          Chandler Stuart          Apex class lookup uses Type.forName with an empty namespace so a subscriber's own class is found from managed code.
*/

public inherited sharing class AIDataSourceDispatcher {
  public class AIDataSourceExecutorException extends Exception {
  }

  // recordId may be null for an unbound data source. The caller logs a failure: this class throws and does not.
  public static List<Object> runDataSource(
    Id dataSourceId,
    Id agentId,
    Id recordId,
    Map<String, Object> inputParameters,
    Id conversationId
  ) {
    if (dataSourceId == null || agentId == null)
      throw new AIDataSourceExecutorException(
        'A data source and an agent are required.'
      );

    List<AIDataSource__c> dataSources = [
      SELECT
        Id,
        DeveloperName__c,
        SourceType__c,
        BindingType__c,
        SOQLTemplate__c,
        ApexClassName__c,
        MaxRows__c
      FROM AIDataSource__c
      WHERE
        Id = :dataSourceId
        AND IsActive__c = TRUE
        AND Id IN (
          SELECT AIDataSource__c
          FROM AIAgentDataSource__c
          WHERE AIAgent__c = :agentId AND IsActive__c = TRUE
        )
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (dataSources.isEmpty())
      throw new AIDataSourceExecutorException(
        'The data source was not found, is not active, or is not assigned to this agent.'
      );

    AIDataSource__c dataSource = dataSources[0];
    Map<String, Object> parameters = inputParameters == null
      ? new Map<String, Object>()
      : inputParameters;
    List<SObject> rawResults;

    if (
      dataSource.BindingType__c ==
      AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND &&
      recordId == null
    ) {
      throw new AIDataSourceExecutorException(
        'Data source "' +
          dataSource.DeveloperName__c +
          '" needs the record the conversation is about.'
      );
    }

    if (
      dataSource.SourceType__c ==
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL
    ) {
      if (String.isBlank(dataSource.SOQLTemplate__c))
        throw new AIDataSourceExecutorException(
          'Data source "' +
            dataSource.DeveloperName__c +
            '" has no SOQL template.'
        );

      Map<String, Object> bindValues = new Map<String, Object>(parameters);
      if (recordId != null)
        bindValues.put('recordId', recordId);

      rawResults = AISoqlTemplateRunner.runTemplate(
        dataSource.SOQLTemplate__c,
        bindValues,
        dataSource.MaxRows__c == null ? null : dataSource.MaxRows__c.intValue()
      );
    } else if (
      dataSource.SourceType__c ==
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX
    ) {
      if (!AIPlanLimitService.isApexAllowed())
        throw new AIDataSourceExecutorException(
          'Apex data sources are not included in the plan.'
        );
      if (String.isBlank(dataSource.ApexClassName__c))
        throw new AIDataSourceExecutorException(
          'Data source "' + dataSource.DeveloperName__c + '" has no Apex class.'
        );

      // Checked before anything in the class runs, not after: the name was typed by a subscriber, format rules only stop junk, and even constructing a class runs its code. The empty namespace makes the lookup find the subscriber's own unprefixed classes; the one-argument form looks only in the package's namespace once this is managed code.
      Type apexType = Type.forName('', dataSource.ApexClassName__c.trim());

      if (
        apexType == null ||
        !IAIDataSourceExecutor.class.isAssignableFrom(apexType)
      )
        throw new AIDataSourceExecutorException(
          'Apex class "' +
            dataSource.ApexClassName__c +
            '" was not found or does not implement IAIDataSourceExecutor.'
        );

      Object executor = apexType.newInstance();

      rawResults = ((IAIDataSourceExecutor) executor)
        .execute(recordId, parameters);
    } else {
      throw new AIDataSourceExecutorException(
        'Data source "' +
          dataSource.DeveloperName__c +
          '" has an unsupported source type.'
      );
    }

    return AIDataSourceResultProcessor.processResults(
      rawResults,
      conversationId
    );
  }
}
