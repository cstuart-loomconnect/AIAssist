/*
Class Name: AIViolationRuleCapService

=================================================================
=================================================================

Description: Warns an administrator, at the moment a rule is saved or assigned, that an agent now has more AI
evaluated rules than the package will use (AIAssistApplicationConstants.MAX_AI_RULES_PER_AGENT). Rules
that apply to every agent share the limit with the rules assigned to one agent, so adding a global rule
can push an agent over without anyone touching that agent.

A trigger cannot show a warning without refusing the save, and refusing would stop a rule that is
harmless for most agents, so the warning is a Platform Log entry (an error-level entry would be
published as an event under org limit pressure, so it is a normal custom message) that names the worst
case and says what is skipped. AIMessagingSelector logs again, at run time, when a request actually
loses a rule, and keeps blocking rules first so a blocking rule is the last to be dropped.

Worst case = the active global AI evaluated rules plus the largest number assigned to any one agent. Two
queries, whatever the size of the save. A failure is logged and never stops the save.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public inherited sharing class AIViolationRuleCapService {
  // The most rules any one agent would have to load right now.
  public static Integer getBusiestAgentRuleCount() {
    Integer globalRules = [
      SELECT COUNT()
      FROM AIViolationRule__c
      WHERE
        IsActive__c = TRUE
        AND AppliesToAllAgents__c = TRUE
        AND DetectionMethod__c = :AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED
        AND SignalTag__c != NULL
      WITH SYSTEM_MODE
    ];

    Integer busiestAssigned = 0;
    for (AggregateResult agentRules : [
      SELECT AIAgent__c, COUNT(Id) total
      FROM AIAgentViolationRule__c
      WHERE
        IsActive__c = TRUE
        AND AIViolationRule__r.IsActive__c = TRUE
        AND AIViolationRule__r.AppliesToAllAgents__c = FALSE
        AND AIViolationRule__r.DetectionMethod__c = :AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED
        AND AIViolationRule__r.SignalTag__c != NULL
      WITH SYSTEM_MODE
      GROUP BY AIAgent__c
      LIMIT 2000
    ])
      busiestAssigned = Math.max(
        busiestAssigned,
        Integer.valueOf(agentRules.get('total'))
      );

    return globalRules + busiestAssigned;
  }

  // Logs when the worst case is over the limit. Returns whether it was.
  public static Boolean warnWhenOverLimit() {
    try {
      Integer cap = AIAssistApplicationConstants.MAX_AI_RULES_PER_AGENT;
      Integer busiest = getBusiestAgentRuleCount();

      if (busiest <= cap)
        return false;

      AIPlatformLogManager.logCustomMessage(
        'An agent now has ' +
          busiest +
          ' active AI evaluated violation rules; only ' +
          cap +
          ' are used for one request.',
        'Blocking rules are used first, then rules by name; the rest are skipped. Deactivate rules, or stop applying them to every agent.',
        'AIViolationRuleCapService',
        'warnWhenOverLimit',
        null
      );

      return true;
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIViolationRuleCapService',
        'warnWhenOverLimit'
      );
      return false;
    }
  }
}
