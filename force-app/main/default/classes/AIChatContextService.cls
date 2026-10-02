/*
Class Name: AIChatContextService

=================================================================
=================================================================

Description: The record the chat window is about and the agents offered for it.

The record context strip shows the object and record names (the name is read as the user, so a record
they cannot read shows no name) and whether a synced PII registry protects the object. The agents are
the active ones for the object, in system mode through AIMessagingSelector, and an Assigned Users Only
agent appears only for a user assigned to it, so the window never offers an agent the validator would
refuse.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from the old context service. Agents respect access mode and assignments.
*/

public with sharing class AIChatContextService {
  // A blank or unreadable record is simply no context (for example the utility bar on a Home page).
  public static AIChatDataStructure.RecordContext buildRecordContext(
    String recordId,
    String objectApiName
  ) {
    AIChatDataStructure.RecordContext recordContext = new AIChatDataStructure.RecordContext();
    Id typedRecordId = AIChatDataStructure.toIdOrNull(recordId);

    if (typedRecordId == null)
      return recordContext;

    String describedObject = AISchemaHelper.getObjectApiName(typedRecordId);
    AISchemaHelper.ObjectInfo objectInfo = AISchemaHelper.getObjectInfo(
      describedObject
    );

    recordContext.recordId = typedRecordId;
    recordContext.objectApiName = String.isNotBlank(objectApiName)
      ? objectApiName
      : describedObject;
    recordContext.objectLabel = objectInfo.label;
    recordContext.objectLabelPlural = objectInfo.pluralLabel;

    // The object's name field varies (Name, CaseNumber, Subject); the helper knows it. Read as the user, so a record they cannot read shows no name.
    try {
      if (
        objectInfo.nameField != null &&
        AISchemaHelper.isAccessible(describedObject)
      ) {
        List<SObject> nameRows = Database.query(
          'SELECT ' +
            String.escapeSingleQuotes(objectInfo.nameField) +
            ' FROM ' +
            String.escapeSingleQuotes(describedObject) +
            ' WHERE Id = :typedRecordId WITH USER_MODE LIMIT 1'
        );
        recordContext.recordName = nameRows.isEmpty()
          ? null
          : String.valueOf(nameRows[0].get(objectInfo.nameField));
      }
    } catch (Exception noAccess) {
      recordContext.recordName = null; // The bar shows the object label alone.
    }

    // Only whether the object is protected is read; the registry is administration the user has no access to.
    recordContext.piiProtected =
      [
        SELECT COUNT()
        FROM AIPIIRegistry__c
        WHERE
          ObjectAPIName__c = :recordContext.objectApiName
          AND Active__c = TRUE
          AND SyncStatus__c = :AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED
        WITH SYSTEM_MODE
      ] > 0;

    return recordContext;
  }

  public static List<AIChatDataStructure.AgentOption> getAvailableAgents(
    String objectApiName
  ) {
    List<AIChatDataStructure.AgentOption> options = new List<AIChatDataStructure.AgentOption>();

    for (
      AIAgent__c agent : AIMessagingSelector.getAgentsAvailableForChat(
        objectApiName,
        UserInfo.getUserId()
      )
    ) {
      AIChatDataStructure.AgentOption option = new AIChatDataStructure.AgentOption();
      option.id = agent.Id;
      option.name = agent.Name;
      option.description = agent.Description__c;
      option.greeting = agent.GreetingMessage__c;
      option.objectApiName = agent.ObjectType__c;
      option.loadTrigger = agent.ConversationLoadTrigger__c;
      option.allowResume = agent.AllowConversationResume__c == true;

      options.add(option);
    }

    return options;
  }

  // agentKey is an agent Id (15 or 18 characters) or a Developer Name. An unknown key falls back to the first agent.
  public static AIChatDataStructure.AgentOption selectAgent(
    List<AIChatDataStructure.AgentOption> agents,
    String agentKey
  ) {
    if (agents.isEmpty())
      return null;
    if (String.isBlank(agentKey))
      return agents[0];

    for (AIChatDataStructure.AgentOption agent : agents) {
      if (
        String.valueOf(agent.id) == agentKey ||
        String.valueOf(agent.id).left(15) == agentKey.left(15)
      )
        return agent;
    }

    List<AIAgent__c> byDeveloperName = [
      SELECT Id
      FROM AIAgent__c
      WHERE DeveloperName__c = :agentKey AND IsActive__c = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    for (AIChatDataStructure.AgentOption agent : agents) {
      if (!byDeveloperName.isEmpty() && agent.id == byDeveloperName[0].Id)
        return agent;
    }

    return agents[0];
  }
}
