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

An administrator sets the thresholds in AIAssistSettings__c: Degraded at 70 and Paused at 85 percent by
default, and a maximum share that replaces the Paused threshold when it is lower, so AI Assist never takes
a limit above that percentage and the rest is the subscriber's buffer. A feature returns to a milder mode
only once usage is below the threshold by the resume margin (5 points by default), so it does not flip
back and forth at the line.

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
*/

public inherited sharing class AIOrgLimitMonitor {
  public class FeatureState {
    public String mode = AIAssistApplicationConstants.LIMIT_MODE_NORMAL;
    public Integer percent = 0;
    public String limitName; // The limit that decided the mode; not kept between reads.
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
  }

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
    Thresholds thresholds = getThresholds();
    Map<String, List<Decimal>> readings = readLimits();
    State freshState = new State();
    freshState.checkedAt = System.currentTimeMillis();

    for (String feature : FEATURES) {
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

  // The administrator's thresholds made safe: a blank, silly or contradictory value never switches AI Assist off or leaves it unprotected. The maximum share replaces the paused threshold when it is lower.
  public static Thresholds getThresholds() {
    AIAssistSettings__c settings = AIAssistSettingsService.getSettings();
    Thresholds thresholds = new Thresholds();

    thresholds.paused = inRange(
      settings.OrgLimitPausedPercent__c,
      2,
      100,
      AIAssistApplicationConstants.DEFAULT_LIMIT_PAUSED_PERCENT
    );
    Integer maxShare = inRange(
      settings.OrgLimitMaxSharePercent__c,
      2,
      100,
      null
    );
    if (maxShare != null && maxShare < thresholds.paused)
      thresholds.paused = maxShare;

    thresholds.degraded = inRange(
      settings.OrgLimitDegradedPercent__c,
      1,
      99,
      AIAssistApplicationConstants.DEFAULT_LIMIT_DEGRADED_PERCENT
    );
    if (thresholds.degraded >= thresholds.paused)
      thresholds.degraded = Math.max(1, thresholds.paused - 1);

    thresholds.margin = inRange(
      settings.OrgLimitResumeMarginPercent__c,
      0,
      50,
      AIAssistApplicationConstants.DEFAULT_LIMIT_RESUME_MARGIN_PERCENT
    );

    return thresholds;
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

  // {"t":checkedAtMilliseconds,"c":[modeIndex,percent],"e":[...],"g":[...]} for Chat, Events and Logging. Small enough for a 255 character field.
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
          featureState == null ? 0 : featureState.percent
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
