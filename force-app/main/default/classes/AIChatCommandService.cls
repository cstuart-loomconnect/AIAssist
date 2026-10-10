/*
Class Name: AIChatCommandService

=================================================================
=================================================================

Description: Slash commands (AIChatCommand__mdt): which exist for this user, agent and record, and how a message is
split into what the user sees and the command's hidden instructions.

A command is usable when it is active, for this object (or any) and this agent (or any), and its
Available To level is at or below the user's: Admins Only needs the AI Assist Admin permission set,
Super Users and Admins needs Super User or Admin. The level comes from the permission sets the user
holds, not from a field on the user record.

Queried with SOQL, not getAll(), because getAll() cuts the long prompt text at 255 characters.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from the old command service. The user level now comes from permission sets, because the user type field on User is removed by the security model.
*/

public with sharing class AIChatCommandService {
  @TestVisible
  private static List<AIChatCommand__mdt> testCommands; // Tests set this instead of reading custom metadata, which cannot be inserted.

  public static List<AIChatDataStructure.CommandOption> getAvailableCommands(
    Id agentId,
    AIChatDataStructure.RecordContext record
  ) {
    List<AIChatDataStructure.CommandOption> options = new List<AIChatDataStructure.CommandOption>();

    List<AIChatCommand__mdt> allCommands = testCommands != null
      ? testCommands
      : [
          SELECT
            Id,
            DeveloperName,
            Command__c,
            Description__c,
            PromptText__c,
            ObjectAPIName__c,
            AgentDeveloperName__c,
            AvailableTo__c,
            IsActive__c,
            DisplayOrder__c
          FROM AIChatCommand__mdt
          WITH SYSTEM_MODE
        ];
    List<AIAgent__c> matchingAgents = [
      SELECT DeveloperName__c
      FROM AIAgent__c
      WHERE Id = :agentId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    String agentDeveloperName = matchingAgents.isEmpty()
      ? null
      : matchingAgents[0].DeveloperName__c;
    String userLevel = getHighestPermissionLevel(UserInfo.getUserId());

    // Usable means active, for this object (or any), this agent (or any) and a level the user holds.
    List<AIChatCommand__mdt> usableCommands = new List<AIChatCommand__mdt>();

    for (AIChatCommand__mdt candidateCommand : allCommands) {
      if (
        candidateCommand.IsActive__c != true ||
        String.isBlank(candidateCommand.Command__c)
      )
        continue;
      if (
        String.isNotBlank(candidateCommand.ObjectAPIName__c) &&
        candidateCommand.ObjectAPIName__c != record.objectApiName
      )
        continue;
      if (
        String.isNotBlank(candidateCommand.AgentDeveloperName__c) &&
        candidateCommand.AgentDeveloperName__c != agentDeveloperName
      )
        continue;
      if (!isAvailableTo(candidateCommand.AvailableTo__c, userLevel))
        continue;
      usableCommands.add(candidateCommand);
    }

    usableCommands.sort(new DisplayOrder());

    for (AIChatCommand__mdt command : usableCommands) {
      AIChatDataStructure.CommandOption option = new AIChatDataStructure.CommandOption();
      option.id = command.Id;
      option.command = command.Command__c;
      option.description = command.Description__c;
      option.isRecordSpecific = String.isNotBlank(command.ObjectAPIName__c);
      option.scopeLabel = option.isRecordSpecific
        ? (record.objectLabel == null
            ? command.ObjectAPIName__c
            : record.objectLabel)
        : null;

      options.add(option);
    }

    return options;
  }

  // The command typed, if the user can use it here: the same rules as the list, so a command that is not offered cannot be typed either.
  public static AIChatCommand__mdt findCommand(
    String commandToken,
    Id agentId,
    String objectApiName
  ) {
    List<AIChatCommand__mdt> allCommands = testCommands != null
      ? testCommands
      : [
          SELECT
            Id,
            DeveloperName,
            Command__c,
            Description__c,
            PromptText__c,
            ObjectAPIName__c,
            AgentDeveloperName__c,
            AvailableTo__c,
            IsActive__c,
            DisplayOrder__c
          FROM AIChatCommand__mdt
          WITH SYSTEM_MODE
        ];
    List<AIAgent__c> matchingAgents = [
      SELECT DeveloperName__c
      FROM AIAgent__c
      WHERE Id = :agentId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    String agentDeveloperName = matchingAgents.isEmpty()
      ? null
      : matchingAgents[0].DeveloperName__c;
    String userLevel = getHighestPermissionLevel(UserInfo.getUserId());

    // Usable means active, for this object (or any), this agent (or any) and a level the user holds.
    List<AIChatCommand__mdt> usableCommands = new List<AIChatCommand__mdt>();

    for (AIChatCommand__mdt candidateCommand : allCommands) {
      if (
        candidateCommand.IsActive__c != true ||
        String.isBlank(candidateCommand.Command__c)
      )
        continue;
      if (
        String.isNotBlank(candidateCommand.ObjectAPIName__c) &&
        candidateCommand.ObjectAPIName__c != objectApiName
      )
        continue;
      if (
        String.isNotBlank(candidateCommand.AgentDeveloperName__c) &&
        candidateCommand.AgentDeveloperName__c != agentDeveloperName
      )
        continue;
      if (!isAvailableTo(candidateCommand.AvailableTo__c, userLevel))
        continue;
      usableCommands.add(candidateCommand);
    }

    usableCommands.sort(new DisplayOrder());

    for (AIChatCommand__mdt command : usableCommands) {
      if (command.Command__c == commandToken)
        return command;
    }

    return null;
  }

  // Each level includes the ones above it. Blank, like All Users, is open to everyone.
  @TestVisible
  private static Boolean isAvailableTo(String availableTo, String userLevel) {
    if (
      availableTo ==
      AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_ADMINS_ONLY
    )
      return userLevel == AIAssistApplicationConstants.USER_LEVEL_ADMIN;
    if (
      availableTo ==
      AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_SUPER_USERS_AND_ADMINS
    )
      return userLevel == AIAssistApplicationConstants.USER_LEVEL_ADMIN ||
        userLevel == AIAssistApplicationConstants.USER_LEVEL_SUPER_USER;

    return true;
  }

  // Lowest display order first, blank last, then by command.
  private class DisplayOrder implements Comparator<AIChatCommand__mdt> {
    public Integer compare(
      AIChatCommand__mdt first,
      AIChatCommand__mdt second
    ) {
      if (first.DisplayOrder__c != second.DisplayOrder__c) {
        if (first.DisplayOrder__c == null)
          return 1;
        if (second.DisplayOrder__c == null)
          return -1;
        return first.DisplayOrder__c < second.DisplayOrder__c ? -1 : 1;
      }

      return first.Command__c.compareTo(second.Command__c);
    }
  }

  // What the user sees: everything before a command's hidden instructions.
  public static String getDisplayText(String messageBody) {
    if (String.isBlank(messageBody))
      return '';

    Integer separatorIndex = messageBody.indexOf(
      AIAssistApplicationConstants.CHAT_COMMAND_PROMPT_SEPARATOR
    );
    return separatorIndex < 0 ? messageBody : messageBody.left(separatorIndex);
  }

  public static Boolean isCommandText(String text) {
    return String.isNotBlank(text) &&
      Pattern.matches(
        AIAssistApplicationConstants.CHAT_COMMAND_PATTERN,
        text.trim()
      );
  }

  public static String getCommandToken(String text) {
    return text.trim().split('\\s', 2)[0];
  }

  // Admin, Super User or User, by the highest AI Assist permission set the user holds. Decides which slash commands they see.
  private static String getHighestPermissionLevel(Id userId) {
    Set<String> heldPermissionSetNames = getHeldPermissionSetNames(userId);

    return heldPermissionSetNames.contains(
        AIAssistApplicationConstants.PERMISSION_SET_ADMIN_USER
      )
      ? AIAssistApplicationConstants.USER_LEVEL_ADMIN
      : heldPermissionSetNames.contains(
            AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER
          )
          ? AIAssistApplicationConstants.USER_LEVEL_SUPER_USER
          : AIAssistApplicationConstants.USER_LEVEL_USER;
  }

  // These queries must see every user's records, not just the running user's, so they run in a class declared without sharing.
  private static SystemReader systemReader = new SystemReader();

  @TestVisible
  private static Set<String> getHeldPermissionSetNames(Id userId) {
    return systemReader.getHeldPermissionSetNames(userId);
  }

  private without sharing class SystemReader {
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
