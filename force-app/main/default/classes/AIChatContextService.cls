/*
Class Name: AIChatContextService

=================================================================
=================================================================

Description: The record the chat window is about and the agents offered for it.

The record context strip shows the object and record names (the name is read as the user, so a record
they cannot read shows no name) and whether a synced PII registry protects the object. The agents are
the active ones for the object, in system mode, and an Assigned Users Only
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
          AND IsActive__c = TRUE
          AND SyncStatus__c = :AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED
        WITH SYSTEM_MODE
      ] > 0;

    return recordContext;
  }

  public static List<AIChatDataStructure.AgentOption> getAvailableAgents(
    String objectApiName
  ) {
    List<AIChatDataStructure.AgentOption> options = new List<AIChatDataStructure.AgentOption>();

    // An agent built for this object says so; a general one has no object.
    Set<Id> agentIdsForObject = getAgentIdsForObject(objectApiName);

    for (
      AIAgent__c agent : getAgentsAvailableForChat(
        objectApiName,
        UserInfo.getUserId()
      )
    ) {
      AIChatDataStructure.AgentOption option = new AIChatDataStructure.AgentOption();
      option.id = agent.Id;
      option.name = agent.Name;
      option.description = agent.Description__c;
      option.greeting = agent.GreetingMessage__c;
      option.objectApiName = agentIdsForObject.contains(agent.Id)
        ? objectApiName
        : null;
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

  // These queries must see every user's records, not just the running user's, so they run in a class declared without sharing.
  private static SystemReader systemReader = new SystemReader();

  @TestVisible
  private static Set<Id> getAgentIdsForObject(String objectApiName) {
    return systemReader.getAgentIdsForObject(objectApiName);
  }

  @TestVisible
  private static List<AIAgent__c> getAgentsAvailableForChat(
    String objectApiName,
    Id userId
  ) {
    return systemReader.getAgentsAvailableForChat(objectApiName, userId);
  }

  private without sharing class SystemReader {
    // Which of the agents are open to this user through an active assignment, by name or by a permission set they hold. One pass for many agents.
    public Set<Id> getAgentIdsAssignedToUser(Id userId, Set<Id> agentIds) {
      Set<Id> assignedIds = new Set<Id>();

      if (userId == null || agentIds == null || agentIds.isEmpty())
        return assignedIds;

      Set<String> heldPermissionSets = getHeldPermissionSetNames(userId);

      for (AIAgentAssignment__c assignment : [
        SELECT AIAgent__c
        FROM AIAgentAssignment__c
        WHERE
          AIAgent__c IN :agentIds
          AND IsActive__c = TRUE
          AND ((AssigneeType__c = :AIAssistApplicationConstants.ASSIGNEE_TYPE_USER
          AND User__c = :userId)
          OR (AssigneeType__c = :AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET
          AND PermissionSetName__c IN :heldPermissionSets))
        WITH SYSTEM_MODE
      ]) {
        assignedIds.add(assignment.AIAgent__c);
      }

      return assignedIds;
    }

    // The active agents that have an active AI Agent Object record for the object.
    public Set<Id> getAgentIdsForObject(String objectApiName) {
      Set<Id> agentIds = new Set<Id>();

      if (String.isBlank(objectApiName))
        return agentIds;

      for (AIAgentObject__c agentObject : [
        SELECT AIAgent__c
        FROM AIAgentObject__c
        WHERE
          ObjectApiName__c = :objectApiName
          AND IsActive__c = TRUE
          AND AIAgent__r.IsActive__c = TRUE
        WITH SYSTEM_MODE
        LIMIT 5000
      ])
        agentIds.add(agentObject.AIAgent__c);

      return agentIds;
    }

    // The active agents this user can chat with for an object, agents for the object first. An agent is for the object through an AI Agent Object record; one with no such record at all is general and comes last. An Assigned Users Only agent is included only when the user is assigned.
    public List<AIAgent__c> getAgentsAvailableForChat(
      String objectApiName,
      Id userId
    ) {
      Map<Id, Set<String>> extraObjectsByAgent = getExtraObjectsByAgent();
      Set<Id> agentsAddedToObject = new Set<Id>();
      for (Id extraAgentId : extraObjectsByAgent.keySet()) {
        if (
          objectApiName != null &&
          extraObjectsByAgent.get(extraAgentId)
            .contains(objectApiName.toLowerCase())
        )
          agentsAddedToObject.add(extraAgentId);
      }

      List<AIAgent__c> candidates = [
        SELECT
          Id,
          Name,
          DeveloperName__c,
          Description__c,
          GreetingMessage__c,
          ConversationLoadTrigger__c,
          AllowConversationResume__c,
          AccessMode__c
        FROM AIAgent__c
        WHERE
          IsActive__c = TRUE
          AND (Id IN :agentsAddedToObject
          OR Id NOT IN :extraObjectsByAgent.keySet())
        WITH SYSTEM_MODE
        ORDER BY Name
        LIMIT :AIAssistApplicationConstants.CHAT_MAX_AGENTS
      ];

      Set<Id> restrictedIds = new Set<Id>();
      for (AIAgent__c candidate : candidates) {
        if (
          candidate.AccessMode__c ==
          AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY
        )
          restrictedIds.add(candidate.Id);
      }

      Set<Id> assignedIds = getAgentIdsAssignedToUser(userId, restrictedIds);
      List<AIAgent__c> agentsForObject = new List<AIAgent__c>();
      List<AIAgent__c> generalAgents = new List<AIAgent__c>();

      for (AIAgent__c candidate : candidates) {
        if (
          restrictedIds.contains(candidate.Id) &&
          !assignedIds.contains(candidate.Id)
        )
          continue;

        // The query left out agents added to other objects only: what remains is for this object or general.
        if (agentsAddedToObject.contains(candidate.Id))
          agentsForObject.add(candidate);
        else
          generalAgents.add(candidate);
      }

      agentsForObject.addAll(generalAgents);
      return agentsForObject;
    }

    // The objects each active agent is for (its active AI Agent Object records), by agent. Agents with none are general and are not in the map.
    public Map<Id, Set<String>> getExtraObjectsByAgent() {
      Map<Id, Set<String>> objectsByAgent = new Map<Id, Set<String>>();

      for (AIAgentObject__c agentObject : [
        SELECT AIAgent__c, ObjectApiName__c
        FROM AIAgentObject__c
        WHERE IsActive__c = TRUE AND AIAgent__r.IsActive__c = TRUE
        WITH SYSTEM_MODE
        LIMIT 5000
      ]) {
        if (!objectsByAgent.containsKey(agentObject.AIAgent__c))
          objectsByAgent.put(agentObject.AIAgent__c, new Set<String>());
        objectsByAgent.get(agentObject.AIAgent__c)
          .add(agentObject.ObjectApiName__c.toLowerCase());
      }

      return objectsByAgent;
    }

    // The API names of every permission set the user holds: assigned directly, and the name of each permission set group assigned to them together with the permission sets inside that group. A permission set reached only through a group has no assignment row of its own, so matching on assignment rows alone would miss it.
    public Set<String> getHeldPermissionSetNames(Id userId) {
      Set<String> heldNames = new Set<String>();
      Set<Id> heldGroupIds = new Set<Id>();

      for (PermissionSetAssignment heldAssignment : [
        SELECT
          PermissionSet.Name,
          PermissionSetGroupId,
          PermissionSetGroup.DeveloperName
        FROM PermissionSetAssignment
        WHERE AssigneeId = :userId
        WITH SYSTEM_MODE
        LIMIT 2000
      ]) {
        heldNames.add(heldAssignment.PermissionSet.Name);
        if (heldAssignment.PermissionSetGroupId != null) {
          heldGroupIds.add(heldAssignment.PermissionSetGroupId);
          heldNames.add(heldAssignment.PermissionSetGroup.DeveloperName);
        }
      }

      if (!heldGroupIds.isEmpty()) {
        for (PermissionSetGroupComponent member : [
          SELECT PermissionSet.Name
          FROM PermissionSetGroupComponent
          WHERE PermissionSetGroupId IN :heldGroupIds
          WITH SYSTEM_MODE
          LIMIT 2000
        ])
          heldNames.add(member.PermissionSet.Name);
      }

      return heldNames;
    }
  }
}
