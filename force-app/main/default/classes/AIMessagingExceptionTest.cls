/*
Class Name: AIMessagingExceptionTest

=================================================================
=================================================================

Description: Testing utility for AIMessagingException: an expected refusal and an unexpected failure are told apart, and only a failure keeps its detail.

=================================================================
=================================================================
Applicable Classes:

AIMessagingException

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIMessagingExceptionTest {
  // testScenario1: A refusal carries its code and its Custom Label text, is flagged as a refusal and has no detail.
  // testScenario2: A failure shows the user only the generic label, keeps the real reason in its detail, and keeps the cause when there is one.

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
    AIMessagingException refusal = AIMessagingException.newRefusal(
      AIAssistApplicationConstants.ERROR_MESSAGE_EMPTY,
      Label.AI_Error_Message_Empty
    );
    Test.stopTest();

    Assert.isTrue(
      refusal.isRefusal,
      'A refusal is an expected outcome, not a fault.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_MESSAGE_EMPTY,
      refusal.code,
      'The code.'
    );
    Assert.areEqual(
      Label.AI_Error_Message_Empty,
      refusal.getMessage(),
      'The message is the label.'
    );
    Assert.isNull(refusal.detail, 'A refusal has nothing to hide.');
  }

  @IsTest
  static void testScenario2() {
    DmlException cause = new DmlException('Underlying problem');

    Test.startTest();
    AIMessagingException withCause = AIMessagingException.newFailure(
      'Real reason',
      cause
    );
    AIMessagingException withoutCause = AIMessagingException.newFailure(
      'Another reason',
      null
    );
    Test.stopTest();

    Assert.isFalse(withCause.isRefusal, 'A failure is not a refusal.');
    Assert.areEqual(
      Label.AI_Error_Generic,
      withCause.getMessage(),
      'The user sees only the generic label.'
    );
    Assert.areEqual(
      'Real reason',
      withCause.detail,
      'The real reason is kept for the log.'
    );
    Assert.areEqual(cause, withCause.getCause(), 'The cause is kept.');
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_GENERIC,
      withCause.code,
      'A failure has the generic code.'
    );
    Assert.areEqual(
      Label.AI_Error_Generic,
      withoutCause.getMessage(),
      'No cause is fine.'
    );
    Assert.isNull(withoutCause.getCause(), 'And there is none.');
  }
}
