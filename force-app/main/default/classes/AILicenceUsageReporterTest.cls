/*
Class Name: AILicenceUsageReporterTest

=================================================================
=================================================================

Description: Testing utility for AILicenceUsageReporter: the month's counts are written to the feature parameters the License Management Org reads.

=================================================================
=================================================================
Applicable Classes:

AILicenceUsageReporter

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AILicenceUsageReporterTest {
  // testScenario1: The month's messages and failed turns are written to their feature parameters, and null counts are written as zero.

  @IsTest
  static void testScenario1() {
    Test.startTest();
    new AILicenceUsageReporter(1234, 5).execute(null);
    Integer messages = System.FeatureManagement.checkPackageIntegerValue(
      AIAssistApplicationConstants.FEATURE_MONTHLY_MESSAGES_USED
    );
    Integer errors = System.FeatureManagement.checkPackageIntegerValue(
      AIAssistApplicationConstants.FEATURE_MONTHLY_ERRORS
    );
    new AILicenceUsageReporter(null, null).execute(null);
    Integer messagesAfterNull = System.FeatureManagement.checkPackageIntegerValue(
      AIAssistApplicationConstants.FEATURE_MONTHLY_MESSAGES_USED
    );
    Test.stopTest();

    Assert.areEqual(1234, messages, 'The month\'s messages.');
    Assert.areEqual(5, errors, 'The month\'s failed turns.');
    Assert.areEqual(0, messagesAfterNull, 'Null is zero.');
  }
}
