/*
Class Name: AIOrgUsageService

=================================================================
=================================================================

Description: The organisation's running usage totals for the current day and the current month:
messages and tokens. They are kept in AIAssistSettings__c.OrgUsageStateJson__c so that the limit check
on every send (AIUsageLimitService) reads one value instead of adding up every AIUsageDaily__c row, which
in a busy org is tens of thousands of rows and past the query row limit.

Kept current two ways:
[1] Every write to a usage row (AIMessagingDataService.addToDailyUsage, in the job that ran the turn or
    its finalizer) adds the same amounts here, under a lock on the settings row.
[2] The maintenance job recalculates the totals exactly from the usage rows (AIOrgUsageTotalsBatch) and
    replaces what is stored, which corrects anything [1] missed.

A total for a day or month that has passed counts as zero: the day and month it belongs to are stored
with it. Until the totals have been stored once (a new install, or no settings row), they are read from
the usage rows the old way, so a limit is never skipped.

"Today" is the day in the org's time zone, as on the usage rows. Nothing here throws: usage bookkeeping must never fail the
turn it describes.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public inherited sharing class AIOrgUsageService {
  // What is stored. Short names because the field holds 255 characters.
  @TestVisible
  private class State {
    String day; // yyyy-MM-dd, in the org's time zone
    Decimal dayMessages = 0;
    Decimal dayTokens = 0;
    Decimal monthMessages = 0;
    Decimal monthTokens = 0;
  }

  // The totals for today and this month. Reads no usage row once the totals have been stored.
  public static AIMessagingSelector.OrgUsage getUsage() {
    Date today = AIAssistGlobalUtility.getOrgToday();
    State state = parse(
      AIAssistSettingsService.getSettings().OrgUsageStateJson__c
    );

    if (state == null)
      return AIMessagingSelector.getOrganisationUsage(today);

    return toUsage(rollForward(state, today));
  }

  // Adds one write to a usage row to the totals. The settings row is locked so two turns ending together both count. Never throws.
  public static void add(AIMessagingDataService.UsageDelta usageDelta) {
    try {
      if (usageDelta == null)
        return;

      Date today = AIAssistGlobalUtility.getOrgToday();
      List<AIAssistSettings__c> settingsRows = [
        SELECT Id, OrgUsageStateJson__c
        FROM AIAssistSettings__c
        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
        WITH SYSTEM_MODE
        LIMIT 1
        FOR UPDATE
      ];
      if (settingsRows.isEmpty())
        return; // No settings row to keep the totals in: they are read from the usage rows instead.

      State state = parse(settingsRows[0].OrgUsageStateJson__c);
      if (state == null) {
        // First use: start from what the usage rows say, which already includes this write.
        AIMessagingSelector.OrgUsage counted = AIMessagingSelector.getOrganisationUsage(
          today
        );
        save(
          settingsRows[0].Id,
          today,
          counted.today.messages,
          counted.today.tokens,
          counted.month.messages,
          counted.month.tokens
        );
        return;
      }

      state = rollForward(state, today);
      Decimal tokens =
        (usageDelta.inputTokens == null ? 0 : usageDelta.inputTokens) +
        (usageDelta.outputTokens == null ? 0 : usageDelta.outputTokens);
      Integer messages = usageDelta.messages == null ? 0 : usageDelta.messages;
      save(
        settingsRows[0].Id,
        today,
        state.dayMessages + messages,
        state.dayTokens + tokens,
        state.monthMessages + messages,
        state.monthTokens + tokens
      );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIOrgUsageService',
        'add'
      );
    }
  }

  // Replaces the stored totals with ones counted exactly from the usage rows (AIOrgUsageTotalsBatch). Never throws.
  public static void replace(
    Date countedOn,
    AIMessagingSelector.OrgUsage counted
  ) {
    try {
      List<AIAssistSettings__c> settingsRows = [
        SELECT Id
        FROM AIAssistSettings__c
        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
        WITH SYSTEM_MODE
        LIMIT 1
        FOR UPDATE
      ];
      if (settingsRows.isEmpty())
        return;

      save(
        settingsRows[0].Id,
        countedOn,
        counted.today.messages,
        counted.today.tokens,
        counted.month.messages,
        counted.month.tokens
      );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIOrgUsageService',
        'replace'
      );
    }
  }

  private static void save(
    Id settingsId,
    Date day,
    Decimal dayMessages,
    Decimal dayTokens,
    Decimal monthMessages,
    Decimal monthTokens
  ) {
    State state = new State();
    state.day = String.valueOf(day);
    state.dayMessages = dayMessages;
    state.dayTokens = dayTokens;
    state.monthMessages = monthMessages;
    state.monthTokens = monthTokens;

    Database.update(
      new AIAssistSettings__c(
        Id = settingsId,
        OrgUsageStateJson__c = JSON.serialize(state)
      ),
      true,
      AccessLevel.SYSTEM_MODE
    );
    AIAssistSettingsService.clearCache();
  }

  // Null for a blank or malformed value: the totals have never been stored.
  private static State parse(String stored) {
    if (String.isBlank(stored))
      return null;

    try {
      State state = (State) JSON.deserialize(stored, State.class);
      return state == null || String.isBlank(state.day) ? null : state;
    } catch (Exception malformed) {
      return null;
    }
  }

  // A stored day that has passed leaves nothing for today, and a stored month that has passed leaves nothing for this month.
  private static State rollForward(State state, Date today) {
    Date storedDay = Date.valueOf(state.day);

    if (storedDay != today) {
      state.dayMessages = 0;
      state.dayTokens = 0;
    }
    if (storedDay.toStartOfMonth() != today.toStartOfMonth()) {
      state.monthMessages = 0;
      state.monthTokens = 0;
    }
    state.day = String.valueOf(today);

    return state;
  }

  private static AIMessagingSelector.OrgUsage toUsage(State state) {
    AIMessagingSelector.OrgUsage orgUsage = new AIMessagingSelector.OrgUsage();
    orgUsage.today.messages = state.dayMessages;
    orgUsage.today.tokens = state.dayTokens;
    orgUsage.month.messages = state.monthMessages;
    orgUsage.month.tokens = state.monthTokens;

    return orgUsage;
  }
}
