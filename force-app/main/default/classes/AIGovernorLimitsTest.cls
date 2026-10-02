/*
Class Name: AIGovernorLimitsTest

=================================================================
=================================================================

Description: Testing utility for AIGovernorLimits: the checks that stop work before a limit is hit.

=================================================================
=================================================================
Applicable Classes:

AIGovernorLimits

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIGovernorLimitsTest {
  // testScenario1: isUncommittedDmlSince is false with no DML since the snapshot, true once a record is inserted, and false for a null snapshot.
  // testScenario2: isUncommittedWorkException is true only for a CalloutException carrying the platform's "uncommitted work pending" message.
  // testScenario3: getRemainingCalloutMilliseconds counts down from the 120 second budget, and is zero when there is no start time.
  // testScenario4: isSafeToRunToolCall and isSafeToPublishProgress are true in a fresh transaction, which has plenty of every limit left.

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
    Test.startTest();
    AIGovernorLimits.DmlSnapshot snapshot = AIGovernorLimits.takeDmlSnapshot();
    Boolean isDmlBeforeInsert = AIGovernorLimits.isUncommittedDmlSince(
      snapshot
    );

    AIAssistTestDataFactory.createAccounts(1, true);
    Boolean isDmlAfterInsert = AIGovernorLimits.isUncommittedDmlSince(snapshot);
    Test.stopTest();

    Assert.isFalse(isDmlBeforeInsert, 'No DML has run since the snapshot.');
    Assert.isTrue(
      isDmlAfterInsert,
      'The insert should be detected as uncommitted DML.'
    );
    Assert.isFalse(
      AIGovernorLimits.isUncommittedDmlSince(null),
      'A null snapshot should never report DML.'
    );
  }

  @IsTest
  static void testScenario2() {
    Test.startTest();
    Boolean isUncommittedWork = AIGovernorLimits.isUncommittedWorkException(
      new CalloutException(
        'You have uncommitted work pending. Please commit or rollback before calling out'
      )
    );
    Boolean isOtherCalloutError = AIGovernorLimits.isUncommittedWorkException(
      new CalloutException('Read timed out')
    );
    Boolean isOtherExceptionType = AIGovernorLimits.isUncommittedWorkException(
      new DmlException('You have uncommitted work pending.')
    );
    Boolean isNull = AIGovernorLimits.isUncommittedWorkException(null);
    Test.stopTest();

    Assert.isTrue(
      isUncommittedWork,
      'The platform\'s uncommitted work callout error should be recognised.'
    );
    Assert.isFalse(
      isOtherCalloutError,
      'A timeout is an ordinary callout failure.'
    );
    Assert.isFalse(
      isOtherExceptionType,
      'Only a CalloutException can be an uncommitted work callout failure.'
    );
    Assert.isFalse(
      isNull,
      'No exception is not an uncommitted work exception.'
    );
  }

  @IsTest
  static void testScenario3() {
    Test.startTest();
    Integer remainingMilliseconds = AIGovernorLimits.getRemainingCalloutMilliseconds(
      System.currentTimeMillis()
    );
    Integer remainingWithNoStart = AIGovernorLimits.getRemainingCalloutMilliseconds(
      null
    );
    Integer remainingAfterOneMinute = AIGovernorLimits.getRemainingCalloutMilliseconds(
      System.currentTimeMillis() - 60000
    );
    Test.stopTest();

    Assert.isTrue(
      remainingMilliseconds <=
      AIAssistApplicationConstants.MAX_TRANSACTION_CALLOUT_MILLISECONDS,
      'Remaining callout time can never exceed the budget.'
    );
    Assert.isTrue(
      remainingMilliseconds >
      AIAssistApplicationConstants.MAX_TRANSACTION_CALLOUT_MILLISECONDS - 5000,
      'Almost none of the budget should be used yet.'
    );
    Assert.areEqual(
      0,
      remainingWithNoStart,
      'With no start there is no budget, so the caller stops.'
    );
    Assert.isTrue(
      remainingAfterOneMinute <= 60000,
      'A minute spent leaves at most a minute.'
    );
  }

  @IsTest
  static void testScenario4() {
    Test.startTest();
    Boolean isSafeToRunToolCall = AIGovernorLimits.isSafeToRunToolCall();
    Boolean isSafeToPublishProgress = AIGovernorLimits.isSafeToPublishProgress();
    Test.stopTest();

    Assert.isTrue(
      isSafeToRunToolCall,
      'A fresh transaction has plenty of each limit left for a tool call.'
    );
    Assert.isTrue(
      isSafeToPublishProgress,
      'A fresh transaction has plenty of Publish Immediately headroom.'
    );
  }
}
