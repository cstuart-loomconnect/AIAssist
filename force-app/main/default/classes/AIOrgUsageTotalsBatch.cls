/*
Class Name: AIOrgUsageTotalsBatch

=================================================================
=================================================================

Description: Counts the organisation's usage for the current month exactly, from the AIUsageDaily__c
rows, and stores the total of its closed days (every day before today) through AIOrgUsageService, which
adds today's rows to it on a read. Run by the maintenance job. A batch because a month of usage rows can
be more than one transaction may read; the totals are carried between chunks (Database.Stateful).

Runs whether or not the application is switched on, and in system mode: usage rows belong to every user.
When it finishes it also reports the month's messages and failed turns, today's included, to the License
Management Org through the MonthlyMessagesUsed and MonthlyErrors feature parameters
(AILicenceUsageReporter).

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Stores the closed days only: today is counted on a read, so no turn writes the totals.
*/

public inherited sharing class AIOrgUsageTotalsBatch implements Database.Batchable<SObject>, Database.Stateful {
  private Date today = AIAssistGlobalUtility.getOrgToday();
  private AIMessagingSelector.UsageTotals closedDays = new AIMessagingSelector.UsageTotals();
  private Decimal monthMessages = 0;
  private Decimal monthFailedTurns = 0;

  public Database.QueryLocator start(Database.BatchableContext context) {
    Date monthStart = today.toStartOfMonth();

    return Database.getQueryLocator(
      [
        SELECT
          UsageDate__c,
          MessageCount__c,
          FailedTurnCount__c,
          InputTokens__c,
          OutputTokens__c
        FROM AIUsageDaily__c
        WHERE UsageDate__c >= :monthStart
        WITH SYSTEM_MODE
      ]
    );
  }

  public void execute(
    Database.BatchableContext context,
    List<AIUsageDaily__c> scope
  ) {
    for (AIUsageDaily__c usageRow : scope) {
      Decimal messages = usageRow.MessageCount__c == null
        ? 0
        : usageRow.MessageCount__c;
      Decimal tokens =
        (usageRow.InputTokens__c == null ? 0 : usageRow.InputTokens__c) +
        (usageRow.OutputTokens__c == null ? 0 : usageRow.OutputTokens__c);

      monthFailedTurns += usageRow.FailedTurnCount__c == null
        ? 0
        : usageRow.FailedTurnCount__c;
      monthMessages += messages;
      if (usageRow.UsageDate__c < today) {
        closedDays.messages += messages;
        closedDays.tokens += tokens;
      }
    }
  }

  public void finish(Database.BatchableContext context) {
    AIOrgUsageService.replace(today, closedDays);

    // The month's messages and failed turns go back to the License Management Org. In a job of its own: a feature parameter is a setup object, and the totals above were just saved to a custom setting in this transaction.
    // Not from a test: feature parameters are org-wide, and tests running side by side contend for the same row.
    try {
      if (!Test.isRunningTest())
        System.enqueueJob(
          new AILicenceUsageReporter(
            monthMessages.intValue(),
            monthFailedTurns.intValue()
          )
        );
    } catch (Exception notQueued) {
      AIPlatformLogManager.logException(
        notQueued,
        'AIOrgUsageTotalsBatch',
        'finish'
      );
    }
  }
}
