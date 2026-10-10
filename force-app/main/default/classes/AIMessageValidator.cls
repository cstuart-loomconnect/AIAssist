/*
Class Name: AIMessageValidator

=================================================================
=================================================================

Description: Decides whether a request to chat is allowed at all, before anything is written.
Every refusal is an exception whose message is a Custom Label (so it translates) and
whose code is a stable AIAssistApplicationConstants.ERROR_* value, checked in this order, cheapest
first:
[1] The application is switched on (AIAssistSettings__c.IsEnabled__c) and not in maintenance.
[2] The message has text and is no longer than MAX_USER_MESSAGE_CHARACTERS.
[3] The agent exists, is active, and the user may use it: an agent set to Assigned Users Only
    needs an active AIAgentAssignment__c for the user or a permission set they hold.
[4] The user has accepted the current usage terms (AITermsAcknowledgment__c).
[5] The channel exists in the object model and is one the user may chat from.
[6] If the chat is about a record, the user can read that record, it is the object the caller
    named, and it is the kind of record the agent works on.

Limits are not checked here; AIUsageLimitService does that once it is known whether the message
starts a new conversation. Nothing here writes.

A missing, mistyped or deleted agent is reported as "not available", never as a hint about what
exists. The checks that need data the user cannot read are made here, in system mode.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, as the first half of AIMessageGuard.
2.0          Chandler Stuart          The agent/object check also honours objects added through AIAgentObject__c.
3.0          Chandler Stuart          The agent access check is a public method, isUserAllowedOnAgent, shared with AIWorkflowActionDispatcher.
4.0          Chandler Stuart          A message is refused while chat is paused to protect the org's limits.
*/

public inherited sharing class AIMessageValidator {
  public static final String TERMS_ACCEPTED = 'ACCEPTED';
  public static final String TERMS_OUTDATED = 'OUTDATED';
  public static final String TERMS_NONE = 'NONE';

  public class AIMessageValidatorException extends Exception {
  }

  // What the checks learned about the request, handed on so nothing is queried twice.
  public class ChatContext {
    public Id userId;
    public AIAgent__c agent;
    public AIUserSettings__c userSettings;
  }

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
    // [1]
    if (!AIAssistSettingsService.isEnabled())
      throw new AIMessageValidatorException(
        Label.AI_Error_Application_Inactive
      );
    if (AIAssistSettingsService.getUiSettings().IsMaintenanceMode__c == true)
      throw new AIMessageValidatorException(Label.AI_Error_Maintenance_Mode);

    // [2]
    if (String.isBlank(messageBody))
      throw new AIMessageValidatorException(Label.AI_Error_Message_Empty);
    // The administrator's maximum when it is set and lower than the fixed one.
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

    ChatContext chatContext = new ChatContext();
    chatContext.userId = UserInfo.getUserId();

    // [3]
    if (agentId == null || agentId.getSobjectType() != AIAgent__c.SObjectType)
      throw new AIMessageValidatorException(Label.AI_Error_Agent_Not_Available);

    chatContext.agent = getAgent(agentId);

    if (chatContext.agent == null)
      throw new AIMessageValidatorException(Label.AI_Error_Agent_Not_Available);
    if (chatContext.agent.IsActive__c != true)
      throw new AIMessageValidatorException(Label.AI_Error_Agent_Inactive);

    // The default access mode is Assigned Users Only: an agent nobody is assigned to is closed to everyone.
    if (!isUserAllowedOnAgent(chatContext.agent, chatContext.userId)) {
      throw new AIMessageValidatorException(Label.AI_Error_Agent_Not_Assigned);
    }

    // [4]
    String termsStatus = getTermsAcceptanceStatus(
      chatContext.userId,
      AIAssistSettingsService.getSettings().CurrentTermsVersion__c
    );

    if (termsStatus == TERMS_OUTDATED)
      throw new AIMessageValidatorException(
        Label.AI_Error_Terms_Version_Changed
      );
    if (termsStatus == TERMS_NONE)
      throw new AIMessageValidatorException(
        Label.AI_Error_Terms_Not_Acknowledged
      );

    // [5] No channel supplied, no settings row and no allow-list all mean unrestricted. A channel the object model does not define is refused here rather than failing later on the restricted picklist.
    chatContext.userSettings = AIUsagePolicyResolver.getUserSettings(
      chatContext.userId
    );

    if (String.isNotBlank(channel)) {
      Set<String> definedChannels = new Set<String>();
      for (
        Schema.PicklistEntry channelEntry : AIConversation__c.Channel__c.getDescribe()
          .getPicklistValues()
      )
        definedChannels.add(channelEntry.getValue());

      if (!definedChannels.contains(channel))
        throw new AIMessageValidatorException(
          Label.AI_Error_Channel_Not_Allowed
        );

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

    // [6] A chat about a record must be about a record the user can read; otherwise the conversation, and the data sources it runs for the model, could be pointed at someone else's data. UserRecordAccess answers with the user's real sharing, hierarchy and permissions.
    if (relatedRecordId != null) {
      Schema.DescribeSObjectResult relatedRecordType = relatedRecordId.getSobjectType()
        .getDescribe();

      // The object name the caller gave must be the object the Id belongs to, so the pair stored on the conversation can be trusted.
      if (
        String.isNotBlank(relatedObjectApiName) &&
        !relatedObjectApiName.equalsIgnoreCase(relatedRecordType.getName()) &&
        !relatedObjectApiName.equalsIgnoreCase(relatedRecordType.getLocalName())
      ) {
        throw new AIMessageValidatorException(
          Label.AI_Error_Record_Access_Denied
        );
      }

      // An agent built for one kind of record is not offered for another. It is built for the objects added to it (AI Agent Object); one with none is general.
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

    return chatContext;
  }

  // These queries must see every user's records, not just the running user's, so they run in a class declared without sharing.
  private static SystemReader systemReader = new SystemReader();

  @TestVisible
  private static Boolean agentSupportsObject(
    Id agentId,
    String objectApiName,
    String objectLocalName
  ) {
    return systemReader.agentSupportsObject(
      agentId,
      objectApiName,
      objectLocalName
    );
  }

  @TestVisible
  private static AIAgent__c getAgent(Id agentId) {
    return systemReader.getAgent(agentId);
  }

  public static String getTermsAcceptanceStatus(
    Id userId,
    String currentTermsVersion
  ) {
    return systemReader.getTermsAcceptanceStatus(userId, currentTermsVersion);
  }

  @TestVisible
  private static Boolean isUserAssignedToAgent(Id agentId, Id userId) {
    return systemReader.isUserAssignedToAgent(agentId, userId);
  }

  private without sharing class SystemReader {
    // True when the agent is offered on the object: an active AI Agent Object record names it, or the agent has none and is general, offered on every object.
    public Boolean agentSupportsObject(
      Id agentId,
      String objectApiName,
      String objectLocalName
    ) {
      Set<String> agentObjects = new Set<String>();

      if (agentId != null) {
        for (AIAgentObject__c agentObject : [
          SELECT ObjectApiName__c
          FROM AIAgentObject__c
          WHERE AIAgent__c = :agentId AND IsActive__c = TRUE
          WITH SYSTEM_MODE
          LIMIT 200
        ])
          agentObjects.add(agentObject.ObjectApiName__c.toLowerCase());
      }

      return agentObjects.isEmpty() ||
        agentObjects.contains(String.valueOf(objectApiName).toLowerCase()) ||
        agentObjects.contains(String.valueOf(objectLocalName).toLowerCase());
    }

    public AIAgent__c getAgent(Id agentId) {
      if (agentId == null)
        return null;

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

      return agents.isEmpty() ? null : agents[0];
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

    // ACCEPTED when the user signed the current version, OUTDATED when they signed an earlier one, NONE when they never signed.
    public String getTermsAcceptanceStatus(
      Id userId,
      String currentTermsVersion
    ) {
      if (String.isBlank(currentTermsVersion))
        return TERMS_ACCEPTED; // No terms configured, so nothing to accept.

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

    // True when an active assignment names the user, or names a permission set (or permission set group) the user holds.
    public Boolean isUserAssignedToAgent(Id agentId, Id userId) {
      if (agentId == null || userId == null)
        return false;

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

      Set<String> heldPermissionSets = getHeldPermissionSetNames(userId);
      heldPermissionSets.retainAll(permissionSetNames);

      return !heldPermissionSets.isEmpty();
    }
  }
}
