/*
Class Name: AIOrgUsageServiceTest

=================================================================
=================================================================

Description: Testing utility for AIOrgUsageService and AIOrgUsageTotalsBatch: the organisation's usage totals, and the limit check that reads them. A test cannot insert 30,000 usage rows (10,000 rows of DML per transaction), so the scale scenario stores closed days standing for that many and asserts the check reads today's usage row alone, which is what makes it independent of how many earlier rows there are.

=================================================================
=================================================================
Applicable Classes:

AIOrgUsageService, AIOrgUsageTotalsBatch, AIUsageLimitService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIOrgUsageServiceTest {
  // testScenario1: With nothing stored the month is counted from the usage rows; a second read in the transaction reads no row, and a usage write in the transaction is counted by the next read without the settings being written.
  // testScenario2: Stored closed days are added to the rows of the days since; a stored value for an earlier month or a later day is ignored and the month is counted from the rows.
  // testScenario3: The limit check adds the stored closed days to today's rows alone: with closed days standing for 30,000 rows it refuses at the plan cap and reads none of the earlier rows.
  // testScenario4: The batch stores the month's closed days exactly, and a read adds today to them.
  // testScenario5: A malformed stored value is treated as never stored.
  // testScenario6: With a cache the totals are counted once and then read from it, for sixty seconds; storing new closed days clears it, and a cache that fails just means counting.

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
    AIOrgUsageService.forgetForTransaction();
  }

  private static String closedDays(
    Date since,
    Integer messages,
    Integer tokens
  ) {
    return '{"since":"' +
      String.valueOf(since) +
      '","messages":' +
      messages +
      ',"tokens":' +
      tokens +
      '}';
  }

  // Usage rows for today and the days before it, each with two messages and forty tokens.
  private static List<AIUsageDaily__c> insertRows(World world, Integer days) {
    List<AIUsageDaily__c> rows = AIAssistTestDataFactory.createAIUsageDailies(
      world.chatUser.Id,
      world.agent.Id,
      null,
      days,
      false
    );
    for (AIUsageDaily__c row : rows) {
      row.MessageCount__c = 2;
      row.InputTokens__c = 30;
      row.OutputTokens__c = 10;
    }
    insert rows;

    return rows;
  }

  private static Decimal messagesSince(List<AIUsageDaily__c> rows, Date since) {
    Decimal messages = 0;
    for (AIUsageDaily__c row : rows) {
      if (row.UsageDate__c >= since)
        messages += row.MessageCount__c;
    }

    return messages;
  }

  // Stands in for the org cache partition, which an org may or may not have.
  private class MapCache implements AISchemaHelper.ICache {
    Map<String, String> values = new Map<String, String>();
    Integer lastTtlSeconds;
    Boolean isFailing = false;

    public String get(String key) {
      if (isFailing)
        throw new Cache.Org.OrgCacheException('Cache is down');
      return values.get(key);
    }

    public void put(String key, String value, Integer ttlSeconds) {
      if (isFailing)
        throw new Cache.Org.OrgCacheException('Cache is down');
      values.put(key, value);
      lastTtlSeconds = ttlSeconds;
    }

    public void clear(String key) {
      values.remove(key);
    }
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
    Date today = AIAssistGlobalUtility.getOrgToday();
    List<AIUsageDaily__c> rows = insertRows(world, 3);
    Decimal monthMessages = messagesSince(rows, today.toStartOfMonth());

    Test.startTest();
    AIMessagingSelector.OrgUsage counted = AIOrgUsageService.getUsage();
    counted.month.messages = 999; // A caller changing its copy changes nobody else's.
    Integer rowsBefore = Limits.getQueryRows();
    AIMessagingSelector.OrgUsage readAgain = AIOrgUsageService.getUsage();
    Integer rowsReadAgain = Limits.getQueryRows() - rowsBefore;
    AIMessagingDataService.addToDailyUsage(delta(world, 1, 20, 10));
    AIMessagingSelector.OrgUsage afterWrite = AIOrgUsageService.getUsage();
    Test.stopTest();

    Assert.areEqual(monthMessages, readAgain.month.messages, 'From the rows.');
    Assert.areEqual(2, readAgain.today.messages, 'Today\'s row.');
    Assert.areEqual(40, readAgain.today.tokens, 'Input and output.');
    Assert.areEqual(0, rowsReadAgain, 'Counted once in a transaction.');
    Assert.areEqual(3, afterWrite.today.messages, 'This transaction\'s write.');
    Assert.areEqual(70, afterWrite.today.tokens, 'And its tokens.');
    Assert.isTrue(
      String.isBlank(AIAssistSettings__c.getOrgDefaults().OrgUsageStateJson__c),
      'A usage write does not touch the settings.'
    );
  }

  @IsTest
  static void testScenario2() {
    World world = createWorld();
    Date today = AIAssistGlobalUtility.getOrgToday();
    List<AIUsageDaily__c> rows = insertRows(world, 3);
    Decimal monthMessages = messagesSince(rows, today.toStartOfMonth());
    Date yesterdayThisMonth = today.day() == 1 ? today : today.addDays(-1);

    Test.startTest();
    store(closedDays(today, 500, 5000));
    AIMessagingSelector.OrgUsage closedToYesterday = AIOrgUsageService.getUsage();
    store(closedDays(yesterdayThisMonth, 500, 5000));
    AIMessagingSelector.OrgUsage closedEarlier = AIOrgUsageService.getUsage();
    store(closedDays(today.addMonths(-1), 500, 5000));
    AIMessagingSelector.OrgUsage lastMonth = AIOrgUsageService.getUsage();
    store(closedDays(today.addDays(1), 500, 5000));
    AIMessagingSelector.OrgUsage tomorrow = AIOrgUsageService.getUsage();
    Test.stopTest();

    Assert.areEqual(502, closedToYesterday.month.messages, 'And today\'s row.');
    Assert.areEqual(5040, closedToYesterday.month.tokens, 'And its tokens.');
    Assert.areEqual(2, closedToYesterday.today.messages, 'Today on its own.');
    Assert.areEqual(
      500 + messagesSince(rows, yesterdayThisMonth),
      closedEarlier.month.messages,
      'Every day since the closed days is counted from its rows.'
    );
    Assert.areEqual(
      monthMessages,
      lastMonth.month.messages,
      'Closed days of a month that has passed say nothing about this one.'
    );
    Assert.areEqual(
      monthMessages,
      tomorrow.month.messages,
      'Nor do closed days up to a day still to come.'
    );
  }

  @IsTest
  static void testScenario3() {
    World world = createWorld();
    // Rows that say almost nothing was used: twenty days of them, of which the check may read today's alone.
    insertRows(world, 20);
    store(closedDays(AIAssistGlobalUtility.getOrgToday(), 29998, 3000000));
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
      rowsRead <= 2,
      'The check reads today\'s usage row and none of the other 19 (the other row is the count of queued jobs), so it costs the same with 30,000 of them: ' +
      rowsRead
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_PLAN_LIMIT_MESSAGES,
      refusedCode,
      'Refused on the closed days and today together, which the rows alone would not have reached.'
    );
  }

  @IsTest
  static void testScenario4() {
    World world = createWorld();
    Date today = AIAssistGlobalUtility.getOrgToday();
    List<AIUsageDaily__c> rows = insertRows(world, 40);
    Decimal monthMessages = messagesSince(rows, today.toStartOfMonth());
    store(closedDays(today, 999, 999));

    Test.startTest();
    Database.executeBatch(new AIOrgUsageTotalsBatch(), 200);
    Test.stopTest();

    AIAssistSettingsService.clearCache();
    AIOrgUsageService.forgetForTransaction();
    Map<String, Object> stored = (Map<String, Object>) JSON.deserializeUntyped(
      AIAssistSettings__c.getOrgDefaults().OrgUsageStateJson__c
    );
    AIMessagingSelector.OrgUsage counted = AIOrgUsageService.getUsage();
    Assert.areEqual(String.valueOf(today), stored.get('since'), 'Up to today.');
    Assert.areEqual(
      monthMessages - 2,
      stored.get('messages'),
      'Every row of this month but today\'s, and none of last month.'
    );
    Assert.areEqual(
      (monthMessages - 2) * 20,
      stored.get('tokens'),
      'Its tokens.'
    );
    Assert.areEqual(2, counted.today.messages, 'Today\'s row only.');
    Assert.areEqual(40, counted.today.tokens, 'Input and output.');
    Assert.areEqual(
      monthMessages,
      counted.month.messages,
      'The closed days and today.'
    );
    Assert.areEqual(monthMessages * 20, counted.month.tokens, 'Its tokens.');
  }

  @IsTest
  static void testScenario5() {
    World world = createWorld();
    insertRows(world, 1);

    Test.startTest();
    store('{ not json');
    AIMessagingSelector.OrgUsage malformed = AIOrgUsageService.getUsage();
    store('{"since":"not a day","messages":500,"tokens":5000}');
    AIMessagingSelector.OrgUsage badDay = AIOrgUsageService.getUsage();
    store('{"day":"2026-01-01","monthMessages":500}');
    AIMessagingSelector.OrgUsage otherShape = AIOrgUsageService.getUsage();
    Test.stopTest();

    Assert.areEqual(2, malformed.month.messages, 'Counted from the rows.');
    Assert.areEqual(2, badDay.month.messages, 'Counted from the rows.');
    Assert.areEqual(2, otherShape.month.messages, 'Counted from the rows.');
  }

  @IsTest
  static void testScenario6() {
    World world = createWorld();
    Date today = AIAssistGlobalUtility.getOrgToday();
    List<AIUsageDaily__c> rows = insertRows(world, 1);
    MapCache orgCache = new MapCache();
    AIOrgUsageService.persistentCache = orgCache;

    Test.startTest();
    AIMessagingSelector.OrgUsage counted = AIOrgUsageService.getUsage();
    rows[0].MessageCount__c = 9;
    update rows;
    AIOrgUsageService.forgetForTransaction(); // As another transaction would start.
    Integer rowsBefore = Limits.getQueryRows();
    AIMessagingSelector.OrgUsage fromCache = AIOrgUsageService.getUsage();
    Integer rowsReadFromCache = Limits.getQueryRows() - rowsBefore;
    AIOrgUsageService.replace(today, new AIMessagingSelector.UsageTotals());
    AIMessagingSelector.OrgUsage afterReplace = AIOrgUsageService.getUsage();
    orgCache.isFailing = true;
    AIOrgUsageService.forgetForTransaction();
    AIMessagingSelector.OrgUsage withoutCache = AIOrgUsageService.getUsage();
    Test.stopTest();

    Assert.areEqual(2, counted.today.messages, 'Counted from the row.');
    Assert.areEqual(
      AIOrgUsageService.USAGE_CACHE_TTL_SECONDS,
      orgCache.lastTtlSeconds,
      'Kept for sixty seconds.'
    );
    Assert.areEqual(2, fromCache.today.messages, 'The cached totals.');
    Assert.areEqual(0, rowsReadFromCache, 'No row is read while cached.');
    Assert.areEqual(
      9,
      afterReplace.today.messages,
      'New closed days clear it.'
    );
    Assert.areEqual(9, withoutCache.today.messages, 'A failing cache counts.');
  }
}
