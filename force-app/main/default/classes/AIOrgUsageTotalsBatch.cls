/*
Class Name: AIOrgUsageTotalsBatch

=================================================================
=================================================================

Description: Counts the organisation's usage for the current month and day exactly, from the
AIUsageDaily__c rows, and stores the result through AIOrgUsageService. Run by the maintenance job. A
batch because a month of usage rows can be more than one transaction may read; the running totals are
carried between chunks (Database.Stateful).

Runs whether or not the application is switched on, and in system mode: usage rows belong to every user.
A turn that ends while the batch runs may be missed by this count; the next run includes it.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public inherited sharing class AIOrgUsageTotalsBatch implements Database.Batchable<SObject>, Database.Stateful {
  private Date today = Datetime.now().dateGmt();
  private AIMessagingSelector.OrgUsage counted = new AIMessagingSelector.OrgUsage();

  public Database.QueryLocator start(Database.BatchableContext context) {
    Date monthStart = today.toStartOfMonth();

    return Database.getQueryLocator(
      [
        SELECT UsageDate__c, MessageCount__c, InputTokens__c, OutputTokens__c
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

      counted.month.messages += messages;
      counted.month.tokens += tokens;
      if (usageRow.UsageDate__c == today) {
        counted.today.messages += messages;
        counted.today.tokens += tokens;
      }
    }
  }

  public void finish(Database.BatchableContext context) {
    AIOrgUsageService.replace(today, counted);
  }
}
