/*
Class Name: AIMessageValidator

=================================================================
=================================================================

Description: Decides whether a request to chat is allowed at all, before anything is written.
Every refusal is an AIMessagingException whose message is a Custom Label (so it translates) and
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
exists. The checks that need data the user cannot read go through AIMessagingSelector.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, as the first half of AIMessageGuard.
2.0          Chandler Stuart          The agent/object check also honours objects added through AIAgentObject__c.
*/

public inherited sharing class AIMessageValidator {
  // What the checks learned about the request, handed on so nothing is queried twice.
  public class ChatContext {
    public Id userId;
    public AIAgent__c agent;
    public AIUserSettings__c userSettings;
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
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_APPLICATION_DISABLED,
        Label.AI_Error_Application_Inactive
      );
    if (AIAssistSettingsService.getUiSettings().IsMaintenanceMode__c == true)
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_MAINTENANCE_MODE,
        Label.AI_Error_Maintenance_Mode
      );

    // [2]
    if (String.isBlank(messageBody))
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_MESSAGE_EMPTY,
        Label.AI_Error_Message_Empty
      );
    if (
      messageBody.length() >
      AIAssistApplicationConstants.MAX_USER_MESSAGE_CHARACTERS
    )
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_MESSAGE_TOO_LONG,
        Label.AI_Error_Message_Too_Long
      );

    ChatContext chatContext = new ChatContext();
    chatContext.userId = UserInfo.getUserId();

    // [3]
    if (agentId == null || agentId.getSobjectType() != AIAgent__c.SObjectType)
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_AGENT_NOT_FOUND,
        Label.AI_Error_Agent_Not_Available
      );

    chatContext.agent = AIMessagingSelector.getAgent(agentId);

    if (chatContext.agent == null)
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_AGENT_NOT_FOUND,
        Label.AI_Error_Agent_Not_Available
      );
    if (chatContext.agent.IsActive__c != true)
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_AGENT_INACTIVE,
        Label.AI_Error_Agent_Inactive
      );

    // The default access mode is Assigned Users Only: an agent nobody is assigned to is closed to everyone.
    if (
      chatContext.agent.AccessMode__c !=
      AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS &&
      !AIMessagingSelector.isUserAssignedToAgent(
        chatContext.agent.Id,
        chatContext.userId
      )
    ) {
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_AGENT_NOT_ASSIGNED,
        Label.AI_Error_Agent_Not_Assigned
      );
    }

    // [4]
    String termsStatus = AIMessagingSelector.getTermsAcceptanceStatus(
      chatContext.userId,
      AIAssistSettingsService.getSettings().CurrentTermsVersion__c
    );

    if (termsStatus == AIMessagingSelector.TERMS_OUTDATED)
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_TERMS_VERSION_CHANGED,
        Label.AI_Error_Terms_Version_Changed
      );
    if (termsStatus == AIMessagingSelector.TERMS_NONE)
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_TERMS_NOT_ACKNOWLEDGED,
        Label.AI_Error_Terms_Not_Acknowledged
      );

    // [5] No channel supplied, no settings row and no allow-list all mean unrestricted. A channel the object model does not define is refused here rather than failing later on the restricted picklist.
    chatContext.userSettings = AIMessagingSelector.getUserSettings(
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
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_CHANNEL_NOT_ALLOWED,
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
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_CHANNEL_NOT_ALLOWED,
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
        AIViolationService.recordDeterministicViolation(
          AIAssistApplicationConstants.VIOLATION_TYPE_UNAUTHORIZED_DATA_ACCESS,
          chatContext.agent.Id,
          chatContext.userId,
          null,
          null
        ); // A user pointing a chat at a record they may not read is the violation the object model calls Unauthorized Data Access.
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_RECORD_ACCESS_DENIED,
          Label.AI_Error_Record_Access_Denied
        );
      }

      // An agent built for one kind of record is not offered for another. It is built for the object on the agent itself and for any added to it.
      if (
        !AIMessagingSelector.agentSupportsObject(
          chatContext.agent.Id,
          chatContext.agent.ObjectType__c,
          relatedRecordType.getName(),
          relatedRecordType.getLocalName()
        )
      ) {
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_AGENT_NOT_AVAILABLE,
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
        AIViolationService.recordDeterministicViolation(
          AIAssistApplicationConstants.VIOLATION_TYPE_UNAUTHORIZED_DATA_ACCESS,
          chatContext.agent.Id,
          chatContext.userId,
          null,
          null
        ); // A user pointing a chat at a record they may not read is the violation the object model calls Unauthorized Data Access.
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_RECORD_ACCESS_DENIED,
          Label.AI_Error_Record_Access_Denied
        );
      }
    }

    return chatContext;
  }
}
