/*
Class Name: AIChatContextService

=================================================================
=================================================================

Description: The record the chat window is about and the agents offered for it.

Step 1: Build the record context: object, record name and whether a synced PII registry protects the object
Step 2: Find the active agents offered for the object, agents for the object first
Step 3: Leave out an Assigned Users Only agent unless the user is assigned to it
Step 4: Pick the agent the window opens with, from an Id or Developer Name, falling back to the first

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIChatContextService {
  // A blank or unreadable record is simply no context (for example the utility bar on a Home page).
  public static AIChatDataStructure.RecordContext buildRecordContext(
    String recordId,
    String objectApiName
  ) {
    // [1] Start with an empty context
    AIChatDataStructure.RecordContext recordContext = new AIChatDataStructure.RecordContext();
    Id typedRecordId = AIChatDataStructure.getIdOrNull(recordId);

    // [2] Return the empty context when there is no record
    if (typedRecordId == null)
      return recordContext;

    // [3] Describe the record's object and copy its details onto the context
    AISchemaHelper.ObjectInfo objectInfo = AISchemaHelper.getObjectInfo(
      typedRecordId
    );
    String describedObject = objectInfo.apiName;

    recordContext.recordId = typedRecordId;
    recordContext.objectApiName = String.isNotBlank(objectApiName)
      ? objectApiName
      : describedObject;
    recordContext.objectLabel = objectInfo.label;
    recordContext.objectLabelPlural = objectInfo.pluralLabel;

    try {
      // [4] Read the record name as the user, because the name field varies (Name, CaseNumber, Subject) and a record they cannot read shows no name
      if (objectInfo.nameField != null && objectInfo.isAccessible) {
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
    } catch (Exception ex) {
      // [5] Show the object label alone when the user cannot read the record
      recordContext.recordName = null;
    }

    // [6] Note whether the object is protected, reading only that fact because the registry is administration the user has no access to
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

    // [7] Return the context
    return recordContext;
  }

  // The agents the window offers the user for the object: agents for the object first, then general agents. An agent is for the object when its Object API Names list includes it; one with a blank list is general. An Assigned Users Only agent is included only when the user is assigned.
  public static List<AIChatDataStructure.AgentOption> getAvailableAgents(
    String objectApiName
  ) {
    // [1] Read the active agents for this object or with no object, because agents for other objects only are left out
    String objectPattern = String.isBlank(objectApiName)
      ? ''
      : '%' + objectApiName + '%';
    List<AIAgent__c> candidates = [
      SELECT
        Id,
        Name,
        DeveloperName__c,
        Description__c,
        GreetingMessage__c,
        ConversationLoadTrigger__c,
        AllowConversationResume__c,
        AccessMode__c,
        ObjectApiNames__c
      FROM AIAgent__c
      WHERE
        IsActive__c = TRUE
        AND (ObjectApiNames__c = NULL
        OR ObjectApiNames__c LIKE :objectPattern)
      WITH SYSTEM_MODE
      ORDER BY Name
      LIMIT :AIAssistApplicationConstants.CHAT_MAX_AGENTS
    ];

    // [2] Note the agents that are for assigned users only
    Set<Id> restrictedIds = new Set<Id>();

    for (AIAgent__c candidate : candidates) {
      if (
        candidate.AccessMode__c ==
        AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY
      )
        restrictedIds.add(candidate.Id);
    }

    // [3] Find which of those the user is assigned to
    Set<Id> assignedIds = getAgentIdsAssignedToUser(
      UserInfo.getUserId(),
      restrictedIds
    );
    Set<Id> agentIdsForObject = new Set<Id>();
    List<AIAgent__c> agentsForObject = new List<AIAgent__c>();
    List<AIAgent__c> generalAgents = new List<AIAgent__c>();

    // [4] Skip assigned only agents the user is not assigned to, and sort the rest into agents for the object and general agents
    for (AIAgent__c candidate : candidates) {
      if (
        restrictedIds.contains(candidate.Id) &&
        !assignedIds.contains(candidate.Id)
      )
        continue;

      Set<String> candidateObjects = AISchemaHelper.getObjectApiNameSet(
        candidate.ObjectApiNames__c
      );

      if (candidateObjects.isEmpty())
        generalAgents.add(candidate);
      else if (
        String.isNotBlank(objectApiName) &&
        candidateObjects.contains(objectApiName.toLowerCase())
      ) {
        agentIdsForObject.add(candidate.Id);
        agentsForObject.add(candidate);
      }
    }

    agentsForObject.addAll(generalAgents);

    // [5] Turn each agent the user can chat with into an option
    List<AIChatDataStructure.AgentOption> options = new List<AIChatDataStructure.AgentOption>();

    for (AIAgent__c agent : agentsForObject) {
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

    // [6] Return the options
    return options;
  }

  // agentKey is an agent Id (15 or 18 characters) or a Developer Name. An unknown key falls back to the first agent.
  public static AIChatDataStructure.AgentOption selectAgent(
    List<AIChatDataStructure.AgentOption> agents,
    String agentKey
  ) {
    // [1] Nothing to pick without agents, and the first agent when no key is given
    if (agents.isEmpty())
      return null;
    if (String.isBlank(agentKey))
      return agents[0];

    // [2] Pick the agent whose Id matches the key
    for (AIChatDataStructure.AgentOption agent : agents) {
      if (
        String.valueOf(agent.id) == agentKey ||
        String.valueOf(agent.id).left(15) == agentKey.left(15)
      )
        return agent;
    }

    // [3] Otherwise look for an active agent whose Developer Name matches the key
    List<AIAgent__c> byDeveloperName = [
      SELECT Id
      FROM AIAgent__c
      WHERE DeveloperName__c = :agentKey AND IsActive__c = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    // [4] Pick the offered agent with that Developer Name
    for (AIChatDataStructure.AgentOption agent : agents) {
      if (!byDeveloperName.isEmpty() && agent.id == byDeveloperName[0].Id)
        return agent;
    }

    // [5] Fall back to the first agent when the key matches none
    return agents[0];
  }

  // Which of the agents are open to this user through an active assignment, by name or by a permission set they hold. One pass for many agents.
  private static Set<Id> getAgentIdsAssignedToUser(
    Id userId,
    Set<Id> agentIds
  ) {
    // [1] Start with no assigned agents
    Set<Id> assignedIds = new Set<Id>();

    // [2] Nothing to check without a user or agents
    if (userId == null || agentIds == null || agentIds.isEmpty())
      return assignedIds;

    // [3] Find the permission sets the user holds
    Set<String> heldPermissionSets = getHeldPermissionSetNames(userId);

    // [4] Collect the agents with an active assignment to the user, by name or by a permission set they hold
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

    // [5] Return the assigned agents
    return assignedIds;
  }

  // The API names of every permission set the user holds: assigned directly, and the name of each permission set group assigned to them together with the permission sets inside that group. A permission set reached only through a group has no assignment row of its own, so matching on assignment rows alone would miss it.
  private static Set<String> getHeldPermissionSetNames(Id userId) {
    // [1] Start with no names and no groups
    Set<String> heldNames = new Set<String>();
    Set<Id> heldGroupIds = new Set<Id>();

    // [2] Add every permission set assigned directly, and note any group assigned
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

    // [3] Add the permission sets inside each assigned group
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

    // [4] Return the names
    return heldNames;
  }
}
