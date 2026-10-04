/*
Class Name: AIOrgLimitMonitorTest

=================================================================
=================================================================

Description: Testing utility for AIOrgLimitMonitor: the mode each feature is in for a given usage, the thresholds the administrator sets, the wait before a switch back, what the modes hold back, and the one message to administrators.

=================================================================
=================================================================
Applicable Classes:

AIOrgLimitMonitor

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIOrgLimitMonitorTest {
  // testScenario1: Usage below the degraded threshold is Normal, at it Degraded, at the paused threshold Paused; each feature reads only its own limits, and none reads API requests.
  // testScenario2: A feature that was Paused stays Paused until usage is below the threshold by the margin, then steps down through Degraded to Normal the same way.
  // testScenario3: The maximum share replaces a higher paused threshold, and blank, out of range or contradictory thresholds fall back to safe values.
  // testScenario4: Chat Paused refuses a new message with the paused label and its own code, and a message is accepted again once usage falls.
  // testScenario5: Events are used only when an administrator turned them on and the Events feature is Normal; otherwise the window polls. Violation events stop only while Events is Paused.
  // testScenario6: Only errors are logged while Logging is not Normal.
  // testScenario7: The reading is kept as a short string and read back, and a malformed or blank one is treated as never read.
  // testScenario8: Refreshing keeps the reading, tells the administrators once when a feature changes mode, and does nothing while the reading is fresh.
  // testScenario9: A failure while reading the limits never throws, and falls back to the last known state or Normal.
  // testScenario10: A feature's own thresholds are used when set, the org-wide ones when blank and the defaults when both are; and nothing pauses later than 95 percent whatever is set.
  // testScenario11: AI Assist's own share trips a feature to Paused while the org has headroom: the asynchronous share for Chat, the event share for Events, and the storage budget for Chat and Logging.
  // testScenario12: validateSettings names each field that breaks Degraded < Paused <= 100 or a share of 5 to 100, and the footprint is measured and stored by a refresh.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  private static void reset() {
    AIOrgLimitMonitor.transactionState = null;
    AIOrgLimitMonitor.testLimits = null;
    AIOrgLimitMonitor.testFootprint = null;
    AIOrgLimitMonitor.isTestFailureThrown = false;
    AIAssistSettingsService.clearCache();
  }

  // Sets the usage of the limits the features read. Chat reads asynchronous Apex, Events reads hourly published events. API requests are full throughout, and no feature reads them.
  private static void setUsage(Integer asyncPercent, Integer eventPercent) {
    AIOrgLimitMonitor.transactionState = null;
    AIOrgLimitMonitor.testLimits = new Map<String, List<Decimal>>{
      'DailyApiRequests' => new List<Decimal>{ 100, 100 },
      'DailyAsyncApexExecutions' => new List<Decimal>{ asyncPercent, 100 },
      'DataStorageMB' => new List<Decimal>{ 0, 100 },
      'HourlyPublishedPlatformEvents' => new List<Decimal>{ eventPercent, 100 },
      'ZeroLimit' => new List<Decimal>{ 5, 0 }
    };
  }

  private static void configure(Map<String, Object> values) {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    for (String fieldName : values.keySet())
      settings.put(fieldName, values.get(fieldName));
    update settings;
    AIAssistSettingsService.clearCache();
  }

  private static AIOrgLimitMonitor.State stateAfter(
    AIOrgLimitMonitor.State previous
  ) {
    AIOrgLimitMonitor.transactionState = null;

    return AIOrgLimitMonitor.evaluate(previous);
  }

  @IsTest
  static void testScenario1() {
    reset();
    setUsage(40, 10);
    AIOrgLimitMonitor.State low = stateAfter(null);
    setUsage(70, 10);
    AIOrgLimitMonitor.State degraded = stateAfter(null);
    setUsage(85, 71);
    AIOrgLimitMonitor.State paused = stateAfter(null);

    Test.startTest();
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.LIMIT_MODE_NORMAL,
      low.byFeature.get(AIAssistApplicationConstants.LIMIT_FEATURE_CHAT).mode,
      'Below the degraded threshold.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.LIMIT_MODE_DEGRADED,
      degraded.byFeature.get(AIAssistApplicationConstants.LIMIT_FEATURE_CHAT)
        .mode,
      'At the degraded threshold.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.LIMIT_MODE_NORMAL,
      degraded.byFeature.get(AIAssistApplicationConstants.LIMIT_FEATURE_EVENTS)
        .mode,
      'Events read the event limits, not the API limit.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.LIMIT_MODE_PAUSED,
      paused.byFeature.get(AIAssistApplicationConstants.LIMIT_FEATURE_CHAT)
        .mode,
      'At the paused threshold.'
    );
    Assert.areEqual(
      'DailyAsyncApexExecutions',
      paused.byFeature.get(AIAssistApplicationConstants.LIMIT_FEATURE_CHAT)
        .limitName,
      'The limit that decided it is known.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.LIMIT_MODE_DEGRADED,
      paused.byFeature.get(AIAssistApplicationConstants.LIMIT_FEATURE_EVENTS)
        .mode,
      'The event limits are at 71 percent.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.LIMIT_MODE_DEGRADED,
      paused.byFeature.get(AIAssistApplicationConstants.LIMIT_FEATURE_LOGGING)
        .mode,
      'Logging reads the event limits too.'
    );
    Assert.areEqual(
      85,
      paused.byFeature.get(AIAssistApplicationConstants.LIMIT_FEATURE_CHAT)
        .percent,
      'The percentage is kept.'
    );
  }

  @IsTest
  static void testScenario2() {
    reset();
    String chat = AIAssistApplicationConstants.LIMIT_FEATURE_CHAT;
    setUsage(90, 0);
    AIOrgLimitMonitor.State step1 = stateAfter(null);
    setUsage(82, 0);
    AIOrgLimitMonitor.State step2 = stateAfter(step1); // Under 85 but not under 80.
    setUsage(78, 0);
    AIOrgLimitMonitor.State step3 = stateAfter(step2); // Under 80, still over the degraded line.
    setUsage(66, 0);
    AIOrgLimitMonitor.State step4 = stateAfter(step3); // Under 70 but not under 65.
    setUsage(60, 0);
    AIOrgLimitMonitor.State step5 = stateAfter(step4);

    Test.startTest();
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.LIMIT_MODE_PAUSED,
      step1.byFeature.get(chat).mode
    );
    Assert.areEqual(
      AIAssistApplicationConstants.LIMIT_MODE_PAUSED,
      step2.byFeature.get(chat).mode,
      'Waits for the margin.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.LIMIT_MODE_DEGRADED,
      step3.byFeature.get(chat).mode,
      'Steps down to Degraded.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.LIMIT_MODE_DEGRADED,
      step4.byFeature.get(chat).mode,
      'Waits for the margin again.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.LIMIT_MODE_NORMAL,
      step5.byFeature.get(chat).mode,
      'Back to Normal.'
    );
  }

  @IsTest
  static void testScenario3() {
    reset();
    configure(
      new Map<String, Object>{
        'OrgLimitMaxSharePercent__c' => 60,
        'OrgLimitPausedPercent__c' => 90,
        'OrgLimitDegradedPercent__c' => 50
      }
    );
    AIOrgLimitMonitor.Thresholds shared = AIOrgLimitMonitor.getThresholds();

    configure(
      new Map<String, Object>{
        'OrgLimitMaxSharePercent__c' => null,
        'OrgLimitPausedPercent__c' => null,
        'OrgLimitDegradedPercent__c' => null,
        'OrgLimitResumeMarginPercent__c' => null
      }
    );
    AIOrgLimitMonitor.Thresholds blank = AIOrgLimitMonitor.getThresholds();

    configure(
      new Map<String, Object>{
        'OrgLimitPausedPercent__c' => 80,
        'OrgLimitDegradedPercent__c' => 95,
        'OrgLimitResumeMarginPercent__c' => 99
      }
    );
    AIOrgLimitMonitor.Thresholds contradictory = AIOrgLimitMonitor.getThresholds();

    configure(
      new Map<String, Object>{
        'OrgLimitPausedPercent__c' => 0,
        'OrgLimitDegradedPercent__c' => 150,
        'OrgLimitResumeMarginPercent__c' => 5
      }
    );
    AIOrgLimitMonitor.Thresholds outOfRange = AIOrgLimitMonitor.getThresholds();

    Test.startTest();
    Test.stopTest();

    Assert.areEqual(
      60,
      shared.paused,
      'The maximum share is lower, so it wins.'
    );
    Assert.areEqual(50, shared.degraded, 'Degraded stays under it.');
    Assert.areEqual(85, blank.paused, 'Default.');
    Assert.areEqual(70, blank.degraded, 'Default.');
    Assert.areEqual(5, blank.margin, 'Default.');
    Assert.areEqual(80, contradictory.paused, 'Kept.');
    Assert.areEqual(
      79,
      contradictory.degraded,
      'Degraded can never reach paused.'
    );
    Assert.areEqual(
      5,
      contradictory.margin,
      'A margin out of range falls back.'
    );
    Assert.areEqual(85, outOfRange.paused, 'Out of range falls back.');
    Assert.areEqual(70, outOfRange.degraded, 'Out of range falls back.');
  }

  @IsTest
  static void testScenario4() {
    reset();
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    List<String> codes = new List<String>();

    Test.startTest();
    setUsage(95, 0);
    Boolean wasPaused = AIOrgLimitMonitor.isChatPaused();
    try {
      AIMessageValidator.validateSendRequest(
        agent.Id,
        'Hello',
        null,
        null,
        null
      );
    } catch (AIMessagingException refusal) {
      codes.add(refusal.code);
      codes.add(refusal.getMessage());
    }
    setUsage(10, 0);
    Boolean isPausedAfter = AIOrgLimitMonitor.isChatPaused();
    Test.stopTest();

    Assert.isTrue(wasPaused, 'Paused at 95 percent.');
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_ORG_LIMITS_PAUSED,
      codes[0],
      'Its own code.'
    );
    Assert.areEqual(
      Label.AI_Error_Org_Limits_Paused,
      codes[1],
      'Its own label.'
    );
    Assert.isFalse(isPausedAfter, 'Resumes without anyone doing anything.');
  }

  @IsTest
  static void testScenario5() {
    reset();
    Test.startTest();
    setUsage(0, 0);
    String byDefault = AIOrgLimitMonitor.getNotificationMode();
    configure(
      new Map<String, Object>{ 'IsEventNotificationEnabled__c' => true }
    );
    setUsage(0, 0);
    String switchedOn = AIOrgLimitMonitor.getNotificationMode();
    Boolean isAllowed = AIOrgLimitMonitor.isEventNotificationAllowed();
    setUsage(0, 75);
    String nearLimit = AIOrgLimitMonitor.getNotificationMode();
    Boolean isViolationEventSentDegraded = AIOrgLimitMonitor.isViolationEventAllowed();
    setUsage(0, 90);
    Boolean isViolationEventSentPaused = AIOrgLimitMonitor.isViolationEventAllowed();
    Test.stopTest();

    Assert.isTrue(
      isViolationEventSentDegraded,
      'Violation events keep going while Events is Degraded.'
    );
    Assert.isFalse(
      isViolationEventSentPaused,
      'Violation events stop while Events is Paused.'
    );

    Assert.areEqual(
      AIAssistApplicationConstants.NOTIFICATION_MODE_POLLING,
      byDefault,
      'Polling is the default.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.NOTIFICATION_MODE_EVENTS,
      switchedOn,
      'Events when an administrator turns them on and there is headroom.'
    );
    Assert.isTrue(isAllowed);
    Assert.areEqual(
      AIAssistApplicationConstants.NOTIFICATION_MODE_POLLING,
      nearLimit,
      'Back to polling near the limit.'
    );
  }

  @IsTest
  static void testScenario6() {
    reset();
    Test.startTest();
    setUsage(0, 0);
    Boolean normal = AIOrgLimitMonitor.isErrorOnlyLogging();
    setUsage(0, 72);
    Boolean degraded = AIOrgLimitMonitor.isErrorOnlyLogging();
    AIPlatformLogManager.logCustomMessage(
      'A warning',
      null,
      'Test',
      'test',
      null
    );
    AIPlatformLogManager.logCustomMessage(
      'An error',
      null,
      'Test',
      'test',
      null,
      AIAssistApplicationConstants.LOG_SEVERITY_ERROR
    );
    Test.stopTest();

    Assert.isFalse(normal, 'Everything is logged normally.');
    Assert.isTrue(degraded, 'Only errors while under pressure.');
  }

  @IsTest
  static void testScenario7() {
    reset();
    setUsage(90, 72);
    AIOrgLimitMonitor.State original = stateAfter(null);

    Test.startTest();
    String serialized = AIOrgLimitMonitor.serialize(original);
    AIOrgLimitMonitor.State readBack = AIOrgLimitMonitor.parse(serialized);
    Test.stopTest();

    Assert.isTrue(serialized.length() <= 255, 'Fits the field.');
    Assert.areEqual(original.checkedAt, readBack.checkedAt, 'The time.');
    for (String feature : original.byFeature.keySet()) {
      Assert.areEqual(
        original.byFeature.get(feature).mode,
        readBack.byFeature.get(feature).mode,
        feature + ' mode.'
      );
      Assert.areEqual(
        original.byFeature.get(feature).percent,
        readBack.byFeature.get(feature).percent,
        feature + ' percent.'
      );
    }
    Assert.isNull(AIOrgLimitMonitor.parse(null), 'Blank.');
    Assert.isNull(AIOrgLimitMonitor.parse('not json'), 'Malformed.');
    Assert.isNull(AIOrgLimitMonitor.parse('{"t":1}'), 'Incomplete.');
  }

  @IsTest
  static void testScenario8() {
    reset();
    User admin = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ admin },
      'AIAssistAdminUser'
    );
    setUsage(90, 0);

    Test.startTest();
    AIOrgLimitMonitor.refreshIfStale();
    Integer alertsAfterFirst = AIOrgLimitMonitor.sentAlertTitles.size();
    String titleSent = alertsAfterFirst > 0
      ? AIOrgLimitMonitor.sentAlertTitles[0]
      : null;
    AIAssistSettings__c kept = AIAssistSettings__c.getOrgDefaults();
    AIOrgLimitMonitor.refreshIfStale(); // Fresh now: nothing to do.
    Test.stopTest();

    Assert.isNotNull(kept.OrgLimitStateJson__c, 'The reading is kept.');
    Assert.isNotNull(
      kept.OrgLimitAlertSentAt__c,
      'When administrators were told.'
    );
    Assert.areEqual(1, alertsAfterFirst, 'Told once.');
    Assert.isTrue(
      titleSent.contains(AIAssistApplicationConstants.LIMIT_MODE_PAUSED),
      'The title names the mode.'
    );
    Assert.areEqual(
      1,
      AIOrgLimitMonitor.sentAlertTitles.size(),
      'A fresh reading sends nothing more.'
    );
    Assert.isTrue(
      AIOrgLimitMonitor.getAdminUserIdsForTest().contains(admin.Id),
      'The administrator is a recipient.'
    );
  }

  @IsTest
  static void testScenario9() {
    reset();
    setUsage(0, 0);
    AIOrgLimitMonitor.State known = stateAfter(null);
    AIOrgLimitMonitor.isTestFailureThrown = true;

    Test.startTest();
    AIOrgLimitMonitor.transactionState = null;
    String modeWithNoHistory = AIOrgLimitMonitor.getMode(
      AIAssistApplicationConstants.LIMIT_FEATURE_CHAT
    );
    AIOrgLimitMonitor.refreshIfStale();
    Boolean isPaused = AIOrgLimitMonitor.isChatPaused();
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.LIMIT_MODE_NORMAL,
      modeWithNoHistory,
      'With no last known state a failed reading is Normal: the monitor is never the reason chat stops.'
    );
    Assert.isFalse(isPaused, 'Not paused.');
    Assert.isNotNull(known, 'A normal reading works.');
  }

  @IsTest
  static void testScenario10() {
    reset();
    Test.startTest();
    configure(
      new Map<String, Object>{
        'OrgLimitDegradedPercent__c' => null,
        'OrgLimitPausedPercent__c' => null,
        'OrgLimitMaxSharePercent__c' => null
      }
    );
    AIOrgLimitMonitor.Thresholds defaults = AIOrgLimitMonitor.getThresholds(
      AIAssistApplicationConstants.LIMIT_FEATURE_CHAT
    );
    configure(
      new Map<String, Object>{
        'OrgLimitDegradedPercent__c' => 40,
        'OrgLimitPausedPercent__c' => 60,
        'OrgLimitMaxSharePercent__c' => 80,
        'EventsDegradedPercent__c' => 20,
        'EventsPausedPercent__c' => 30,
        'EventsAppSharePercent__c' => 10
      }
    );
    AIOrgLimitMonitor.Thresholds orgWide = AIOrgLimitMonitor.getThresholds(
      AIAssistApplicationConstants.LIMIT_FEATURE_CHAT
    );
    AIOrgLimitMonitor.Thresholds own = AIOrgLimitMonitor.getThresholds(
      AIAssistApplicationConstants.LIMIT_FEATURE_EVENTS
    );
    configure(
      new Map<String, Object>{
        'OrgLimitMaxSharePercent__c' => null,
        'ChatDegradedPercent__c' => 97,
        'ChatPausedPercent__c' => 100,
        'ChatAppSharePercent__c' => 3
      }
    );
    AIOrgLimitMonitor.Thresholds floored = AIOrgLimitMonitor.getThresholds(
      AIAssistApplicationConstants.LIMIT_FEATURE_CHAT
    );
    setUsage(96, 0);
    String modeAt96 = stateAfter(null)
      .byFeature.get(AIAssistApplicationConstants.LIMIT_FEATURE_CHAT)
      .mode;
    Test.stopTest();

    Assert.areEqual(70, defaults.degraded, 'Both blank: the default.');
    Assert.areEqual(85, defaults.paused, 'Both blank: the default.');
    Assert.isNull(defaults.appShare, 'No share budget unless one is set.');
    Assert.areEqual(40, orgWide.degraded, 'Blank on Chat: the org-wide value.');
    Assert.areEqual(60, orgWide.paused, 'Blank on Chat: the org-wide value.');
    Assert.areEqual(80, orgWide.appShare, 'Blank on Chat: the org-wide share.');
    Assert.areEqual(20, own.degraded, 'The feature\'s own value.');
    Assert.areEqual(30, own.paused, 'The feature\'s own value.');
    Assert.areEqual(10, own.appShare, 'The feature\'s own share.');
    Assert.areEqual(95, floored.paused, 'Never later than 95 percent.');
    Assert.areEqual(94, floored.degraded, 'Degraded stays under it.');
    Assert.isNull(floored.appShare, 'A share under 5 is not a budget.');
    Assert.areEqual(
      AIAssistApplicationConstants.LIMIT_MODE_PAUSED,
      modeAt96,
      'Paused at 96 percent although the setting says 100.'
    );
  }

  @IsTest
  static void testScenario11() {
    reset();
    configure(
      new Map<String, Object>{
        'ChatAppSharePercent__c' => 20,
        'EventsAppSharePercent__c' => 50,
        'StorageBudgetPercent__c' => 10
      }
    );
    // The org is almost idle: 5 percent of everything. Limits are 100 a day of asynchronous Apex, 100 an hour of events and 100 MB.
    setUsage(5, 5);
    AIOrgLimitMonitor.Footprint footprint = new AIOrgLimitMonitor.Footprint();
    AIOrgLimitMonitor.testFootprint = footprint;

    Test.startTest();
    footprint.asyncJobs = 19;
    AIOrgLimitMonitor.State under = stateAfter(null);
    footprint.asyncJobs = 20;
    AIOrgLimitMonitor.State asyncTripped = stateAfter(null);
    footprint.asyncJobs = 0;
    footprint.events = 1200; // Half of 24 hours of the hourly allowance.
    AIOrgLimitMonitor.State eventsTripped = stateAfter(null);
    footprint.events = 0;
    footprint.storageMegabytes = 10;
    AIOrgLimitMonitor.State storageTripped = stateAfter(null);
    Test.stopTest();

    String chat = AIAssistApplicationConstants.LIMIT_FEATURE_CHAT;
    String events = AIAssistApplicationConstants.LIMIT_FEATURE_EVENTS;
    String logging = AIAssistApplicationConstants.LIMIT_FEATURE_LOGGING;
    String normal = AIAssistApplicationConstants.LIMIT_MODE_NORMAL;
    String paused = AIAssistApplicationConstants.LIMIT_MODE_PAUSED;
    Assert.areEqual(normal, under.byFeature.get(chat).mode, 'Under its share.');
    Assert.areEqual(19, under.byFeature.get(chat).appPercent, 'Its share.');
    Assert.areEqual(
      paused,
      asyncTripped.byFeature.get(chat).mode,
      'AI Assist used its share of asynchronous Apex although the org has headroom.'
    );
    Assert.isTrue(
      asyncTripped.byFeature.get(chat).limitName.contains('AI Assist share'),
      'The reason says it is the share.'
    );
    Assert.areEqual(
      normal,
      asyncTripped.byFeature.get(events).mode,
      'Events have their own share.'
    );
    Assert.areEqual(
      paused,
      eventsTripped.byFeature.get(events).mode,
      'Events.'
    );
    Assert.areEqual(
      normal,
      eventsTripped.byFeature.get(chat).mode,
      'Chat is not paused by the event share.'
    );
    Assert.areEqual(
      paused,
      storageTripped.byFeature.get(chat).mode,
      'The storage budget pauses chat.'
    );
    Assert.areEqual(
      paused,
      storageTripped.byFeature.get(logging).mode,
      'And logging.'
    );
    Assert.areEqual(
      normal,
      storageTripped.byFeature.get(events).mode,
      'Events store nothing.'
    );
    Assert.areEqual(
      20,
      AIOrgLimitMonitor.parse(AIOrgLimitMonitor.serialize(asyncTripped))
        .byFeature.get(chat)
        .appPercent,
      'The share is kept with the reading.'
    );
  }

  @IsTest
  static void testScenario12() {
    reset();
    AIAssistSettings__c sound = new AIAssistSettings__c(
      ChatDegradedPercent__c = 50,
      ChatPausedPercent__c = 100,
      ChatAppSharePercent__c = 5,
      StorageBudgetPercent__c = 100
    );
    AIAssistSettings__c broken = new AIAssistSettings__c(
      ChatDegradedPercent__c = 80,
      ChatPausedPercent__c = 80,
      EventsPausedPercent__c = 101,
      LoggingDegradedPercent__c = 0,
      LoggingAppSharePercent__c = 4,
      OrgLimitMaxSharePercent__c = 101,
      StorageBudgetPercent__c = 2
    );
    insert new AIPlatformLog__c(ClassName__c = 'Footprint');
    setUsage(0, 0);

    Test.startTest();
    List<String> noProblems = AIOrgLimitMonitor.validateSettings(sound);
    List<String> problems = AIOrgLimitMonitor.validateSettings(broken);
    AIOrgLimitMonitor.Footprint before = AIOrgLimitMonitor.getFootprint();
    AIOrgLimitMonitor.refreshIfStale();
    AIAssistSettingsService.clearCache();
    Test.stopTest();

    Assert.isTrue(noProblems.isEmpty(), 'Sound settings: ' + noProblems);
    Assert.areEqual(6, problems.size(), 'One sentence each: ' + problems);
    Assert.isTrue(
      String.join(problems, ' ')
        .contains('ChatDegradedPercent__c must be lower than'),
      'The field to fix is named.'
    );
    Assert.isNull(before.measuredAt, 'Never measured.');
    String stored = AIAssistSettings__c.getOrgDefaults().AppUsageStateJson__c;
    Assert.isTrue(String.isNotBlank(stored), 'A refresh measures and stores.');
    AIOrgLimitMonitor.Footprint measured = (AIOrgLimitMonitor.Footprint) JSON.deserialize(
      stored,
      AIOrgLimitMonitor.Footprint.class
    );
    Assert.isNotNull(measured.measuredAt, 'When it was measured.');
    Assert.isTrue(
      measured.events >= 1,
      'The log entry is counted as an event.'
    );
    Assert.isTrue(measured.storageMegabytes > 0, 'Records take storage.');
  }
}
