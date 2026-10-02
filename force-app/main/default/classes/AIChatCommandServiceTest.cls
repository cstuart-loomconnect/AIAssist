/*
Class Name: AIChatCommandServiceTest

=================================================================
=================================================================

Description: Testing utility for AIChatCommandService: which slash commands a user can use, and splitting a message into what is shown and what is hidden. Commands are supplied in memory because custom metadata cannot be inserted.

=================================================================
=================================================================
Applicable Classes:

AIChatCommandService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIChatCommandServiceTest {
  // testScenario1: Command text is recognised, and the token and display text are split from the hidden instructions.
  // testScenario2: Only active commands for this object and agent are offered, lowest display order first, blank last.
  // testScenario3: Availability levels include the ones above, and a command that is not offered cannot be typed.
  // testScenario4: findCommand finds a usable command and returns null for one that is not offered.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  @IsTest
  static void testScenario1() {
    String body =
      '/summarise now' +
      AIAssistApplicationConstants.CHAT_COMMAND_PROMPT_SEPARATOR +
      'Summarise the record.';

    Test.startTest();
    Boolean isCommand = AIChatCommandService.isCommandText('/summarise now');
    Boolean notCommand =
      AIChatCommandService.isCommandText('hello /summarise') ||
      AIChatCommandService.isCommandText('/') ||
      AIChatCommandService.isCommandText(null);
    String token = AIChatCommandService.getCommandToken('  /summarise now');
    String shown = AIChatCommandService.getDisplayText(body);
    String blank = AIChatCommandService.getDisplayText(null);
    Test.stopTest();

    Assert.isTrue(isCommand, 'A command.');
    Assert.isFalse(notCommand, 'Not commands.');
    Assert.areEqual('/summarise', token, 'The token.');
    Assert.areEqual(
      '/summarise now',
      shown,
      'Hidden instructions are cut off.'
    );
    Assert.areEqual('', blank, 'Blank.');
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    List<AIChatCommand__mdt> commands = new List<AIChatCommand__mdt>{
      new AIChatCommand__mdt(
        Command__c = '/b',
        IsActive__c = true,
        DisplayOrder__c = 2
      ),
      new AIChatCommand__mdt(
        Command__c = '/a',
        IsActive__c = true,
        DisplayOrder__c = 1
      ),
      new AIChatCommand__mdt(Command__c = '/z', IsActive__c = true),
      new AIChatCommand__mdt(Command__c = '/off', IsActive__c = false),
      new AIChatCommand__mdt(
        Command__c = '/contact',
        IsActive__c = true,
        ObjectAPIName__c = 'Contact'
      ),
      new AIChatCommand__mdt(
        Command__c = '/other',
        IsActive__c = true,
        AgentDeveloperName__c = 'Someone_Else'
      )
    };
    AIChatCommandService.testCommands = commands;
    AIChatDataStructure.RecordContext record = new AIChatDataStructure.RecordContext();
    record.objectApiName = 'Account';

    Test.startTest();
    List<AIChatDataStructure.CommandOption> options = AIChatCommandService.getAvailableCommands(
      agent.Id,
      record
    );
    Test.stopTest();

    Assert.areEqual(
      new List<String>{ '/a', '/b', '/z' },
      new List<String>{
        options[0].command,
        options[1].command,
        options[2].command
      },
      'In order.'
    );
    Assert.areEqual(
      3,
      options.size(),
      'Inactive, other object and other agent are left out.'
    );
  }

  @IsTest
  static void testScenario3() {
    Test.startTest();
    Boolean adminOnlyForUser = AIChatCommandService.isAvailableTo(
      AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_ADMINS_ONLY,
      AIAssistApplicationConstants.USER_LEVEL_USER
    );
    Boolean adminOnlyForAdmin = AIChatCommandService.isAvailableTo(
      AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_ADMINS_ONLY,
      AIAssistApplicationConstants.USER_LEVEL_ADMIN
    );
    Boolean superForSuper = AIChatCommandService.isAvailableTo(
      AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_SUPER_USERS_AND_ADMINS,
      AIAssistApplicationConstants.USER_LEVEL_SUPER_USER
    );
    Boolean superForUser = AIChatCommandService.isAvailableTo(
      AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_SUPER_USERS_AND_ADMINS,
      AIAssistApplicationConstants.USER_LEVEL_USER
    );
    Boolean openToAll = AIChatCommandService.isAvailableTo(
      null,
      AIAssistApplicationConstants.USER_LEVEL_USER
    );
    Test.stopTest();

    Assert.isFalse(adminOnlyForUser || superForUser, 'Refused.');
    Assert.isTrue(adminOnlyForAdmin && superForSuper && openToAll, 'Allowed.');
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIChatCommandService.testCommands = new List<AIChatCommand__mdt>{
      new AIChatCommand__mdt(
        Command__c = '/open',
        IsActive__c = true,
        PromptText__c = 'Do it.'
      ),
      new AIChatCommand__mdt(
        Command__c = '/admin',
        IsActive__c = true,
        AvailableTo__c = AIAssistApplicationConstants.CHAT_COMMAND_AVAILABLE_TO_ADMINS_ONLY
      )
    };
    User plainUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIChatCommand__mdt found;
    AIChatCommand__mdt hidden;

    System.runAs(plainUser) {
      Test.startTest();
      found = AIChatCommandService.findCommand('/open', agent.Id, null);
      hidden = AIChatCommandService.findCommand('/admin', agent.Id, null);
      Test.stopTest();
    }

    Assert.areEqual('Do it.', found.PromptText__c, 'Found.');
    Assert.isNull(hidden, 'An admin command is not available to a plain user.');
  }
}
