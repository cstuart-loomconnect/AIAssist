/*
Class Name: AIOrgUsageServiceTest

=================================================================
=================================================================

Description: Testing utility for AIOrgUsageService and AIOrgUsageTotalsBatch: the organisation's running usage totals, and the limit check that reads them. A test cannot insert 30,000 usage rows (10,000 rows of DML per transaction), so the scale scenario stores a total standing for that many and asserts the check reads no usage row at all, which is what makes it independent of how many there are.

=================================================================
=================================================================
Applicable Classes:

AIOrgUsageService, AIOrgUsageTotalsBatch, AIUsageLimitService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIOrgUsageServiceTest {
  // testScenario1: Until totals are stored they are counted from the usage rows; the first usage write stores them, and later writes add to them without reading a usage row.
  // testScenario2: A stored total for an earlier day counts as nothing today, and one for an earlier month as nothing this month.
  // testScenario3: The limit check uses the stored total, not the usage rows: with a total standing for 30,000 rows it refuses at the plan cap and reads no usage row, whatever the rows say.
  // testScenario4: The batch counts the month and the day exactly from the usage rows and replaces what was stored.
  // testScenario5: A malformed stored value is treated as never stored, and a null write changes nothing.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  private class World {
    User chatUser;
    AIAgent__c agent;
    AIMessageValidator.ChatContext context;
  }

  private static World createWorld() {
    World world = new World();
    world.chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    world.agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    world.context = new AIMessageValidator.ChatContext();
    world.context.userId = world.chatUser.Id;
    world.context.agent = world.agent;

    return world;
  }

  private static void store(String state) {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.OrgUsageStateJson__c = state;
    update settings;
    AIAssistSettingsService.clearCache();
  }

  private static AIMessagingDataService.UsageDelta delta(
    World world,
    Integer messages,
    Decimal inputTokens,
    Decimal outputTokens
  ) {
    AIMessagingDataService.UsageDelta usageDelta = new AIMessagingDataService.UsageDelta();
    usageDelta.userId = world.chatUser.Id;
    usageDelta.agentId = world.agent.Id;
    usageDelta.modelConfigurationId = world.agent.AIModelConfiguration__c;
    usageDelta.messages = messages;
    usageDelta.inputTokens = inputTokens;
    usageDelta.outputTokens = outputTokens;

    return usageDelta;
  }

  @IsTest
  static void testScenario1() {
    World world = createWorld();
    AIUsageDaily__c earlier = AIAssistTestDataFactory.createAIUsageDailies(
      world.chatUser.Id,
      world.agent.Id,
      null,
      1,
      false
    )[0];
    earlier.MessageCount__c = 7;
    earlier.InputTokens__c = 70;
    insert earlier;

    Test.startTest();
    AIMessagingSelector.OrgUsage beforeStored = AIOrgUsageService.getUsage();
    AIMessagingDataService.addToDailyUsage(delta(world, 1, 20, 10));
    String storedAfterFirst = AIAssistSettings__c.getOrgDefaults()
      .OrgUsageStateJson__c;
    Integer rowsBefore = Limits.getQueryRows();
    AIMessagingSelector.OrgUsage afterFirst = AIOrgUsageService.getUsage();
    Integer rowsReadByGet = Limits.getQueryRows() - rowsBefore;
    AIMessagingDataService.addToDailyUsage(delta(world, 1, 5, 5));
    AIMessagingSelector.OrgUsage afterSecond = AIOrgUsageService.getUsage();
    Test.stopTest();

    Assert.areEqual(7, beforeStored.month.messages, 'Counted from the rows.');
    Assert.isTrue(String.isNotBlank(storedAfterFirst), 'Stored on first use.');
    Assert.areEqual(8, afterFirst.month.messages, 'Seven and this one.');
    Assert.areEqual(100, afterFirst.month.tokens, 'Seventy and thirty.');
    Assert.areEqual(8, afterFirst.today.messages, 'All of it was today.');
    Assert.areEqual(0, rowsReadByGet, 'Reading the totals reads no row.');
    Assert.areEqual(9, afterSecond.month.messages, 'Added to.');
    Assert.areEqual(110, afterSecond.today.tokens, 'Added to.');
  }

  @IsTest
  static void testScenario2() {
    Date today = Datetime.now().dateGmt();
    Date yesterdayOrEarlierThisMonth = today.day() == 1
      ? today
      : today.addDays(-1);

    Test.startTest();
    store(
      '{"day":"' +
        String.valueOf(today.addMonths(-1)) +
        '","dayMessages":5,"dayTokens":50,"monthMessages":500,"monthTokens":5000}'
    );
    AIMessagingSelector.OrgUsage lastMonth = AIOrgUsageService.getUsage();
    store(
      '{"day":"' +
        String.valueOf(yesterdayOrEarlierThisMonth) +
        '","dayMessages":5,"dayTokens":50,"monthMessages":500,"monthTokens":5000}'
    );
    AIMessagingSelector.OrgUsage earlierThisMonth = AIOrgUsageService.getUsage();
    Test.stopTest();

    Assert.areEqual(0, lastMonth.month.messages, 'A new month starts at zero.');
    Assert.areEqual(0, lastMonth.today.tokens, 'And so does the day.');
    Assert.areEqual(
      500,
      earlierThisMonth.month.messages,
      'The month carries on.'
    );
    if (today.day() != 1)
      Assert.areEqual(0, earlierThisMonth.today.messages, 'A new day is zero.');
  }

  @IsTest
  static void testScenario3() {
    World world = createWorld();
    // Rows that say almost nothing was used: if the check read them it would allow the message.
    insert AIAssistTestDataFactory.createAIUsageDailies(
      world.chatUser.Id,
      world.agent.Id,
      null,
      20,
      false
    );
    store(
      '{"day":"' +
        String.valueOf(Datetime.now().dateGmt()) +
        '","dayMessages":900,"dayTokens":90000,"monthMessages":30000,"monthTokens":3000000}'
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_MESSAGES,
      30001
    );
    String refusedCode;

    Test.startTest();
    Integer rowsBefore = Limits.getQueryRows();
    AIUsageLimitService.enforceUsageLimits(world.context, false, 0);
    Integer rowsRead = Limits.getQueryRows() - rowsBefore;
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_MESSAGES,
      30000
    );
    try {
      AIUsageLimitService.enforceUsageLimits(world.context, false, 0);
    } catch (AIMessagingException ex) {
      refusedCode = ex.code;
    }
    Test.stopTest();

    Assert.isTrue(
      rowsRead <= 1,
      'The check reads none of the 20 usage rows (the one row is the count of queued jobs), so it costs the same with 30,000 of them: ' +
      rowsRead
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_PLAN_LIMIT_MESSAGES,
      refusedCode,
      'Refused on the stored total, which the rows alone would not have reached.'
    );
  }

  @IsTest
  static void testScenario4() {
    World world = createWorld();
    Date today = Datetime.now().dateGmt();
    List<AIUsageDaily__c> rows = AIAssistTestDataFactory.createAIUsageDailies(
      world.chatUser.Id,
      world.agent.Id,
      null,
      40,
      false
    );
    Decimal monthMessages = 0;
    for (AIUsageDaily__c row : rows) {
      row.MessageCount__c = 2;
      row.InputTokens__c = 30;
      row.OutputTokens__c = 10;
      if (row.UsageDate__c >= today.toStartOfMonth())
        monthMessages += 2;
    }
    insert rows;
    store(
      '{"day":"' +
        String.valueOf(today) +
        '","dayMessages":999,"dayTokens":999,"monthMessages":999,"monthTokens":999}'
    );

    Test.startTest();
    Database.executeBatch(new AIOrgUsageTotalsBatch(), 200);
    Test.stopTest();

    AIAssistSettingsService.clearCache();
    AIMessagingSelector.OrgUsage counted = AIOrgUsageService.getUsage();
    Assert.areEqual(2, counted.today.messages, 'Today\'s row only.');
    Assert.areEqual(40, counted.today.tokens, 'Input and output.');
    Assert.areEqual(
      monthMessages,
      counted.month.messages,
      'Every row of this month and none of last month.'
    );
    Assert.areEqual(monthMessages * 20, counted.month.tokens, 'Its tokens.');
  }

  @IsTest
  static void testScenario5() {
    World world = createWorld();

    Test.startTest();
    store('{ not json');
    AIMessagingSelector.OrgUsage malformed = AIOrgUsageService.getUsage();
    AIOrgUsageService.add(null);
    String afterNull = AIAssistSettings__c.getOrgDefaults()
      .OrgUsageStateJson__c;
    AIOrgUsageService.add(delta(world, 1, 1, 1));
    Test.stopTest();

    Assert.areEqual(
      0,
      malformed.month.messages,
      'Counted from the rows: none.'
    );
    Assert.areEqual('{ not json', afterNull, 'A null write changes nothing.');
    Assert.isTrue(
      AIAssistSettings__c.getOrgDefaults()
        .OrgUsageStateJson__c.startsWith('{"'),
      'The next write stores a proper value.'
    );
  }
}
