/*
Class Name: AIMessageValidatorTest

=================================================================
=================================================================

Description: Testing utility for AIMessageValidator: every reason a user can be refused when sending a message, as a real end user holding only the AI Assist User permission set.

=================================================================
=================================================================
Applicable Classes:

AIMessageValidator

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIMessageValidatorTest {
  // testScenario1: An open agent and an acceptable message are allowed, and the context carries the user, the agent and the user's settings so nothing is queried twice.
  // testScenario2: A switched-off application refuses every message.
  // testScenario3: Maintenance mode refuses new messages.
  // testScenario4: A blank or null message is refused, a message over the length limit is refused, and one exactly at the limit is allowed.
  // testScenario5: A missing, mistyped, deleted or inactive agent is refused, all but the inactive one as plain 'not available' so nothing is revealed about what exists.
  // testScenario6: An Assigned Users Only agent is closed until the user is assigned, by name or by permission set, while an agent open to all users needs no assignment.
  // testScenario7: With a terms version configured, a user who never accepted, one who accepted an earlier version and one who accepted the current version are told so, or allowed.
  // testScenario8: A channel the object model does not define is refused, as is one outside the user's allow-list, while one on the list, or none at all, is allowed.
  // testScenario9: A chat about a record is allowed for a record the user owns, and refused for a mismatched object name, a record the user cannot see, or an object the agent is not built for.

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
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, true);
    AIMessageValidator.ChatContext context;

    System.runAs(chatUser) {
      Test.startTest();
      context = AIMessageValidator.validateSendRequest(
        agent.Id,
        'Hello',
        AIAssistApplicationConstants.CHANNEL_UTILITY_BAR,
        null,
        null
      );
      Test.stopTest();
    }

    Assert.areEqual(chatUser.Id, context.userId, 'The user.');
    Assert.areEqual(agent.Id, context.agent.Id, 'The agent.');
    Assert.isNotNull(context.userSettings, 'And the user\'s settings.');
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;

    Test.startTest();
    try {
      AIMessageValidator.validateSendRequest(
        agent.Id,
        'Hello',
        null,
        null,
        null
      );
      Assert.fail('A switched-off application should have thrown.');
    } catch (AIMessagingException ex) {
      Assert.areEqual(
        AIAssistApplicationConstants.ERROR_APPLICATION_DISABLED,
        ex.code,
        'The code.'
      );
      Assert.areEqual(
        Label.AI_Error_Application_Inactive,
        ex.getMessage(),
        'The text is the Custom Label.'
      );
      Assert.isTrue(ex.isRefusal, 'An expected refusal, not a fault.');
    }
    Test.stopTest();
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIAssistUISettings__c uiSettings = AIAssistUISettings__c.getOrgDefaults();
    uiSettings.IsMaintenanceMode__c = true;
    upsert uiSettings;

    Test.startTest();
    try {
      AIMessageValidator.validateSendRequest(
        agent.Id,
        'Hello',
        null,
        null,
        null
      );
      Assert.fail('Maintenance mode should have thrown.');
    } catch (AIMessagingException ex) {
      Assert.areEqual(
        AIAssistApplicationConstants.ERROR_MAINTENANCE_MODE,
        ex.code,
        'The code.'
      );
      Assert.areEqual(
        Label.AI_Error_Maintenance_Mode,
        ex.getMessage(),
        'The text is the Custom Label.'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    String atTheLimit = 'x'
      .repeat(AIAssistApplicationConstants.MAX_USER_MESSAGE_CHARACTERS);
    List<String> codes = new List<String>();

    Test.startTest();
    for (String body : new List<String>{ '   ', null, atTheLimit + 'x' }) {
      try {
        AIMessageValidator.validateSendRequest(
          agent.Id,
          body,
          null,
          null,
          null
        );
        Assert.fail('This message should have been refused.');
      } catch (AIMessagingException ex) {
        codes.add(ex.code);
      }
    }

    AIMessageValidator.ChatContext allowed = AIMessageValidator.validateSendRequest(
      agent.Id,
      atTheLimit,
      null,
      null,
      null
    );
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_MESSAGE_EMPTY,
      codes[0],
      'Blank.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_MESSAGE_EMPTY,
      codes[1],
      'Null.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_MESSAGE_TOO_LONG,
      codes[2],
      'One over the limit.'
    );
    Assert.isNotNull(allowed, 'A message exactly at the limit is allowed.');
  }

  @IsTest
  static void testScenario5() {
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      2,
      model.Id,
      true
    );
    agents[0].IsActive__c = false;
    update agents[0];
    Id deletedId = agents[1].Id;
    delete agents[1];
    Map<Id, String> codeByAgentId = new Map<Id, String>();
    Map<Id, String> messageByAgentId = new Map<Id, String>();

    Test.startTest();
    for (
      Id agentId : new List<Id>{ agents[0].Id, deletedId, UserInfo.getUserId() }
    ) {
      try {
        AIMessageValidator.validateSendRequest(
          agentId,
          'Hello',
          null,
          null,
          null
        );
        Assert.fail('This agent should have been refused.');
      } catch (AIMessagingException ex) {
        codeByAgentId.put(agentId, ex.code);
        messageByAgentId.put(agentId, ex.getMessage());
      }
    }

    try {
      AIMessageValidator.validateSendRequest(null, 'Hello', null, null, null);
      Assert.fail('No agent should have been refused.');
    } catch (AIMessagingException ex) {
      codeByAgentId.put(null, ex.code);
    }
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_AGENT_INACTIVE,
      codeByAgentId.get(agents[0].Id),
      'An inactive agent.'
    );
    Assert.areEqual(
      Label.AI_Error_Agent_Inactive,
      messageByAgentId.get(agents[0].Id),
      'With its own label.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_AGENT_NOT_FOUND,
      codeByAgentId.get(deletedId),
      'A deleted agent.'
    );
    Assert.areEqual(
      Label.AI_Error_Agent_Not_Available,
      messageByAgentId.get(deletedId),
      'Reported as not available.'
    );
    Assert.areEqual(
      Label.AI_Error_Agent_Not_Available,
      messageByAgentId.get(UserInfo.getUserId()),
      'An Id of the wrong type is reported the same way.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_AGENT_NOT_FOUND,
      codeByAgentId.get(null),
      'No Id at all.'
    );
  }

  @IsTest
  static void testScenario6() {
    List<User> users = AIAssistTestDataFactory.createUsers(2, true);
    AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      4,
      model.Id,
      false
    );
    agents[0]
      .AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
    agents[1]
      .AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
    agents[2]
      .AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
    insert agents;
    AIAssistTestDataFactory.createAIAgentAssignments(
      agents[1].Id,
      new List<User>{ users[0] },
      true
    );
    AIAssistTestDataFactory.createAIAgentAssignments(
      agents[2].Id,
      'AIAssistUser',
      true
    );
    Map<Id, String> codeByAgentId = new Map<Id, String>();

    Test.startTest();
    System.runAs(users[0]) {
      for (AIAgent__c agent : agents) {
        try {
          AIMessageValidator.validateSendRequest(
            agent.Id,
            'Hello',
            null,
            null,
            null
          );
          codeByAgentId.put(agent.Id, 'ALLOWED');
        } catch (AIMessagingException ex) {
          codeByAgentId.put(agent.Id, ex.code);
        }
      }
    }
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_AGENT_NOT_ASSIGNED,
      codeByAgentId.get(agents[0].Id),
      'An agent nobody is assigned to is closed.'
    );
    Assert.areEqual(
      'ALLOWED',
      codeByAgentId.get(agents[1].Id),
      'Assigned by name.'
    );
    Assert.areEqual(
      'ALLOWED',
      codeByAgentId.get(agents[2].Id),
      'Assigned by permission set.'
    );
    Assert.areEqual(
      'ALLOWED',
      codeByAgentId.get(agents[3].Id),
      'Open to all users.'
    );
  }

  @IsTest
  static void testScenario7() {
    List<User> users = AIAssistTestDataFactory.createUsers(3, true);
    AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.CurrentTermsVersion__c = 'v2';
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    System.runAs(users[1]) {
      insert AIAssistTestDataFactory.createAITermsAcknowledgments(
        users[1].Id,
        'v1',
        1,
        false
      );
    }
    System.runAs(users[2]) {
      insert AIAssistTestDataFactory.createAITermsAcknowledgments(
        users[2].Id,
        'v2',
        1,
        false
      );
    }
    List<String> outcomes = new List<String>();
    List<String> messages = new List<String>();

    Test.startTest();
    for (User user : users) {
      System.runAs(user) {
        try {
          AIMessageValidator.validateSendRequest(
            agent.Id,
            'Hello',
            null,
            null,
            null
          );
          outcomes.add('ALLOWED');
        } catch (AIMessagingException ex) {
          outcomes.add(ex.code);
          messages.add(ex.getMessage());
        }
      }
    }
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_TERMS_NOT_ACKNOWLEDGED,
      outcomes[0],
      'Never accepted.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_TERMS_VERSION_CHANGED,
      outcomes[1],
      'Accepted an earlier version.'
    );
    Assert.areEqual('ALLOWED', outcomes[2], 'Accepted the current version.');
    Assert.areEqual(
      Label.AI_Error_Terms_Not_Acknowledged,
      messages[0],
      'Labelled.'
    );
    Assert.areEqual(
      Label.AI_Error_Terms_Version_Changed,
      messages[1],
      'Labelled.'
    );
  }

  @IsTest
  static void testScenario8() {
    List<User> users = AIAssistTestDataFactory.createUsers(1, true);
    AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(
      users[0].Id,
      false
    )[0];
    settings.AllowedChannels__c = AIAssistApplicationConstants.CHANNEL_MOBILE;
    insert settings;
    Map<String, String> outcomeByChannel = new Map<String, String>();

    Test.startTest();
    System.runAs(users[0]) {
      for (
        String channel : new List<String>{
          'Carrier Pigeon',
          AIAssistApplicationConstants.CHANNEL_UTILITY_BAR,
          AIAssistApplicationConstants.CHANNEL_MOBILE,
          ''
        }
      ) {
        try {
          AIMessageValidator.validateSendRequest(
            agent.Id,
            'Hello',
            channel,
            null,
            null
          );
          outcomeByChannel.put(channel, 'ALLOWED');
        } catch (AIMessagingException ex) {
          outcomeByChannel.put(channel, ex.code);
        }
      }
    }
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_CHANNEL_NOT_ALLOWED,
      outcomeByChannel.get('Carrier Pigeon'),
      'An undefined channel would fail on the restricted picklist, so it is refused first.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_CHANNEL_NOT_ALLOWED,
      outcomeByChannel.get(AIAssistApplicationConstants.CHANNEL_UTILITY_BAR),
      'Outside the allow-list.'
    );
    Assert.areEqual(
      'ALLOWED',
      outcomeByChannel.get(AIAssistApplicationConstants.CHANNEL_MOBILE),
      'On the allow-list.'
    );
    Assert.areEqual(
      'ALLOWED',
      outcomeByChannel.get(''),
      'No channel supplied is unrestricted.'
    );
  }

  @IsTest
  static void testScenario9() {
    List<User> users = AIAssistTestDataFactory.createUsers(2, true);
    AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      2,
      model.Id,
      false
    );
    insert agents;
    AIAssistTestDataFactory.createAIAgentObjects(
      agents[1].Id,
      new List<String>{ 'Contact' },
      true
    );
    Account ownAccount;
    System.runAs(users[0]) {
      ownAccount = AIAssistTestDataFactory.createAccounts(1, true)[0];
    }
    AIConversation__c theirConversation = AIAssistTestDataFactory.createAIConversations(
      agents[0].Id,
      users[1].Id,
      1,
      true
    )[0];
    List<String> outcomes = new List<String>();

    Test.startTest();
    System.runAs(users[0]) {
      List<List<Object>> attempts = new List<List<Object>>{
        new List<Object>{ agents[0].Id, 'Account', ownAccount.Id },
        new List<Object>{ agents[0].Id, null, ownAccount.Id },
        new List<Object>{ agents[0].Id, 'Contact', ownAccount.Id },
        new List<Object>{
          agents[0].Id,
          'LoomConnect__AIConversation__c',
          theirConversation.Id
        },
        new List<Object>{ agents[1].Id, 'Account', ownAccount.Id }
      };

      for (List<Object> attempt : attempts) {
        try {
          AIMessageValidator.validateSendRequest(
            (Id) attempt[0],
            'Hello',
            null,
            (String) attempt[1],
            (Id) attempt[2]
          );
          outcomes.add('ALLOWED');
        } catch (AIMessagingException ex) {
          outcomes.add(ex.code);
        }
      }
    }
    Test.stopTest();

    Assert.areEqual(
      'ALLOWED',
      outcomes[0],
      'The user can read their own record.'
    );
    Assert.areEqual(
      'ALLOWED',
      outcomes[1],
      'A blank object name is filled in from the Id.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_RECORD_ACCESS_DENIED,
      outcomes[2],
      'The object name does not match the Id.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_RECORD_ACCESS_DENIED,
      outcomes[3],
      'Another user\'s private conversation is a record this user cannot see.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_AGENT_NOT_AVAILABLE,
      outcomes[4],
      'An agent built for Contact is not offered for an Account.'
    );
  }
}
