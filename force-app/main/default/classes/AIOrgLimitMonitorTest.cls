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
  // testScenario1: Usage below the degraded threshold is Normal, at it Degraded, at the paused threshold Paused; each feature reads only its own limits.
  // testScenario2: A feature that was Paused stays Paused until usage is below the threshold by the margin, then steps down through Degraded to Normal the same way.
  // testScenario3: The maximum share replaces a higher paused threshold, and blank, out of range or contradictory thresholds fall back to safe values.
  // testScenario4: Chat Paused refuses a new message with the paused label and its own code, and a message is accepted again once usage falls.
  // testScenario5: Events are used only when an administrator turned them on and the Events feature is Normal; otherwise the window polls.
  // testScenario6: Only errors are logged while Logging is not Normal.
  // testScenario7: The reading is kept as a short string and read back, and a malformed or blank one is treated as never read.
  // testScenario8: Refreshing keeps the reading, tells the administrators once when a feature changes mode, and does nothing while the reading is fresh.
  // testScenario9: A failure while reading the limits never throws, and falls back to the last known state or Normal.

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
    AIOrgLimitMonitor.isTestFailureThrown = false;
    AIAssistSettingsService.clearCache();
  }

  // Sets the usage of the limits the features read. Chat reads API requests, Events reads hourly published events.
  private static void setUsage(Integer apiPercent, Integer eventPercent) {
    AIOrgLimitMonitor.transactionState = null;
    AIOrgLimitMonitor.testLimits = new Map<String, List<Decimal>>{
      'DailyApiRequests' => new List<Decimal>{ apiPercent, 100 },
      'DailyAsyncApexExecutions' => new List<Decimal>{ 0, 100 },
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
      'DailyApiRequests',
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
    Test.stopTest();

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
}
