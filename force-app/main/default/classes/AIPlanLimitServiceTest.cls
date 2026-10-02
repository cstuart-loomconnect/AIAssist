/*
Class Name: AIPlanLimitServiceTest

=================================================================
=================================================================

Description: Testing utility for AIPlanLimitService: plan limits come from Feature Management, and a limit that cannot be read means unlimited.

=================================================================
=================================================================
Applicable Classes:

AIPlanLimitService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIPlanLimitServiceTest {
  // testScenario1: Reading the limits with nothing set for the test returns either unlimited or a positive number, and never throws.
  // testScenario2: A value set for the test replaces the real one, a null value means unlimited, and a Boolean parameter can switch Apex data sources off.
  // testScenario3: Resetting clears the values set for the test, so the real limits are read again.
  // testScenario4: The activation parameters are read the same way, and the activation checks are off in a test until it asks for them.

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
    AIPlanLimitService.resetForTest();

    Test.startTest();
    Integer messageLimit = AIPlanLimitService.getMessageLimit();
    Integer usageLimit = AIPlanLimitService.getUsageLimit();
    Boolean isApexAllowed = AIPlanLimitService.isApexAllowed();
    Test.stopTest();

    Assert.isTrue(
      messageLimit == null || messageLimit > 0,
      'The message limit is unlimited or positive.'
    );
    Assert.isTrue(
      usageLimit == null || usageLimit > 0,
      'The token limit is unlimited or positive.'
    );
    Assert.isNotNull(
      isApexAllowed,
      'Whether Apex data sources are allowed is always answered.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_MESSAGES,
      5000
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_USAGE,
      null
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      false
    );

    Test.startTest();
    Integer messageLimit = AIPlanLimitService.getMessageLimit();
    Integer cachedMessageLimit = AIPlanLimitService.getMessageLimit();
    Integer usageLimit = AIPlanLimitService.getUsageLimit();
    Boolean isApexAllowed = AIPlanLimitService.isApexAllowed();
    Test.stopTest();

    Assert.areEqual(
      5000,
      messageLimit,
      'The value set for the test is returned.'
    );
    Assert.areEqual(
      5000,
      cachedMessageLimit,
      'A second read returns the same value.'
    );
    Assert.isNull(usageLimit, 'A null value means unlimited.');
    Assert.isFalse(isApexAllowed, 'The plan can switch Apex data sources off.');
  }

  @IsTest
  static void testScenario3() {
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_MESSAGES,
      10
    );
    AIPlanLimitService.resetForTest();

    Test.startTest();
    Integer messageLimit = AIPlanLimitService.getMessageLimit();
    Test.stopTest();

    Assert.areNotEqual(
      10,
      messageLimit,
      'After a reset the limit is read from Feature Management again.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_ACTIVE_AGENTS,
      3
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_ACTIVE_DATA_SOURCES,
      10
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_ACTIVE_WORKFLOW_ACTIONS,
      null
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_CONVERSATION_RETENTION_DAYS,
      90
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MULTIPLE_PROVIDERS_ALLOWED,
      false
    );

    Test.startTest();
    Boolean isCheckedByDefault = AIPlanLimitService.isActivationChecked();
    AIPlanLimitService.isActivationCheckedInTest = true;
    Boolean isCheckedWhenAsked = AIPlanLimitService.isActivationChecked();
    Test.stopTest();

    Assert.areEqual(3, AIPlanLimitService.getActiveAgentLimit(), 'Agents.');
    Assert.areEqual(
      10,
      AIPlanLimitService.getActiveDataSourceLimit(),
      'Data sources.'
    );
    Assert.isNull(
      AIPlanLimitService.getActiveActionLimit(),
      'A null value means unlimited.'
    );
    Assert.areEqual(90, AIPlanLimitService.getRetentionDayCap(), 'Retention.');
    Assert.isFalse(
      AIPlanLimitService.isMultipleProvidersAllowed(),
      'The plan can limit the organisation to one provider.'
    );
    Assert.isFalse(isCheckedByDefault, 'Off in a test by default.');
    Assert.isTrue(isCheckedWhenAsked, 'On once the test asks.');
  }
}
