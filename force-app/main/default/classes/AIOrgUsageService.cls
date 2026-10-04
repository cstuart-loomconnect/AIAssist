/*
Class Name: AIOrgUsageService

=================================================================
=================================================================

Description: The organisation's usage totals for the current day and the current month: messages and
tokens. The limit check on every send (AIUsageLimitService) reads them from here.

A SUM over AIUsageDaily__c counts every row it adds up against the query row limit, so the month is never
added up on a send. The total has two parts:
[1] The month's closed days (every day before today), counted exactly by the maintenance job
    (AIOrgUsageTotalsBatch) and stored in AIAssistSettings__c.OrgUsageStateJson__c with the day they
    were counted up to. Written once a night, never by a turn.
[2] The days since then, normally today alone, added up from the usage rows by one grouped query.

The result is kept for USAGE_CACHE_TTL_SECONDS in the org cache partition the subscriber may have created
(AISchemaHelper.PARTITION_NAME), and for the rest of the transaction in any case. Nothing is written or
locked when a turn ends, so turns ending together do not wait for each other; the totals can be up to
that many seconds behind, which a plan limit can bear.

Until the maintenance job has stored [1] (a new install, no settings row, a value that cannot be read,
or one for a month that has passed), [2] covers the whole month so far, so a limit is never skipped.

"Today" is the day in the org's time zone, as on the usage rows.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          No write or lock per turn: closed days are stored nightly, today is counted from the usage rows and cached.
*/

public inherited sharing class AIOrgUsageService {
  public static final Integer USAGE_CACHE_TTL_SECONDS = 60;
  private static final String CACHE_KEY_PREFIX = 'orgusage'; // Cache keys must be alphanumeric.

  // What is stored: this month's totals for the days before "since". Short names because the field holds 255 characters.
  @TestVisible
  private class State {
    String since; // yyyy-MM-dd, in the org's time zone: the first day that is not in the totals.
    Decimal messages = 0;
    Decimal tokens = 0;
  }

  // Not in a test unless the test supplies one: an org's own partition would carry totals from one test into the next.
  @TestVisible
  private static AISchemaHelper.ICache persistentCache = Test.isRunningTest()
    ? null
    : new AISchemaHelper.OrgPartitionCache();
  private static AIMessagingSelector.OrgUsage transactionUsage;
  private static Date transactionUsageDay;

  // The totals for today and this month, at most USAGE_CACHE_TTL_SECONDS old.
  public static AIMessagingSelector.OrgUsage getUsage() {
    Date today = AIAssistGlobalUtility.getOrgToday();

    if (transactionUsage == null || transactionUsageDay != today) {
      String cacheKey = cacheKey(today);
      AIMessagingSelector.OrgUsage orgUsage = readCached(cacheKey);

      if (orgUsage == null) {
        orgUsage = count(today);
        writeCached(cacheKey, orgUsage);
      }

      transactionUsage = orgUsage;
      transactionUsageDay = today;
    }

    return copy(transactionUsage);
  }

  // After this transaction has written usage, its next read counts again instead of using its own earlier answer.
  public static void forgetForTransaction() {
    transactionUsage = null;
    transactionUsageDay = null;
  }

  // Stores this month's totals for the days before countedBefore, counted exactly from the usage rows (AIOrgUsageTotalsBatch). Never throws.
  public static void replace(
    Date countedBefore,
    AIMessagingSelector.UsageTotals closedDays
  ) {
    try {
      List<AIAssistSettings__c> settingsRows = [
        SELECT Id
        FROM AIAssistSettings__c
        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (settingsRows.isEmpty())
        return; // No settings row to keep them in: the whole month is counted from the usage rows instead.

      State state = new State();
      state.since = String.valueOf(countedBefore);
      state.messages = closedDays.messages;
      state.tokens = closedDays.tokens;

      Database.update(
        new AIAssistSettings__c(
          Id = settingsRows[0].Id,
          OrgUsageStateJson__c = JSON.serialize(state)
        ),
        true,
        AccessLevel.SYSTEM_MODE
      );
      AIAssistSettingsService.clearCache();
      forgetForTransaction();
      clearCached(cacheKey(AIAssistGlobalUtility.getOrgToday()));
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIOrgUsageService',
        'replace'
      );
    }
  }

  // The stored closed days, when they are of this month, and the usage rows of every day since.
  private static AIMessagingSelector.OrgUsage count(Date today) {
    Date monthStart = today.toStartOfMonth();
    Date countFrom = monthStart;
    State state = parse(
      AIAssistSettingsService.getSettings().OrgUsageStateJson__c
    );

    if (state != null) {
      Date storedSince = Date.valueOf(state.since);
      // A value for a month that has passed, or for a day still to come, says nothing about this month.
      if (storedSince >= monthStart && storedSince <= today)
        countFrom = storedSince;
      else
        state = null;
    }

    AIMessagingSelector.OrgUsage orgUsage = AIMessagingSelector.getOrganisationUsage(
      today,
      countFrom
    );
    if (state != null) {
      orgUsage.month.messages += state.messages == null ? 0 : state.messages;
      orgUsage.month.tokens += state.tokens == null ? 0 : state.tokens;
    }

    return orgUsage;
  }

  // Null for a blank or malformed value: the closed days have never been stored.
  private static State parse(String stored) {
    if (String.isBlank(stored))
      return null;

    try {
      State state = (State) JSON.deserialize(stored, State.class);
      if (state == null || String.isBlank(state.since))
        return null;

      Date.valueOf(state.since);
      return state;
    } catch (Exception malformed) {
      return null;
    }
  }

  private static String cacheKey(Date day) {
    return CACHE_KEY_PREFIX +
      Datetime.newInstanceGmt(day.year(), day.month(), day.day())
        .formatGmt('yyyyMMdd');
  }

  // A cache that is missing, full or unreadable just means counting.
  private static AIMessagingSelector.OrgUsage readCached(String cacheKey) {
    try {
      String cachedJson = persistentCache == null
        ? null
        : persistentCache.get(cacheKey);

      return String.isBlank(cachedJson)
        ? null
        : (AIMessagingSelector.OrgUsage) JSON.deserialize(
            cachedJson,
            AIMessagingSelector.OrgUsage.class
          );
    } catch (Exception cacheReadFailure) {
      return null;
    }
  }

  private static void writeCached(
    String cacheKey,
    AIMessagingSelector.OrgUsage orgUsage
  ) {
    try {
      if (persistentCache != null)
        persistentCache.put(
          cacheKey,
          JSON.serialize(orgUsage),
          USAGE_CACHE_TTL_SECONDS
        );
    } catch (Exception cacheWriteFailure) {
      persistentCache = null; // No capacity or no partition: once per transaction instead.
    }
  }

  private static void clearCached(String cacheKey) {
    try {
      if (persistentCache != null)
        persistentCache.clear(cacheKey);
    } catch (Exception cacheClearFailure) {
      persistentCache = null;
    }
  }

  // A caller gets totals of its own, so changing them cannot change what the next caller reads.
  private static AIMessagingSelector.OrgUsage copy(
    AIMessagingSelector.OrgUsage orgUsage
  ) {
    AIMessagingSelector.OrgUsage copied = new AIMessagingSelector.OrgUsage();
    copied.month.messages = orgUsage.month.messages;
    copied.month.tokens = orgUsage.month.tokens;
    copied.today.messages = orgUsage.today.messages;
    copied.today.tokens = orgUsage.today.tokens;

    return copied;
  }
}
