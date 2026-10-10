/*
Class Name: AIChatCommandService

=================================================================
=================================================================

Description: Slash commands (AIChatCommand__mdt) for the chat window.

Step 1: List the commands this user can use for the agent and record, in display order
Step 2: Find the command the user typed, using the same rules so an unlisted command cannot be typed
Step 3: Work out the user's level from the permission sets they hold
Step 4: Split a message into what the user sees and the command's hidden instructions

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIChatCommandService {

    // Lowest display order first, blank last, then by command.
    private class DisplayOrder implements Comparator<AIChatCommand__mdt> {

        public Integer compare(AIChatCommand__mdt first, AIChatCommand__mdt second) {

            // [1] Order by display order, with blank display orders last
            if (first.DisplayOrder__c != second.DisplayOrder__c) {

                if (first.DisplayOrder__c == null) return 1;
                if (second.DisplayOrder__c == null) return -1;
                return first.DisplayOrder__c < second.DisplayOrder__c ? -1 : 1;
            }

            // [2] Order commands with the same display order by their command text
            return first.Command__c.compareTo(second.Command__c);
        }
    }

    @TestVisible
    private static List<AIChatCommand__mdt> testCommands; // Tests set this instead of reading custom metadata, which cannot be inserted.

    // The commands this user can use on the record, in display order, for the list the window shows.
    public static List<AIChatDataStructure.CommandOption> getAvailableCommands(Id agentId, AIChatDataStructure.RecordContext record) {

        // [1] Start with no options
        List<AIChatDataStructure.CommandOption> options = new List<AIChatDataStructure.CommandOption>();

        // [2] Read every command, or the test commands when a test has set them
        List<AIChatCommand__mdt> allCommands = testCommands != null ? testCommands : [SELECT Id, DeveloperName, Command__c, Description__c, PromptText__c, ObjectAPIName__c, AgentDeveloperName__c, AvailableTo__c, IsActive__c, DisplayOrder__c FROM AIChatCommand__mdt WITH SYSTEM_MODE];

        // [3] Find the agent's developer name, because commands can be limited to one agent
        List<AIAgent__c> matchingAgents = [SELECT DeveloperName__c FROM AIAgent__c WHERE Id = :agentId WITH SYSTEM_MODE LIMIT 1];
        String agentDeveloperName = matchingAgents.isEmpty() ? null : matchingAgents[0].DeveloperName__c;

        // [4] Find the user's level, because some commands are limited to admins or super users
        String userLevel = getHighestPermissionLevel(UserInfo.getUserId());

        // [5] Keep the commands that are usable: active, for this object (or any), this agent (or any) and a level the user holds
        List<AIChatCommand__mdt> usableCommands = new List<AIChatCommand__mdt>();

        for (AIChatCommand__mdt candidateCommand : allCommands) {

            if (candidateCommand.IsActive__c != true || String.isBlank(candidateCommand.Command__c)) continue;
            if (String.isNotBlank(candidateCommand.ObjectAPIName__c) && candidateCommand.ObjectAPIName__c != record.objectApiName) continue;
            if (String.isNotBlank(candidateCommand.AgentDeveloperName__c) && candidateCommand.AgentDeveloperName__c != agentDeveloperName) continue;
            if (!isAvailableTo(candidateCommand.AvailableTo__c, userLevel)) continue;
            usableCommands.add(candidateCommand);
        }

        // [6] Put the usable commands in display order
        usableCommands.sort(new DisplayOrder());

        // [7] Turn each usable command into an option for the window
        for (AIChatCommand__mdt command : usableCommands) {

            AIChatDataStructure.CommandOption option = new AIChatDataStructure.CommandOption();
            option.id = command.Id;
            option.command = command.Command__c;
            option.description = command.Description__c;
            option.isRecordSpecific = String.isNotBlank(command.ObjectAPIName__c);
            option.scopeLabel = option.isRecordSpecific ? (record.objectLabel == null ? command.ObjectAPIName__c : record.objectLabel) : null;

            options.add(option);
        }

        // [8] Return the options
        return options;
    }

    // The command typed, if the user can use it here: the same rules as the list, so a command that is not offered cannot be typed either.
    public static AIChatCommand__mdt findCommand(String commandToken, Id agentId, String objectApiName) {

        // [1] Read every command, or the test commands when a test has set them
        List<AIChatCommand__mdt> allCommands = testCommands != null ? testCommands : [SELECT Id, DeveloperName, Command__c, Description__c, PromptText__c, ObjectAPIName__c, AgentDeveloperName__c, AvailableTo__c, IsActive__c, DisplayOrder__c FROM AIChatCommand__mdt WITH SYSTEM_MODE];

        // [2] Find the agent's developer name, because commands can be limited to one agent
        List<AIAgent__c> matchingAgents = [SELECT DeveloperName__c FROM AIAgent__c WHERE Id = :agentId WITH SYSTEM_MODE LIMIT 1];
        String agentDeveloperName = matchingAgents.isEmpty() ? null : matchingAgents[0].DeveloperName__c;

        // [3] Find the user's level, because some commands are limited to admins or super users
        String userLevel = getHighestPermissionLevel(UserInfo.getUserId());

        // [4] Keep the commands that are usable: active, for this object (or any), this agent (or any) and a level the user holds
        List<AIChatCommand__mdt> usableCommands = new List<AIChatCommand__mdt>();

        for (AIChatCommand__mdt candidateCommand : allCommands) {

            if (candidateCommand.IsActive__c != true || String.isBlank(candidateCommand.Command__c)) continue;
            if (String.isNotBlank(candidateCommand.ObjectAPIName__c) && candidateCommand.ObjectAPIName__c != objectApiName) continue;
            if (String.isNotBlank(candidateCommand.AgentDeveloperName__c) && candidateCommand.AgentDeveloperName__c != agentDeveloperName) continue;
            if (!isAvailableTo(candidateCommand.AvailableTo__c, userLevel)) continue;
            usableCommands.add(candidateCommand);
        }

        // [5] Put the usable commands in display order
        usableCommands.sort(new DisplayOrder());

        // [6] Return the usable command that matches what was typed
        for (AIChatCommand__mdt command : usableCommands) {

            if (command.Command__c == commandToken) return command;
        }

        // [7] Return nothing when no usable command matches
        return null;
    }

    // What the user sees: everything before a command's hidden instructions.
    public static String getDisplayText(String messageBody) {

        // [1] Show nothing for a blank message
        if (String.isBlank(messageBody)) return '';

        // [2] Cut the message where the hidden instructions start, if they are there
        Integer separatorIndex = messageBody.indexOf(AIAssistApplicationConstants.CHAT_COMMAND_PROMPT_SEPARATOR);
        return separatorIndex < 0 ? messageBody : messageBody.left(separatorIndex);
    }

    // Whether the text is shaped like a slash command.
    public static Boolean isCommandText(String text) {

        // [1] Check the trimmed text against the command pattern
        return String.isNotBlank(text) && Pattern.matches(AIAssistApplicationConstants.CHAT_COMMAND_PATTERN, text.trim());
    }

    // The first word of the text, which is the command.
    public static String getCommandToken(String text) {

        // [1] Return the text up to the first space
        return text.trim().split('\\s', 2)[0];
    }

    // Each level includes the ones above it. Blank, like All Users, is open to everyone.
    @TestVisible
    private static Boolean isAvailableTo(String availableTo, String userLevel) {

        // [1] Admins only commands need the admin level
        if (availableTo == AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_ADMINS_ONLY) return userLevel == AIAssistApplicationConstants.USER_LEVEL_ADMIN;

        // [2] Super user commands need the super user or admin level
        if (availableTo == AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_SUPER_USERS_AND_ADMINS) return userLevel == AIAssistApplicationConstants.USER_LEVEL_ADMIN || userLevel == AIAssistApplicationConstants.USER_LEVEL_SUPER_USER;

        // [3] Any other command is open to everyone
        return true;
    }

    // Admin, Super User or User, by the highest AI Assist permission set the user holds. Decides which slash commands they see.
    private static String getHighestPermissionLevel(Id userId) {

        // [1] Find the permission sets the user holds
        Set<String> heldPermissionSetNames = getHeldPermissionSetNames(userId);

        // [2] Return the highest level they hold, or the plain user level
        return heldPermissionSetNames.contains(AIAssistApplicationConstants.PERMISSION_SET_ADMIN_USER) ? AIAssistApplicationConstants.USER_LEVEL_ADMIN : heldPermissionSetNames.contains(AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER) ? AIAssistApplicationConstants.USER_LEVEL_SUPER_USER : AIAssistApplicationConstants.USER_LEVEL_USER;
    }

    // The API names of every permission set the user holds: assigned directly, and the name of each permission set group assigned to them together with the permission sets inside that group. A permission set reached only through a group has no assignment row of its own, so matching on assignment rows alone would miss it.
    @TestVisible
    private static Set<String> getHeldPermissionSetNames(Id userId) {

        // [1] Start with no names and no groups
        Set<String> heldNames = new Set<String>();
        Set<Id> heldGroupIds = new Set<Id>();

        // [2] Add every permission set assigned directly, and note any group assigned
        for (PermissionSetAssignment heldAssignment : [SELECT PermissionSet.Name, PermissionSetGroupId, PermissionSetGroup.DeveloperName FROM PermissionSetAssignment WHERE AssigneeId = :userId WITH SYSTEM_MODE LIMIT 2000]) {

            heldNames.add(heldAssignment.PermissionSet.Name);

            if (heldAssignment.PermissionSetGroupId != null) {

                heldGroupIds.add(heldAssignment.PermissionSetGroupId);
                heldNames.add(heldAssignment.PermissionSetGroup.DeveloperName);
            }
        }

        // [3] Add the permission sets inside each assigned group
        if (!heldGroupIds.isEmpty()) {

            for (PermissionSetGroupComponent member : [SELECT PermissionSet.Name FROM PermissionSetGroupComponent WHERE PermissionSetGroupId IN :heldGroupIds WITH SYSTEM_MODE LIMIT 2000]) {

                heldNames.add(member.PermissionSet.Name);
            }
        }

        // [4] Return the names
        return heldNames;
    }
}
