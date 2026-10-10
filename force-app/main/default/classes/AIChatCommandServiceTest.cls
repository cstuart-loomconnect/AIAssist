/*
Class Name: AIChatCommandServiceTest

=================================================================
=================================================================

Description: Testing utility for AIChatCommandService: which slash commands a user can use, and splitting a message into what is shown and what is hidden. Commands are supplied in memory because custom metadata cannot be inserted.

=================================================================
=================================================================
Applicable Classes:

AIChatCommandService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIChatCommandServiceTest {

    // testScenario1: Command text is recognised, and the token and display text are split from the hidden instructions.
    // testScenario2: Only active commands for this object and agent are offered, lowest display order first, blank last.
    // testScenario3: Availability levels include the ones above, and a command that is not offered cannot be typed.
    // testScenario4: findCommand finds a usable command and returns null for one that is not offered.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Build a command message with hidden instructions
        String body =
        '/summarise now' +
        AIAssistApplicationConstants.CHAT_COMMAND_PROMPT_SEPARATOR +
        'Summarise the record.';

        // [2] Run the command text checks
        Boolean isCommand;
        Boolean notCommand;
        String token;
        String shown;
        String blank;

        Test.startTest();
            isCommand = AIChatCommandService.isCommandText('/summarise now');
            notCommand =
            AIChatCommandService.isCommandText('hello /summarise') ||
            AIChatCommandService.isCommandText('/') ||
            AIChatCommandService.isCommandText(null);
            token = AIChatCommandService.getCommandToken('  /summarise now');
            shown = AIChatCommandService.getDisplayText(body);
            blank = AIChatCommandService.getDisplayText(null);
        Test.stopTest();

        // [3] Check the command text results
        Assert.isTrue(isCommand, 'A slash command should be recognised as command text.');
        Assert.isFalse(notCommand, 'Text that is not a slash command should not be recognised.');

        Assert.areEqual('/summarise', token, 'The token should be the first word of the command.');
        Assert.areEqual('/summarise now', shown, 'The hidden instructions should be cut off the display text.');
        Assert.areEqual('', blank, 'A null message should show as blank.');
    }

    @IsTest static void testScenario2() {

        // [1] Create an agent
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        // [2] Supply the commands in memory
        AIChatCommandService.testCommands = new List<AIChatCommand__mdt>{
            new AIChatCommand__mdt(Command__c = '/b', IsActive__c = true, DisplayOrder__c = 2),
            new AIChatCommand__mdt(Command__c = '/a', IsActive__c = true, DisplayOrder__c = 1),
            new AIChatCommand__mdt(Command__c = '/z', IsActive__c = true),
            new AIChatCommand__mdt(Command__c = '/off', IsActive__c = false),
            new AIChatCommand__mdt(Command__c = '/contact', IsActive__c = true, ObjectAPIName__c = 'Contact'),
            new AIChatCommand__mdt(Command__c = '/other', IsActive__c = true, AgentDeveloperName__c = 'Someone_Else')
        };

        // [3] Set the record context to an Account
        AIChatDataStructure.RecordContext record = new AIChatDataStructure.RecordContext();
        record.objectApiName = 'Account';

        // [4] Get the available commands
        List<AIChatDataStructure.CommandOption> options;

        Test.startTest();
            options = AIChatCommandService.getAvailableCommands(agent.Id, record);
        Test.stopTest();

        // [5] Check only the matching commands are offered, in order
        Assert.areEqual(3, options.size(), 'Inactive, other object and other agent commands should be left out.');
        Assert.areEqual(new List<String>{ '/a', '/b', '/z' }, new List<String>{
            options[0].command,
            options[1].command,
            options[2].command
        }, 'The commands should be in display order, with a blank display order last.');
    }

    @IsTest static void testScenario3() {

        // [1] Check availability for each user level
        Boolean adminOnlyForUser;
        Boolean adminOnlyForAdmin;
        Boolean superForSuper;
        Boolean superForUser;
        Boolean openToAll;

        Test.startTest();
            adminOnlyForUser = AIChatCommandService.isAvailableTo(AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_ADMINS_ONLY, AIAssistApplicationConstants.USER_LEVEL_USER);
            adminOnlyForAdmin = AIChatCommandService.isAvailableTo(AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_ADMINS_ONLY, AIAssistApplicationConstants.USER_LEVEL_ADMIN);
            superForSuper = AIChatCommandService.isAvailableTo(AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_SUPER_USERS_AND_ADMINS, AIAssistApplicationConstants.USER_LEVEL_SUPER_USER);
            superForUser = AIChatCommandService.isAvailableTo(AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_SUPER_USERS_AND_ADMINS, AIAssistApplicationConstants.USER_LEVEL_USER);
            openToAll = AIChatCommandService.isAvailableTo(null, AIAssistApplicationConstants.USER_LEVEL_USER);
        Test.stopTest();

        // [2] Check which levels are allowed
        Assert.isFalse(adminOnlyForUser || superForUser, 'A plain user should be refused admin and super user commands.');
        Assert.isTrue(adminOnlyForAdmin && superForSuper && openToAll, 'An admin, a super user and a command open to all should be allowed.');
    }

    @IsTest static void testScenario4() {

        // [1] Create an agent
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        // [2] Supply the commands in memory
        AIChatCommandService.testCommands = new List<AIChatCommand__mdt>{
            new AIChatCommand__mdt(Command__c = '/open', IsActive__c = true, PromptText__c = 'Do it.'),
            new AIChatCommand__mdt(Command__c = '/admin', IsActive__c = true, AvailableTo__c = AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_ADMINS_ONLY)
        };

        // [3] Create a plain user
        User plainUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        // [4] Find each command as the plain user
        AIChatCommand__mdt found;
        AIChatCommand__mdt hidden;

        System.runAs(plainUser) {
            Test.startTest();
                found = AIChatCommandService.findCommand('/open', agent.Id, null);
                hidden = AIChatCommandService.findCommand('/admin', agent.Id, null);
            Test.stopTest();
        }

        // [5] Check only the open command is found
        Assert.areEqual('Do it.', found.PromptText__c, 'A command open to everyone should be found.');
        Assert.isNull(hidden, 'An admin command should not be found for a plain user.');
    }
}
