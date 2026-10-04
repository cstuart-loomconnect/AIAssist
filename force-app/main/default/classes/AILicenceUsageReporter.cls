/*
Class Name: AILicenceUsageReporter

=================================================================
=================================================================

Description: Reports the month's messages and failed turns from the subscriber's org to the License
Management Org, through the MonthlyMessagesUsed and MonthlyErrors feature parameters (subscriber to LMO).
Counts only: no content, no user, no record.

A job of its own because writing a feature parameter is a change to a setup object, which cannot share a
transaction with the custom setting AIOrgUsageTotalsBatch has just saved, and because a failure to write
it is not one Apex can catch: it must not take the usage totals with it.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public inherited sharing class AILicenceUsageReporter implements Queueable {
  private Integer monthlyMessages;
  private Integer monthlyErrors;

  public AILicenceUsageReporter(
    Integer monthlyMessages,
    Integer monthlyErrors
  ) {
    this.monthlyMessages = monthlyMessages == null ? 0 : monthlyMessages;
    this.monthlyErrors = monthlyErrors == null ? 0 : monthlyErrors;
  }

  public void execute(QueueableContext context) {
    System.FeatureManagement.setPackageIntegerValue(
      AIAssistApplicationConstants.FEATURE_MONTHLY_MESSAGES_USED,
      monthlyMessages
    );
    System.FeatureManagement.setPackageIntegerValue(
      AIAssistApplicationConstants.FEATURE_MONTHLY_ERRORS,
      monthlyErrors
    );
  }
}
