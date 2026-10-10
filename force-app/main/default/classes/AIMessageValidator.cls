/*
Class Name: AIMessageValidator

=================================================================
=================================================================

Description: Decides whether a request to chat is allowed at all, before anything is written. Every refusal is an exception with a Custom Label message.

Step 1: Check the application is switched on and not in maintenance
Step 2: Check the message has text and is not longer than the limit
Step 3: Check the agent exists, is active and the user may use it
Step 4: Check the user has accepted the current usage terms
Step 5: Check the channel exists and is one the user may chat from
Step 6: If the chat is about a record, check the user can read it and the agent works on that kind of record
Step 7: Return the context the checks learned, so nothing is queried twice

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIMessageValidator {
  public class AIMessageValidatorException extends Exception {
  }

  // What the checks learned about the request, handed on so nothing is queried twice.
  public class ChatContext {
    public Id userId;
    public AIAgent__c agent;
    public AIUserSettings__c userSettings;
  }

  public static final String TERMS_ACCEPTED = 'ACCEPTED';
  public static final String TERMS_OUTDATED = 'OUTDATED';
  public static final String TERMS_NONE = 'NONE';

  // The agent's access check, shared with the Workflow Action dispatcher so an action cannot be run by a user the agent no longer admits. True for an agent open to all users, otherwise when an active assignment names the user or a permission set (or group) they hold.
  public static Boolean isUserAllowedOnAgent(AIAgent__c agent, Id userId) {
    return agent != null &&
      (agent.AccessMode__c ==
      AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS ||
      isUserAssignedToAgent(agent.Id, userId));
  }

  // Returns the context for the limit checks. Throws a refusal if the request is not allowed.
  public static ChatContext validateSendRequest(
    Id agentId,
    String messageBody,
    String channel,
    String relatedObjectApiName,
    Id relatedRecordId
  ) {
    // [1] Refuse when the application is switched off
    if (!AIAssistSettingsService.isEnabled())
      throw new AIMessageValidatorException(
        Label.AI_Error_Application_Inactive
      );

    // [2] Refuse when the application is in maintenance mode
    if (AIAssistSettingsService.getUiSettings().IsMaintenanceMode__c == true)
      throw new AIMessageValidatorException(Label.AI_Error_Maintenance_Mode);

    // [3] Refuse a message with no text
    if (String.isBlank(messageBody))
      throw new AIMessageValidatorException(Label.AI_Error_Message_Empty);

    // [4] Refuse a message over the limit, which is the administrator's maximum when it is set and lower than the fixed one
    Decimal configuredLength = AIAssistSettingsService.getSettings()
      .MaxMessageLength__c;
    if (
      messageBody.length() >
      (configuredLength != null &&
        configuredLength >= 1 &&
        configuredLength <
        AIAssistApplicationConstants.MAX_USER_MESSAGE_CHARACTERS
        ? configuredLength.intValue()
        : AIAssistApplicationConstants.MAX_USER_MESSAGE_CHARACTERS)
    )
      throw new AIMessageValidatorException(Label.AI_Error_Message_Too_Long);

    // [5] Start the context with the running user
    ChatContext chatContext = new ChatContext();
    chatContext.userId = UserInfo.getUserId();

    // [6] Refuse a missing agent, or an Id that is not an agent, as "not available" so nothing is revealed about what exists
    if (agentId == null || agentId.getSobjectType() != AIAgent__c.SObjectType)
      throw new AIMessageValidatorException(Label.AI_Error_Agent_Not_Available);

    // [7] Load the agent and refuse one that was not found
    chatContext.agent = getAgent(agentId);

    if (chatContext.agent == null)
      throw new AIMessageValidatorException(Label.AI_Error_Agent_Not_Available);

    // [8] Refuse an agent that is switched off
    if (chatContext.agent.IsActive__c != true)
      throw new AIMessageValidatorException(Label.AI_Error_Agent_Inactive);

    // [9] Refuse a user the agent does not admit. The default is Assigned Users Only, so an agent nobody is assigned to is closed to everyone
    if (!isUserAllowedOnAgent(chatContext.agent, chatContext.userId)) {
      throw new AIMessageValidatorException(Label.AI_Error_Agent_Not_Assigned);
    }

    // [10] Find out whether the user has accepted the current usage terms
    String termsStatus = getTermsAcceptanceStatus(
      chatContext.userId,
      AIAssistSettingsService.getSettings().CurrentTermsVersion__c
    );

    // [11] Refuse a user who accepted an earlier version of the terms, or none at all
    if (termsStatus == TERMS_OUTDATED)
      throw new AIMessageValidatorException(
        Label.AI_Error_Terms_Version_Changed
      );
    if (termsStatus == TERMS_NONE)
      throw new AIMessageValidatorException(
        Label.AI_Error_Terms_Not_Acknowledged
      );

    // [12] Load the user's settings. No settings row means unrestricted
    chatContext.userSettings = AIUsagePolicyService.getUserSettings(
      chatContext.userId
    );

    if (String.isNotBlank(channel)) {
      // [13] Refuse a channel the object model does not define, rather than failing later on the restricted picklist
      Set<String> definedChannels = new Set<String>();
      for (
        Schema.PicklistEntry channelEntry : AIConversation__c.Channel__c.getDescribe()
          .getPicklistValues()
      ) {
        definedChannels.add(channelEntry.getValue());
      }

      if (!definedChannels.contains(channel))
        throw new AIMessageValidatorException(
          Label.AI_Error_Channel_Not_Allowed
        );

      // [14] Refuse a channel outside the user's allow-list. No allow-list means unrestricted
      if (
        chatContext.userSettings != null &&
        String.isNotBlank(chatContext.userSettings.AllowedChannels__c) &&
        !new Set<String>(
            chatContext.userSettings.AllowedChannels__c.split(
              AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR
            )
          )
          .contains(channel)
      ) {
        throw new AIMessageValidatorException(
          Label.AI_Error_Channel_Not_Allowed
        );
      }
    }

    if (relatedRecordId != null) {
      // [15] A chat about a record must name the object the Id belongs to, so the pair stored on the conversation can be trusted
      Schema.DescribeSObjectResult relatedRecordType = relatedRecordId.getSobjectType()
        .getDescribe();

      if (
        String.isNotBlank(relatedObjectApiName) &&
        !relatedObjectApiName.equalsIgnoreCase(relatedRecordType.getName()) &&
        !relatedObjectApiName.equalsIgnoreCase(relatedRecordType.getLocalName())
      ) {
        throw new AIMessageValidatorException(
          Label.AI_Error_Record_Access_Denied
        );
      }

      // [16] Refuse an agent built for another kind of record. An agent with no objects added to it is general
      if (
        !agentSupportsObject(
          chatContext.agent.Id,
          relatedRecordType.getName(),
          relatedRecordType.getLocalName()
        )
      ) {
        throw new AIMessageValidatorException(
          Label.AI_Error_Agent_Not_Available
        );
      }

      // [17] Refuse a record the user cannot read, as otherwise the conversation and its data sources could be pointed at someone else's data. UserRecordAccess answers with the user's real sharing, hierarchy and permissions
      List<UserRecordAccess> recordAccess = relatedRecordType.isAccessible()
        ? [
            SELECT RecordId, HasReadAccess
            FROM UserRecordAccess
            WHERE UserId = :chatContext.userId AND RecordId = :relatedRecordId
            WITH SYSTEM_MODE
          ]
        : new List<UserRecordAccess>();

      if (recordAccess.isEmpty() || recordAccess[0].HasReadAccess != true) {
        throw new AIMessageValidatorException(
          Label.AI_Error_Record_Access_Denied
        );
      }
    }

    // [18] Return what the checks learned
    return chatContext;
  }

  // ACCEPTED when the user signed the current version, OUTDATED when they signed an earlier one, NONE when they never signed.
  public static String getTermsAcceptanceStatus(
    Id userId,
    String currentTermsVersion
  ) {
    // [1] No terms configured, so nothing to accept
    if (String.isBlank(currentTermsVersion))
      return TERMS_ACCEPTED;

    // [2] The user signed the current version
    if (
      [
        SELECT COUNT()
        FROM AITermsAcknowledgment__c
        WHERE User__c = :userId AND TermsVersion__c = :currentTermsVersion
        WITH SYSTEM_MODE
        LIMIT 1
      ] > 0
    )
      return TERMS_ACCEPTED;

    // [3] The user signed an earlier version, or never signed
    return [
        SELECT COUNT()
        FROM AITermsAcknowledgment__c
        WHERE User__c = :userId
        WITH SYSTEM_MODE
        LIMIT 1
      ] > 0
      ? TERMS_OUTDATED
      : TERMS_NONE;
  }

  // True when the agent is offered on the object: its Object API Names list includes it, or the list is blank and the agent is general, offered on every object.
  @TestVisible
  private static Boolean agentSupportsObject(
    Id agentId,
    String objectApiName,
    String objectLocalName
  ) {
    // [1] Read the agent's object list, which must see the agent whoever is asking
    Set<String> agentObjects = new Set<String>();

    if (agentId != null) {
      for (AIAgent__c agent : [
        SELECT ObjectApiNames__c
        FROM AIAgent__c
        WHERE Id = :agentId
        WITH SYSTEM_MODE
        LIMIT 1
      ]) {
        agentObjects = AISchemaHelper.getObjectApiNameSet(
          agent.ObjectApiNames__c
        );
      }
    }

    // [2] A blank list means the agent is general, otherwise the object must be on it
    return agentObjects.isEmpty() ||
      agentObjects.contains(String.valueOf(objectApiName).toLowerCase()) ||
      agentObjects.contains(String.valueOf(objectLocalName).toLowerCase());
  }

  // Returns the agent with the fields the chat needs, or null when there is no such agent. It must see the agent whoever is asking.
  @TestVisible
  private static AIAgent__c getAgent(Id agentId) {
    // [1] Nothing to find without an Id
    if (agentId == null)
      return null;

    // [2] Read the agent
    List<AIAgent__c> agents = [
      SELECT
        Id,
        Name,
        DeveloperName__c,
        AIAgentPersona__c,
        IsActive__c,
        AccessMode__c,
        AIModelConfiguration__c,
        MaxMessagesPerConversation__c,
        MaxTokensPerConversation__c,
        MaxToolCallingIterations__c,
        SingleActiveConversationPerRecord__c,
        TokenTrackingMethod__c
      FROM AIAgent__c
      WHERE Id = :agentId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    // [3] Return the agent, or null when it was not found
    return agents.isEmpty() ? null : agents[0];
  }

  // The API names of every permission set the user holds: assigned directly, and the name of each permission set group assigned to them together with the permission sets inside that group. A permission set reached only through a group has no assignment row of its own, so matching on assignment rows alone would miss it.
  private static Set<String> getHeldPermissionSetNames(Id userId) {
    // [1] Collect the permission sets and groups assigned to the user directly
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

    // [2] Add the permission sets inside each group the user holds
    if (!heldGroupIds.isEmpty()) {
      for (PermissionSetGroupComponent member : [
        SELECT PermissionSet.Name
        FROM PermissionSetGroupComponent
        WHERE PermissionSetGroupId IN :heldGroupIds
        WITH SYSTEM_MODE
        LIMIT 2000
      ]) {
        heldNames.add(member.PermissionSet.Name);
      }
    }

    return heldNames;
  }

  // True when an active assignment names the user, or names a permission set (or permission set group) the user holds.
  @TestVisible
  private static Boolean isUserAssignedToAgent(Id agentId, Id userId) {
    // [1] Nobody to check
    if (agentId == null || userId == null)
      return false;

    // [2] The user is assigned by name
    Integer directAssignments = [
      SELECT COUNT()
      FROM AIAgentAssignment__c
      WHERE
        AIAgent__c = :agentId
        AND IsActive__c = TRUE
        AND AssigneeType__c = :AIAssistApplicationConstants.ASSIGNEE_TYPE_USER
        AND User__c = :userId
      WITH SYSTEM_MODE
    ];

    if (directAssignments > 0)
      return true;

    // [3] Collect the permission sets the agent is assigned to
    Set<String> permissionSetNames = new Set<String>();

    for (AIAgentAssignment__c assignment : [
      SELECT PermissionSetName__c
      FROM AIAgentAssignment__c
      WHERE
        AIAgent__c = :agentId
        AND IsActive__c = TRUE
        AND AssigneeType__c = :AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET
      WITH SYSTEM_MODE
      LIMIT 200
    ]) {
      if (String.isNotBlank(assignment.PermissionSetName__c))
        permissionSetNames.add(assignment.PermissionSetName__c);
    }

    if (permissionSetNames.isEmpty())
      return false;

    // [4] The user is assigned when they hold any of those permission sets
    Set<String> heldPermissionSets = getHeldPermissionSetNames(userId);
    heldPermissionSets.retainAll(permissionSetNames);

    return !heldPermissionSets.isEmpty();
  }
}
