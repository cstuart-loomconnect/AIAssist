/*
Class Name: AIOrgLimitMonitor

=================================================================
=================================================================

Description: Keeps AI Assist from using up the limits it shares with the subscriber's own processes. It reads
OrgLimits.getMap() at most once every few minutes and gives each feature a mode:
- Normal: nothing is held back.
- Degraded: live push updates stop (the chat window polls instead) and only errors are logged.
- Paused: new chat messages are refused with a plain message, and resume by themselves.

Features and the limits each depends on (AIAssistApplicationConstants.ORG_LIMITS_FOR_*):
- Chat: asynchronous Apex and data storage. Not API requests: a chat turn is Apex and a callout, and uses none.
- Events: platform event allowances (the "reply is ready" and progress events).
- Logging: the event allowances and data storage, because every log entry is an event.

An administrator sets the thresholds in AIAssistSettings__c. Each feature has its own Degraded and Paused
percentage ({Feature}DegradedPercent__c, {Feature}PausedPercent__c); a blank one uses the org-wide
OrgLimit* field, and that falls back to 70 and 85. Whatever is set, a feature pauses at 95 percent of any
limit. A feature returns to a milder mode only once usage is below the threshold by the resume margin (5
points by default), so it does not flip back and forth at the line.

Two readings decide a mode, and the stricter wins:
- Org headroom: how full the org's limit is, from every process in the org.
- AI Assist's share: how much of the limit AI Assist itself used ({Feature}AppSharePercent__c, or
  OrgLimitMaxSharePercent__c when blank). Reaching the share pauses the feature even when the org has
  room, so AI Assist cannot crowd out the subscriber's own work. StorageBudgetPercent__c is the share of
  data storage; reaching it pauses Chat and Logging.
AI Assist's own usage (its footprint) is measured only by the maintenance job and by refreshIfStale, at
most hourly, and kept in AppUsageStateJson__c: asynchronous jobs in the last day (AsyncApexJob, by
namespace), events in the last day (the day's messages plus Platform Log entries) and the storage its
records take (records times 2 KB).

How it stays cheap and safe:
- The last reading is kept in AIAssistSettings__c.OrgLimitStateJson__c, which the platform caches, so most
  calls read nothing. When it is older than the check interval a call recomputes in memory and keeps the
  answer for the rest of the transaction. Nothing is written by a call that only asks for a mode.
- refreshIfStale is the one method that writes. It is called where DML is already safe (after a turn has
  finished, and from the maintenance job), never before a callout, because uncommitted work blocks
  callouts.
- Administrators are told once when a mode changes (a custom notification, or an email if the notification
  type is missing) and a Platform Log entry is written. Further changes inside the minimum gap are logged
  but not announced again, unless a feature pauses.
- If reading the limits fails, the last known state is used, or Normal when there is none: the monitor
  must never be the reason chat stops. The failure is logged.

Events are optional (AIAssistSettings__c.IsEventNotificationEnabled__c, off by default): the chat window
polls, which uses no event allowance. An org with headroom can turn events on, and they are switched off
again, with the window falling back to polling, as soon as the Events feature leaves Normal.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Thresholds per feature with the org-wide ones as defaults, a hard floor at 95 percent, and AI Assist's own share of each limit measured and applied.
*/

public inherited sharing class AIOrgLimitMonitor {
  public class FeatureState {
    public String mode = AIAssistApplicationConstants.LIMIT_MODE_NORMAL;
    public Integer percent = 0;
    public Integer appPercent = 0; // AI Assist's own share of the limit behind this feature.
    public String limitName; // The limit that decided the mode; not kept between reads.
  }

  // AI Assist's own usage of the org, as last measured.
  public class Footprint {
    public Long measuredAt;
    public Decimal asyncJobs = 0; // In the last day.
    public Decimal events = 0; // In the last day.
    public Decimal storageMegabytes = 0;
  }

  public class State {
    public Long checkedAt;
    public Map<String, FeatureState> byFeature = new Map<String, FeatureState>();
  }

  // For tests: the people who would be told.
  @TestVisible
  private static Set<Id> getAdminUserIdsForTest() {
    return new Set<Id>(
      AIMessagingSelector.getAdminUserIds(
        AIAssistApplicationConstants.LIMIT_ALERT_MAX_RECIPIENTS
      )
    );
  }

  // What a change of mode looks like, for the log and the administrator's message.
  @TestVisible
  private class Change {
    String feature;
    String fromMode;
    String toMode;
    Integer percent;
    String limitName;
  }

  public class Thresholds {
    public Integer degraded;
    public Integer paused;
    public Integer margin;
    public Integer appShare; // Null: no share budget.
  }

  // The package's objects that hold records, for the storage estimate.
  private static final List<Schema.SObjectType> STORED_OBJECTS = new List<Schema.SObjectType>{
    AIAgent__c.SObjectType,
    AIAgentAssignment__c.SObjectType,
    AIAgentDataSource__c.SObjectType,
    AIAgentObject__c.SObjectType,
    AIAgentViolationRule__c.SObjectType,
    AIAgentWorkflowAction__c.SObjectType,
    AIConversation__c.SObjectType,
    AIConversationMessage__c.SObjectType,
    AIDataDeletionRequest__c.SObjectType,
    AIDataSource__c.SObjectType,
    AIExecutionStep__c.SObjectType,
    AIFeedback__c.SObjectType,
    AIModelConfiguration__c.SObjectType,
    AIPIIFieldMetadata__c.SObjectType,
    AIPIIMapping__c.SObjectType,
    AIPIIMaskingRecord__c.SObjectType,
    AIPIIRegistry__c.SObjectType,
    AIPlatformLog__c.SObjectType,
    AIPromptTemplate__c.SObjectType,
    AITermsAcknowledgment__c.SObjectType,
    AIUsageDaily__c.SObjectType,
    AIUsagePolicy__c.SObjectType,
    AIUsagePolicyAssignment__c.SObjectType,
    AIUserSettings__c.SObjectType,
    AIViolation__c.SObjectType,
    AIViolationRule__c.SObjectType,
    AIWorkflowAction__c.SObjectType
  };

  private static final List<String> FEATURES = new List<String>{
    AIAssistApplicationConstants.LIMIT_FEATURE_CHAT,
    AIAssistApplicationConstants.LIMIT_FEATURE_EVENTS,
    AIAssistApplicationConstants.LIMIT_FEATURE_LOGGING
  };
  private static final List<String> MODES_BY_INDEX = new List<String>{
    AIAssistApplicationConstants.LIMIT_MODE_NORMAL,
    AIAssistApplicationConstants.LIMIT_MODE_DEGRADED,
    AIAssistApplicationConstants.LIMIT_MODE_PAUSED
  };
  private static final String NOTIFICATION_TYPE_NAME = 'AIAssistLimitAlert';

  // Tests cannot change the org's limits: name => {used, maximum}. When set it replaces OrgLimits.getMap().
  @TestVisible
  private static Map<String, List<Decimal>> testLimits;
  @TestVisible
  private static Boolean isTestFailureThrown = false;
  // Tests cannot create jobs or fill storage: when set it replaces the measured footprint.
  @TestVisible
  private static Footprint testFootprint;
  @TestVisible
  private static State transactionState;
  private static Boolean isReading = false;
  @TestVisible
  private static List<String> sentAlertTitles = new List<String>(); // What was sent, for tests; no message is sent twice in a transaction.

  // =============================================================
  // Asking for a mode
  // =============================================================

  public static String getMode(String feature) {
    FeatureState featureState = getState().byFeature.get(feature);

    return featureState == null
      ? AIAssistApplicationConstants.LIMIT_MODE_NORMAL
      : featureState.mode;
  }

  // True when new chat messages must be refused until usage falls.
  public static Boolean isChatPaused() {
    return getMode(AIAssistApplicationConstants.LIMIT_FEATURE_CHAT) ==
      AIAssistApplicationConstants.LIMIT_MODE_PAUSED;
  }

  // True only when an administrator has turned events on and the Events feature is Normal.
  public static Boolean isEventNotificationAllowed() {
    return AIAssistSettingsService.getSettings()
        .IsEventNotificationEnabled__c == true &&
      getMode(AIAssistApplicationConstants.LIMIT_FEATURE_EVENTS) ==
      AIAssistApplicationConstants.LIMIT_MODE_NORMAL;
  }

  // False only while the Events feature is Paused. A violation event tells a subscriber's own automation, so it keeps going through Degraded and does not depend on the chat's event setting; the AIViolation__c record is saved either way.
  public static Boolean isViolationEventAllowed() {
    return getMode(AIAssistApplicationConstants.LIMIT_FEATURE_EVENTS) !=
      AIAssistApplicationConstants.LIMIT_MODE_PAUSED;
  }

  // What the chat window should use to learn a reply is ready.
  public static String getNotificationMode() {
    return isEventNotificationAllowed()
      ? AIAssistApplicationConstants.NOTIFICATION_MODE_EVENTS
      : AIAssistApplicationConstants.NOTIFICATION_MODE_POLLING;
  }

  // True under pressure: only errors are published to the Platform Log, because a log entry is itself an event.
  public static Boolean isErrorOnlyLogging() {
    return getMode(AIAssistApplicationConstants.LIMIT_FEATURE_LOGGING) !=
      AIAssistApplicationConstants.LIMIT_MODE_NORMAL;
  }

  // The reading behind the modes, for a health check page.
  public static State getState() {
    if (transactionState != null)
      return transactionState;

    State storedState = parse(
      AIAssistSettingsService.getSettings().OrgLimitStateJson__c
    );
    if (storedState != null && !isStale(storedState)) {
      transactionState = storedState;
      return transactionState;
    }
    if (isReading)
      return storedState == null ? new State() : storedState; // Reading the limits logged something that asked for a mode.

    isReading = true;
    try {
      if (isTestFailureThrown)
        throw new AIOrgLimitMonitorException(
          'Test exception for AIOrgLimitMonitor.getState'
        );

      transactionState = evaluate(storedState);
    } catch (Exception readFailure) {
      AIPlatformLogManager.logException(
        readFailure,
        'AIOrgLimitMonitor',
        'getState'
      );
      transactionState = storedState == null ? new State() : storedState;
    } finally {
      isReading = false;
    }

    return transactionState;
  }

  // =============================================================
  // Keeping the reading and telling administrators
  // =============================================================

  public class AIOrgLimitMonitorException extends Exception {
  }

  // Takes a fresh reading when the last one is older than the check interval, keeps it, and announces a change of mode. Call it only where DML is safe. A failure is logged and never thrown.
  public static void refreshIfStale() {
    try {
      AIAssistSettings__c settings = AIAssistSettingsService.getSettings();
      State storedState = parse(settings.OrgLimitStateJson__c);
      if (storedState != null && !isStale(storedState))
        return;
      if (isTestFailureThrown)
        throw new AIOrgLimitMonitorException(
          'Test exception for AIOrgLimitMonitor.refreshIfStale'
        );

      // AI Assist's own usage is measured here and nowhere else, and only when the last measurement is old: it costs a count query per object.
      Footprint storedFootprint = getFootprint();
      Boolean isFootprintDue =
        settings.Id != null &&
        testFootprint == null &&
        (storedFootprint.measuredAt == null ||
        System.currentTimeMillis() - storedFootprint.measuredAt >=
        AIAssistApplicationConstants.APP_FOOTPRINT_REFRESH_MINUTES * 60000L);
      if (isFootprintDue)
        transactionFootprint = measureFootprint();

      State freshState = evaluate(storedState);
      transactionState = freshState;

      if (settings.Id == null)
        return; // No settings row to keep the reading in: it is recomputed on each read instead.

      List<Change> changes = findChanges(storedState, freshState);
      Boolean shouldAlert = !changes.isEmpty() && isAlertDue(settings, changes);

      AIAssistSettings__c stateUpdate = new AIAssistSettings__c(
        Id = settings.Id,
        OrgLimitStateJson__c = serialize(freshState)
      );
      if (isFootprintDue)
        stateUpdate.AppUsageStateJson__c = JSON.serialize(transactionFootprint);
      if (shouldAlert)
        stateUpdate.OrgLimitAlertSentAt__c = System.now();
      Database.update(stateUpdate, true, AccessLevel.SYSTEM_MODE);
      AIAssistSettingsService.clearCache();

      for (Change change : changes)
        logChange(change);
      if (shouldAlert)
        notifyAdministrators(changes);
    } catch (Exception refreshFailure) {
      AIPlatformLogManager.logException(
        refreshFailure,
        'AIOrgLimitMonitor',
        'refreshIfStale'
      );
    }
  }

  // =============================================================
  // The decision
  // =============================================================

  // Reads the limits and decides each feature's mode, starting from where it was so a switch back waits for the margin.
  @TestVisible
  private static State evaluate(State previousState) {
    Map<String, List<Decimal>> readings = readLimits();
    Footprint footprint = getFootprint();
    State freshState = new State();
    freshState.checkedAt = System.currentTimeMillis();

    // AI Assist's own share of the three limits its features lean on. Events are compared with a day of the hourly allowance, because the footprint counts a day.
    Decimal asyncShare = shareOf(
      footprint.asyncJobs,
      readings.get(AIAssistApplicationConstants.ORG_LIMIT_ASYNC_APEX),
      1
    );
    Decimal eventShare = shareOf(
      footprint.events,
      readings.get(AIAssistApplicationConstants.ORG_LIMIT_HOURLY_EVENTS),
      24
    );
    Decimal storageShare = shareOf(
      footprint.storageMegabytes,
      readings.get(AIAssistApplicationConstants.ORG_LIMIT_DATA_STORAGE),
      1
    );
    Integer storageBudget = inRange(
      AIAssistSettingsService.getSettings().StorageBudgetPercent__c,
      AIAssistApplicationConstants.LIMIT_MINIMUM_SHARE_PERCENT,
      100,
      null
    );

    for (String feature : FEATURES) {
      Thresholds thresholds = getThresholds(feature);
      FeatureState featureState = new FeatureState();
      Decimal highestPercent = 0;

      for (String limitName : getLimitNames(feature)) {
        List<Decimal> reading = readings.get(limitName);
        if (reading == null || reading[1] == null || reading[1] <= 0)
          continue;

        Decimal percent = 100 * reading[0] / reading[1];
        if (percent > highestPercent) {
          highestPercent = percent;
          featureState.limitName = limitName;
        }
      }

      FeatureState previousFeature = previousState == null
        ? null
        : previousState.byFeature.get(feature);
      featureState.percent = highestPercent.round(System.RoundingMode.DOWN)
        .intValue();
      featureState.mode = decideMode(
        highestPercent,
        previousFeature == null
          ? AIAssistApplicationConstants.LIMIT_MODE_NORMAL
          : previousFeature.mode,
        thresholds
      );

      // The stricter of the two readings: the org may have headroom while AI Assist has used its share.
      Boolean isChat =
        feature == AIAssistApplicationConstants.LIMIT_FEATURE_CHAT;
      Decimal appShare = isChat ? asyncShare : eventShare;
      featureState.appPercent = appShare.round(System.RoundingMode.DOWN)
        .intValue();
      if (thresholds.appShare != null && appShare >= thresholds.appShare) {
        featureState.mode = AIAssistApplicationConstants.LIMIT_MODE_PAUSED;
        featureState.limitName =
          'AI Assist share of ' +
          (isChat
            ? AIAssistApplicationConstants.ORG_LIMIT_ASYNC_APEX
            : AIAssistApplicationConstants.ORG_LIMIT_HOURLY_EVENTS);
      }
      if (
        storageBudget != null &&
        storageShare >= storageBudget &&
        feature != AIAssistApplicationConstants.LIMIT_FEATURE_EVENTS
      ) {
        featureState.mode = AIAssistApplicationConstants.LIMIT_MODE_PAUSED;
        featureState.appPercent = storageShare.round(System.RoundingMode.DOWN)
          .intValue();
        featureState.limitName =
          'AI Assist share of ' +
          AIAssistApplicationConstants.ORG_LIMIT_DATA_STORAGE;
      }

      freshState.byFeature.put(feature, featureState);
    }

    return freshState;
  }

  @TestVisible
  private static String decideMode(
    Decimal percent,
    String previousMode,
    Thresholds thresholds
  ) {
    if (percent >= thresholds.paused)
      return AIAssistApplicationConstants.LIMIT_MODE_PAUSED;
    if (
      previousMode == AIAssistApplicationConstants.LIMIT_MODE_PAUSED &&
      percent >= thresholds.paused - thresholds.margin
    )
      return AIAssistApplicationConstants.LIMIT_MODE_PAUSED;
    if (percent >= thresholds.degraded)
      return AIAssistApplicationConstants.LIMIT_MODE_DEGRADED;
    if (
      previousMode != AIAssistApplicationConstants.LIMIT_MODE_NORMAL &&
      percent >= thresholds.degraded - thresholds.margin
    )
      return AIAssistApplicationConstants.LIMIT_MODE_DEGRADED;

    return AIAssistApplicationConstants.LIMIT_MODE_NORMAL;
  }

  // The org-wide thresholds, as for a feature with no fields of its own.
  public static Thresholds getThresholds() {
    return getThresholds(null);
  }

  // A feature's thresholds made safe: a blank, silly or contradictory value never switches AI Assist off or leaves it unprotected. The feature's own fields come first, then the org-wide OrgLimit* fields, then the defaults. The org-wide maximum share still replaces the paused threshold when it is lower, and nothing pauses later than the hard floor.
  public static Thresholds getThresholds(String feature) {
    AIAssistSettings__c settings = AIAssistSettingsService.getSettings();
    Thresholds thresholds = new Thresholds();
    Boolean hasOwnFields = FEATURES.contains(feature);

    thresholds.paused = inRange(
      hasOwnFields
        ? (Decimal) settings.get(feature + 'PausedPercent__c')
        : null,
      2,
      100,
      inRange(
        settings.OrgLimitPausedPercent__c,
        2,
        100,
        AIAssistApplicationConstants.DEFAULT_LIMIT_PAUSED_PERCENT
      )
    );
    Integer maxShare = inRange(
      settings.OrgLimitMaxSharePercent__c,
      2,
      100,
      null
    );
    if (maxShare != null && maxShare < thresholds.paused)
      thresholds.paused = maxShare;
    thresholds.paused = Math.min(
      thresholds.paused,
      AIAssistApplicationConstants.LIMIT_HARD_FLOOR_PAUSED_PERCENT
    );

    thresholds.degraded = inRange(
      hasOwnFields
        ? (Decimal) settings.get(feature + 'DegradedPercent__c')
        : null,
      1,
      99,
      inRange(
        settings.OrgLimitDegradedPercent__c,
        1,
        99,
        AIAssistApplicationConstants.DEFAULT_LIMIT_DEGRADED_PERCENT
      )
    );
    if (thresholds.degraded >= thresholds.paused)
      thresholds.degraded = Math.max(1, thresholds.paused - 1);

    thresholds.margin = inRange(
      settings.OrgLimitResumeMarginPercent__c,
      0,
      50,
      AIAssistApplicationConstants.DEFAULT_LIMIT_RESUME_MARGIN_PERCENT
    );

    thresholds.appShare = inRange(
      hasOwnFields
        ? (Decimal) settings.get(feature + 'AppSharePercent__c')
        : null,
      AIAssistApplicationConstants.LIMIT_MINIMUM_SHARE_PERCENT,
      100,
      inRange(
        settings.OrgLimitMaxSharePercent__c,
        AIAssistApplicationConstants.LIMIT_MINIMUM_SHARE_PERCENT,
        100,
        null
      )
    );

    return thresholds;
  }

  // What is wrong with the limit settings as an administrator entered them, one sentence each, naming the field to fix. Empty when they are sound. The monitor never trusts them (getThresholds); this is for the screens that save them.
  public static List<String> validateSettings(AIAssistSettings__c settings) {
    List<String> problems = new List<String>();
    List<String> groups = new List<String>{ 'OrgLimit' };
    groups.addAll(FEATURES);

    for (String settingGroup : groups) {
      Decimal degraded = (Decimal) settings.get(
        settingGroup + 'DegradedPercent__c'
      );
      Decimal paused = (Decimal) settings.get(
        settingGroup + 'PausedPercent__c'
      );
      Decimal share = (Decimal) settings.get(
        settingGroup == 'OrgLimit'
          ? 'OrgLimitMaxSharePercent__c'
          : settingGroup + 'AppSharePercent__c'
      );

      if (paused != null && (paused < 2 || paused > 100))
        problems.add(
          settingGroup + 'PausedPercent__c must be between 2 and 100.'
        );
      if (degraded != null && degraded < 1)
        problems.add(settingGroup + 'DegradedPercent__c must be 1 or more.');
      if (degraded != null && paused != null && degraded >= paused)
        problems.add(
          settingGroup +
            'DegradedPercent__c must be lower than ' +
            settingGroup +
            'PausedPercent__c.'
        );
      if (
        share != null &&
        (share < AIAssistApplicationConstants.LIMIT_MINIMUM_SHARE_PERCENT ||
        share > 100)
      )
        problems.add(
          (settingGroup == 'OrgLimit'
            ? 'OrgLimitMaxSharePercent__c'
            : settingGroup + 'AppSharePercent__c') +
          ' must be between 5 and 100.'
        );
    }

    if (
      settings.StorageBudgetPercent__c != null &&
      (settings.StorageBudgetPercent__c <
      AIAssistApplicationConstants.LIMIT_MINIMUM_SHARE_PERCENT ||
      settings.StorageBudgetPercent__c > 100)
    )
      problems.add('StorageBudgetPercent__c must be between 5 and 100.');

    return problems;
  }

  // =============================================================
  // AI Assist's own usage
  // =============================================================

  private static Footprint transactionFootprint;

  // The footprint as last measured and stored. Empty (all zero) when it has never been measured. Reads no record.
  public static Footprint getFootprint() {
    if (testFootprint != null)
      return testFootprint;
    if (transactionFootprint != null)
      return transactionFootprint;

    String stored = AIAssistSettingsService.getSettings().AppUsageStateJson__c;
    try {
      Footprint footprint = String.isBlank(stored)
        ? null
        : (Footprint) JSON.deserialize(stored, Footprint.class);
      return footprint == null ? new Footprint() : footprint;
    } catch (Exception malformed) {
      return new Footprint();
    }
  }

  // Counts AI Assist's own jobs, events and records. One count query per object, so it is called only from refreshIfStale.
  @TestVisible
  private static Footprint measureFootprint() {
    Footprint footprint = new Footprint();
    footprint.measuredAt = System.currentTimeMillis();
    Datetime oneDayAgo = System.now().addDays(-1);
    String packageNamespace = AIMessagingSelector.getPackageNamespace();

    // Every job of the package's classes. Outside a namespace the class name prefix keeps the subscriber's own jobs out.
    footprint.asyncJobs = [
      SELECT COUNT()
      FROM AsyncApexJob
      WHERE
        ApexClass.NamespacePrefix = :packageNamespace
        AND ApexClass.Name LIKE 'AI%'
        AND CreatedDate >= :oneDayAgo
      WITH SYSTEM_MODE
    ];

    // Each message can publish a "reply is ready" event and each log entry is published as one.
    footprint.events =
      AIOrgUsageService.getUsage().today.messages +
      [
        SELECT COUNT()
        FROM AIPlatformLog__c
        WHERE CreatedDate >= :oneDayAgo
        WITH SYSTEM_MODE
      ];

    Decimal records = 0;
    for (Schema.SObjectType storedObject : STORED_OBJECTS)
      records += Database.countQuery(
        'SELECT COUNT() FROM ' + storedObject,
        AccessLevel.SYSTEM_MODE
      );
    footprint.storageMegabytes = (records *
      AIAssistApplicationConstants.STORAGE_KILOBYTES_PER_RECORD /
      1024)
      .setScale(4);

    return footprint;
  }

  // Usage as a percentage of a limit reading {used, maximum}, the maximum multiplied to cover the same period as the usage. Zero when the limit is unknown.
  private static Decimal shareOf(
    Decimal used,
    List<Decimal> reading,
    Integer periods
  ) {
    if (
      used == null ||
      reading == null ||
      reading[1] == null ||
      reading[1] <= 0
    )
      return 0;

    return 100 * used / (reading[1] * periods);
  }

  private static Integer inRange(
    Decimal configured,
    Integer lowest,
    Integer highest,
    Integer fallback
  ) {
    if (configured == null || configured < lowest || configured > highest)
      return fallback;

    return configured.intValue();
  }

  private static Set<String> getLimitNames(String feature) {
    if (feature == AIAssistApplicationConstants.LIMIT_FEATURE_CHAT)
      return AIAssistApplicationConstants.ORG_LIMITS_FOR_CHAT;

    Set<String> limitNames = new Set<String>(
      AIAssistApplicationConstants.ORG_LIMITS_FOR_EVENTS
    );
    if (feature == AIAssistApplicationConstants.LIMIT_FEATURE_LOGGING)
      limitNames.add('DataStorageMB'); // Every log entry becomes a record.

    return limitNames;
  }

  private static Map<String, List<Decimal>> readLimits() {
    if (testLimits != null)
      return testLimits;

    Map<String, List<Decimal>> readings = new Map<String, List<Decimal>>();
    Map<String, System.OrgLimit> orgLimits = OrgLimits.getMap();
    for (String limitName : orgLimits.keySet()) {
      System.OrgLimit orgLimit = orgLimits.get(limitName);
      readings.put(
        limitName,
        new List<Decimal>{ orgLimit.getValue(), orgLimit.getLimit() }
      );
    }

    return readings;
  }

  private static Boolean isStale(State state) {
    if (state == null || state.checkedAt == null)
      return true;

    Integer checkMinutes = inRange(
      AIAssistSettingsService.getSettings().OrgLimitCheckMinutes__c,
      1,
      1440,
      AIAssistApplicationConstants.DEFAULT_LIMIT_CHECK_MINUTES
    );

    return System.currentTimeMillis() - state.checkedAt >=
      checkMinutes * 60000L;
  }

  // =============================================================
  // Keeping the state between transactions
  // =============================================================

  // {"t":checkedAtMilliseconds,"c":[modeIndex,percent,appPercent],"e":[...],"g":[...]} for Chat, Events and Logging. Small enough for a 255 character field.
  @TestVisible
  private static String serialize(State state) {
    Map<String, Object> compact = new Map<String, Object>{
      't' => state.checkedAt
    };
    List<String> keys = new List<String>{ 'c', 'e', 'g' };

    for (Integer index = 0; index < FEATURES.size(); index++) {
      FeatureState featureState = state.byFeature.get(FEATURES[index]);
      compact.put(
        keys[index],
        new List<Integer>{
          featureState == null
            ? 0
            : Math.max(0, MODES_BY_INDEX.indexOf(featureState.mode)),
          featureState == null ? 0 : featureState.percent,
          featureState == null ? 0 : featureState.appPercent
        }
      );
    }

    return JSON.serialize(compact);
  }

  @TestVisible
  private static State parse(String serialized) {
    if (String.isBlank(serialized))
      return null;

    try {
      Map<String, Object> compact = (Map<String, Object>) JSON.deserializeUntyped(
        serialized
      );
      State state = new State();
      state.checkedAt = Long.valueOf(String.valueOf(compact.get('t')));
      List<String> keys = new List<String>{ 'c', 'e', 'g' };

      for (Integer index = 0; index < FEATURES.size(); index++) {
        List<Object> values = (List<Object>) compact.get(keys[index]);
        FeatureState featureState = new FeatureState();
        Integer modeIndex = Integer.valueOf(values[0]);
        featureState.mode = modeIndex >= 0 &&
          modeIndex < MODES_BY_INDEX.size()
          ? MODES_BY_INDEX[modeIndex]
          : AIAssistApplicationConstants.LIMIT_MODE_NORMAL;
        featureState.percent = Integer.valueOf(values[1]);
        featureState.appPercent = values.size() > 2
          ? Integer.valueOf(values[2])
          : 0;
        state.byFeature.put(FEATURES[index], featureState);
      }

      return state;
    } catch (Exception malformedState) {
      return null; // Treated as never read: the limits are read again.
    }
  }

  // =============================================================
  // Telling people
  // =============================================================

  private static List<Change> findChanges(State before, State after) {
    List<Change> changes = new List<Change>();

    for (String feature : FEATURES) {
      FeatureState beforeFeature = before == null
        ? null
        : before.byFeature.get(feature);
      FeatureState afterFeature = after.byFeature.get(feature);
      String fromMode = beforeFeature == null
        ? AIAssistApplicationConstants.LIMIT_MODE_NORMAL
        : beforeFeature.mode;

      if (afterFeature != null && afterFeature.mode != fromMode) {
        Change change = new Change();
        change.feature = feature;
        change.fromMode = fromMode;
        change.toMode = afterFeature.mode;
        change.percent = afterFeature.percent;
        change.limitName = afterFeature.limitName;
        changes.add(change);
      }
    }

    return changes;
  }

  // Told when nothing has been announced lately, or at once when something pauses.
  private static Boolean isAlertDue(
    AIAssistSettings__c settings,
    List<Change> changes
  ) {
    for (Change change : changes) {
      if (change.toMode == AIAssistApplicationConstants.LIMIT_MODE_PAUSED)
        return true;
    }

    return settings.OrgLimitAlertSentAt__c == null ||
      settings.OrgLimitAlertSentAt__c.addMinutes(
        AIAssistApplicationConstants.LIMIT_ALERT_MINIMUM_GAP_MINUTES
      ) <= System.now();
  }

  // One entry per change. Going to Paused is logged as an error so it is published even while only errors are.
  private static void logChange(Change change) {
    AIPlatformLogManager.logCustomMessage(
      change.feature +
        ' changed from ' +
        change.fromMode +
        ' to ' +
        change.toMode +
        ' at ' +
        change.percent +
        ' percent of an org limit.',
      'Limit: ' + change.limitName,
      'AIOrgLimitMonitor',
      'refreshIfStale',
      null,
      change.toMode == AIAssistApplicationConstants.LIMIT_MODE_PAUSED
        ? AIAssistApplicationConstants.LOG_SEVERITY_ERROR
        : AIAssistApplicationConstants.LOG_SEVERITY_WARNING
    );
  }

  // One notification for all the changes of one reading, to the administrators.
  private static void notifyAdministrators(List<Change> changes) {
    try {
      Change headline = changes[0];
      for (Change change : changes) {
        if (change.toMode == AIAssistApplicationConstants.LIMIT_MODE_PAUSED)
          headline = change;
      }

      String effect = headline.toMode ==
        AIAssistApplicationConstants.LIMIT_MODE_PAUSED
        ? Label.AI_Alert_Org_Limits_Effect_Paused
        : (headline.toMode == AIAssistApplicationConstants.LIMIT_MODE_DEGRADED
            ? Label.AI_Alert_Org_Limits_Effect_Degraded
            : Label.AI_Alert_Org_Limits_Effect_Normal);
      String title = String.format(
        Label.AI_Alert_Org_Limits_Title,
        new List<String>{ headline.feature, headline.toMode }
      );
      String body = String.format(
        Label.AI_Alert_Org_Limits_Body,
        new List<String>{
          headline.limitName == null ? headline.feature : headline.limitName,
          String.valueOf(headline.percent),
          effect
        }
      );

      List<Id> recipientIds = AIMessagingSelector.getAdminUserIds(
        AIAssistApplicationConstants.LIMIT_ALERT_MAX_RECIPIENTS
      );
      if (recipientIds.isEmpty())
        return;

      sentAlertTitles.add(title);
      if (!sendCustomNotification(title, body, recipientIds))
        sendEmails(title, body, recipientIds);
    } catch (Exception notifyFailure) {
      AIPlatformLogManager.logException(
        notifyFailure,
        'AIOrgLimitMonitor',
        'notifyAdministrators'
      );
    }
  }

  // False when the notification type is missing or the send failed, so the caller falls back to email.
  private static Boolean sendCustomNotification(
    String title,
    String body,
    List<Id> recipientIds
  ) {
    try {
      List<CustomNotificationType> types = [
        SELECT Id
        FROM CustomNotificationType
        WHERE DeveloperName = :NOTIFICATION_TYPE_NAME
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (types.isEmpty())
        return false;

      Messaging.CustomNotification notification = new Messaging.CustomNotification();
      notification.setNotificationTypeId(types[0].Id);
      notification.setTitle(title);
      notification.setBody(body);
      notification.setTargetPageRef(
        '{"type":"standard__namedPage","attributes":{"pageName":"home"}}'
      );
      Set<String> recipients = new Set<String>();
      for (Id recipientId : recipientIds)
        recipients.add(String.valueOf(recipientId));
      notification.send(recipients);

      return true;
    } catch (Exception sendFailure) {
      AIPlatformLogManager.logException(
        sendFailure,
        'AIOrgLimitMonitor',
        'sendCustomNotification'
      );
      return false;
    }
  }

  private static void sendEmails(
    String title,
    String body,
    List<Id> recipientIds
  ) {
    List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

    for (Id recipientId : recipientIds) {
      Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
      email.setTargetObjectId(recipientId);
      email.setSaveAsActivity(false);
      email.setSubject(title);
      email.setPlainTextBody(body);
      emails.add(email);
    }

    Messaging.sendEmail(emails, false);
  }
}
