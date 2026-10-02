/*
Class Name: AITokenUsageServiceTest

=================================================================
=================================================================

Description: Testing utility for AITokenUsageService: token usage over a period for everyone, an agent, a user or a conversation, from the daily usage rows.

=================================================================
=================================================================
Applicable Classes:

AITokenUsageService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AITokenUsageServiceTest {
  // testScenario1: Global usage adds input and output tokens across users and agents for the dates, both ends included.
  // testScenario2: Agent and user usage count only their own rows.
  // testScenario3: No usage is zero, not null.
  // testScenario4: A range that is missing or backwards, and an Id of the wrong type, are refused.
  // testScenario5: A conversation's running total comes from the conversation, and a missing one is refused with the not found label.

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
    List<User> users = AIAssistTestDataFactory.createUsers(2, true);
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    List<AIUsageDaily__c> rows = AIAssistTestDataFactory.createAIUsageDailies(
      users[0].Id,
      agent.Id,
      model.Id,
      3,
      false
    );
    rows.addAll(
      AIAssistTestDataFactory.createAIUsageDailies(
        users[1].Id,
        agent.Id,
        model.Id,
        1,
        false
      )
    );
    for (AIUsageDaily__c row : rows) {
      row.InputTokens__c = 100;
      row.OutputTokens__c = 50;
    }
    insert rows;
    Date today = Datetime.now().dateGmt();
    Decimal allDays;
    Decimal todayOnly;

    Test.startTest();
    allDays = AITokenUsageService.getGlobalUsage(today.addDays(-2), today);
    todayOnly = AITokenUsageService.getGlobalUsage(today, today);
    Test.stopTest();

    Assert.areEqual(600, allDays, 'Four rows of 150.');
    Assert.areEqual(
      300,
      todayOnly,
      'Today\'s two rows: both ends of the range are included.'
    );
  }

  @IsTest
  static void testScenario2() {
    List<User> users = AIAssistTestDataFactory.createUsers(2, true);
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      2,
      model.Id,
      true
    );
    List<AIUsageDaily__c> rows = AIAssistTestDataFactory.createAIUsageDailies(
      users[0].Id,
      agents[0].Id,
      model.Id,
      1,
      false
    );
    rows.addAll(
      AIAssistTestDataFactory.createAIUsageDailies(
        users[1].Id,
        agents[1].Id,
        model.Id,
        1,
        false
      )
    );
    rows[0].InputTokens__c = 10;
    rows[1].InputTokens__c = 1000;
    insert rows;
    Date today = Datetime.now().dateGmt();

    Test.startTest();
    Decimal agentOne = AITokenUsageService.getAgentUsage(
      agents[0].Id,
      today,
      today
    );
    Decimal userTwo = AITokenUsageService.getUserUsage(
      users[1].Id,
      today,
      today
    );
    Test.stopTest();

    Assert.areEqual(10, agentOne, 'Only that agent.');
    Assert.areEqual(1000, userTwo, 'Only that user.');
  }

  @IsTest
  static void testScenario3() {
    Date today = Datetime.now().dateGmt();

    Test.startTest();
    Decimal everyone = AITokenUsageService.getGlobalUsage(today, today);
    Decimal user = AITokenUsageService.getUserUsage(
      UserInfo.getUserId(),
      today,
      today
    );
    Test.stopTest();

    Assert.areEqual(0, everyone, 'Zero.');
    Assert.areEqual(0, user, 'Zero.');
  }

  @IsTest
  static void testScenario4() {
    Date today = Datetime.now().dateGmt();
    List<String> codes = new List<String>();

    Test.startTest();
    try {
      AITokenUsageService.getGlobalUsage(today, today.addDays(-1));
      Assert.fail('A backwards range should have thrown.');
    } catch (AIMessagingException ex) {
      codes.add(ex.code);
    }
    try {
      AITokenUsageService.getGlobalUsage(null, today);
      Assert.fail('A missing start should have thrown.');
    } catch (AIMessagingException ex) {
      codes.add(ex.code);
    }
    try {
      AITokenUsageService.getAgentUsage(UserInfo.getUserId(), today, today);
      Assert.fail('A user Id is not an agent.');
    } catch (AIMessagingException ex) {
      codes.add(ex.code);
    }
    try {
      AITokenUsageService.getUserUsage(null, today, today);
      Assert.fail('No user should have thrown.');
    } catch (AIMessagingException ex) {
      codes.add(ex.code);
    }
    Test.stopTest();

    Assert.areEqual(4, codes.size(), 'Each was refused.');
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_AGENT_NOT_FOUND,
      codes[2],
      'An agent Id of the wrong type.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_NOT_AUTHORISED,
      codes[3],
      'No user.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      70,
      2,
      true
    );
    Decimal total;
    String message;

    Test.startTest();
    total = AITokenUsageService.getConversationUsage(conversation.Id);
    try {
      AITokenUsageService.getConversationUsage(agent.Id);
      Assert.fail('An agent Id is not a conversation.');
    } catch (AIMessagingException ex) {
      message = ex.getMessage();
    }
    Test.stopTest();

    Assert.areEqual(140, total, 'The roll-up.');
    Assert.areEqual(
      Label.AI_Error_Conversation_Not_Found,
      message,
      'The text is the Custom Label.'
    );
  }
}
