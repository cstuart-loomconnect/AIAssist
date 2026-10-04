/*
Class Name: AIViolationService

=================================================================
=================================================================

Description: Records violations of the rules an administrator set up (AIViolationRule__c), in the two ways the
object model describes.

Deterministic - Apex: the package already knows the condition (a usage limit reached, a record the
user may not read, an action they may not run, masking that failed). The code that refuses calls
raise with the violation type, and a violation is recorded for each active deterministic rule of the
agent that produces that type. With no such rule, nothing is recorded.

AI Evaluated: for conditions only the model can judge. The rule's instruction is added to the system
prompt (promptInstructions) with its signal tag, and the model is asked to put that exact tag on a line
of its own in the reply if the condition is met. inspectReply looks for the exact tag and nothing
else: the model's free-text explanation is never trusted. The tag is removed from the reply, and when
the rule blocks requests the reply is withheld.

Every violation is recorded in system mode through the package gateway, counted on the user's daily
usage row, and announced on AIViolationEvent__e (published immediately, so it survives a rollback).
The detail names the rule and never repeats the user's message or the reply.

AI evaluated rules need the plan to include them; without it they are not added to the prompt and no
tag is looked for. At most MAX_AI_RULES_PER_AGENT rules are used for one agent.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development. The violation detection the object model describes, which the old code did not have.
*/

public inherited sharing class AIViolationService {
  // What looking at a reply found.
  public class Inspection {
    public String replyText;
    public Boolean isBlocked = false;
    public Integer violationCount = 0;
  }

  // The instruction block for the system prompt, or null when there is nothing to add or the plan does not include AI evaluated rules.
  public static String buildPromptInstructions(
    List<AIViolationRule__c> aiRules
  ) {
    if (
      aiRules == null ||
      aiRules.isEmpty() ||
      !AIPlanLimitService.isAiRulesAllowed()
    )
      return null;

    List<String> lines = new List<String>{
      'If the user\'s request meets any condition below, do not carry it out, and put the exact tag on a line of its own at the end of your reply:'
    };

    for (AIViolationRule__c rule : aiRules) {
      if (
        String.isNotBlank(rule.SignalTag__c) &&
        String.isNotBlank(rule.AIDetectionInstruction__c)
      )
        lines.add(rule.SignalTag__c + ': ' + rule.AIDetectionInstruction__c);
    }

    return lines.size() == 1 ? null : String.join(lines, '\n');
  }

  // The rules a turn will be checked against: empty when the plan does not include AI evaluated rules.
  public static List<AIViolationRule__c> loadActiveAiRules(Id agentId) {
    return AIPlanLimitService.isAiRulesAllowed()
      ? AIMessagingSelector.getActiveAiEvaluatedRules(agentId)
      : new List<AIViolationRule__c>();
  }

  // Looks for each rule's exact signal tag in the reply. Returns the reply without the tags and whether a blocking rule fired. Records a violation for each rule that fired. Never throws.
  public static Inspection checkReplyForSignalTags(
    AIMessageOutcomeService.AIResponseContext responseContext,
    String replyText
  ) {
    Inspection inspection = new Inspection();
    inspection.replyText = replyText;

    try {
      if (
        responseContext == null ||
        responseContext.aiRules == null ||
        responseContext.aiRules.isEmpty() ||
        String.isBlank(replyText) ||
        !AIPlanLimitService.isAiRulesAllowed()
      )
        return inspection;

      List<AIViolationRule__c> firedRules = new List<AIViolationRule__c>();

      for (AIViolationRule__c rule : responseContext.aiRules) {
        if (String.isBlank(rule.SignalTag__c))
          continue;

        // The tag only counts as a whole token, so a longer tag that contains this one does not fire it.
        Pattern tagPattern = Pattern.compile(
          '(?<![A-Z0-9_])' + Pattern.quote(rule.SignalTag__c) + '(?![A-Z0-9_])'
        );

        if (tagPattern.matcher(inspection.replyText).find()) {
          firedRules.add(rule);
          inspection.replyText = tagPattern.matcher(inspection.replyText)
            .replaceAll('');
        }
      }

      if (firedRules.isEmpty())
        return inspection;

      inspection.replyText = inspection.replyText.replaceAll('[ \\t]+\\n', '\n')
        .trim();

      for (AIViolationRule__c firedRule : firedRules) {
        if (firedRule.BlockRequest__c == true)
          inspection.isBlocked = true;
      }

      // One violation per rule, one usage count for them all, and one event each. A violation is blocked when its own rule blocks. Detail names the rule only.
      List<AIViolation__c> violations = new List<AIViolation__c>();
      List<AIViolationEvent__e> violationEvents = new List<AIViolationEvent__e>();

      for (AIViolationRule__c firedRule : firedRules) {
        String severity = firedRule.BlockRequest__c == true ||
          firedRule.ViolationTypeProduced__c !=
          AIAssistApplicationConstants.VIOLATION_TYPE_AI_FLAGGED_INTENT &&
          firedRule.ViolationTypeProduced__c !=
          AIAssistApplicationConstants.VIOLATION_TYPE_USAGE_LIMIT_EXCEEDED
          ? AIAssistApplicationConstants.SEVERITY_HIGH
          : firedRule.ViolationTypeProduced__c ==
              AIAssistApplicationConstants.VIOLATION_TYPE_USAGE_LIMIT_EXCEEDED
              ? AIAssistApplicationConstants.SEVERITY_LOW
              : AIAssistApplicationConstants.SEVERITY_MEDIUM;
        String detail = ('Rule "' +
          firedRule.Name +
          '" fired.')
          .left(AIAssistApplicationConstants.VIOLATION_DETAIL_LENGTH);

        violations.add(
          new AIViolation__c(
            AIViolationRule__c = firedRule.Id,
            ViolationType__c = firedRule.ViolationTypeProduced__c,
            Severity__c = severity,
            ReviewStatus__c = AIAssistApplicationConstants.REVIEW_STATUS_NEW,
            RequestBlocked__c = firedRule.BlockRequest__c == true,
            User__c = responseContext.userId,
            AIConversation__c = responseContext.conversationId,
            AIConversationMessage__c = responseContext.triggeringMessageId,
            Detail__c = detail
          )
        );

        violationEvents.add(
          new AIViolationEvent__e(
            ViolationRuleId__c = firedRule.Id,
            ViolationType__c = firedRule.ViolationTypeProduced__c,
            Severity__c = severity,
            RequestBlocked__c = firedRule.BlockRequest__c == true,
            UserId__c = responseContext.userId,
            ConversationId__c = responseContext.conversationId,
            Detail__c = detail,
            OccurredAt__c = System.now()
          )
        );
      }

      AIMessagingDataService.insertAndLogFailures(
        violations,
        'AIViolationService',
        'checkReplyForSignalTags'
      );

      if (responseContext.userId != null) {
        AIMessagingDataService.UsageDelta usageDelta = new AIMessagingDataService.UsageDelta();
        usageDelta.userId = responseContext.userId;
        usageDelta.agentId = responseContext.agentId;
        usageDelta.modelConfigurationId = responseContext.agentId == null
          ? null
          : AIMessagingSelector.getAgent(responseContext.agentId)
              ?.AIModelConfiguration__c;
        usageDelta.violations = violations.size();
        try {
          AIMessagingDataService.addToDailyUsage(usageDelta);
        } catch (Exception usageException) {
          AIPlatformLogManager.logException(
            usageException,
            'AIViolationService',
            'checkReplyForSignalTags'
          );
        }
      }

      // The record above is the evidence; the event is skipped while publishing is paused to protect the org's event allowance.
      for (
        Database.SaveResult publishResult : EventBus.publish(
          AIOrgLimitMonitor.isViolationEventAllowed()
            ? violationEvents
            : new List<AIViolationEvent__e>()
        )
      ) {
        if (!publishResult.isSuccess())
          AIPlatformLogManager.logCustomMessage(
            'AIViolationEvent__e was not published.',
            publishResult.getErrors()[0].getMessage(),
            'AIViolationService',
            'inspectReply',
            null
          );
      }

      inspection.violationCount = violations.size();
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIViolationService',
        'checkReplyForSignalTags'
      );
    }

    return inspection;
  }

  // Records a violation for each active deterministic rule of the agent that produces violationType. Returns true when one of them blocks requests. Never throws.
  public static Boolean recordDeterministicViolation(
    String violationType,
    Id agentId,
    Id userId,
    Id conversationId,
    Id messageId
  ) {
    try {
      List<AIViolationRule__c> rules = AIMessagingSelector.getActiveRulesForViolationType(
        agentId,
        violationType
      );
      if (rules.isEmpty())
        return false;

      Boolean isBlocking = false;
      for (AIViolationRule__c rule : rules) {
        if (rule.BlockRequest__c == true)
          isBlocking = true;
      }

      // One violation per rule, one usage count for them all, and one event each. A violation is blocked when its own rule blocks. Detail names the rule only.
      List<AIViolation__c> violations = new List<AIViolation__c>();
      List<AIViolationEvent__e> violationEvents = new List<AIViolationEvent__e>();

      for (AIViolationRule__c rule : rules) {
        String severity = rule.BlockRequest__c == true ||
          rule.ViolationTypeProduced__c !=
          AIAssistApplicationConstants.VIOLATION_TYPE_AI_FLAGGED_INTENT &&
          rule.ViolationTypeProduced__c !=
          AIAssistApplicationConstants.VIOLATION_TYPE_USAGE_LIMIT_EXCEEDED
          ? AIAssistApplicationConstants.SEVERITY_HIGH
          : rule.ViolationTypeProduced__c ==
              AIAssistApplicationConstants.VIOLATION_TYPE_USAGE_LIMIT_EXCEEDED
              ? AIAssistApplicationConstants.SEVERITY_LOW
              : AIAssistApplicationConstants.SEVERITY_MEDIUM;
        String detail = ('Rule "' +
          rule.Name +
          '" fired.')
          .left(AIAssistApplicationConstants.VIOLATION_DETAIL_LENGTH);

        violations.add(
          new AIViolation__c(
            AIViolationRule__c = rule.Id,
            ViolationType__c = rule.ViolationTypeProduced__c,
            Severity__c = severity,
            ReviewStatus__c = AIAssistApplicationConstants.REVIEW_STATUS_NEW,
            RequestBlocked__c = rule.BlockRequest__c == true,
            User__c = userId,
            AIConversation__c = conversationId,
            AIConversationMessage__c = messageId,
            Detail__c = detail
          )
        );

        violationEvents.add(
          new AIViolationEvent__e(
            ViolationRuleId__c = rule.Id,
            ViolationType__c = rule.ViolationTypeProduced__c,
            Severity__c = severity,
            RequestBlocked__c = rule.BlockRequest__c == true,
            UserId__c = userId,
            ConversationId__c = conversationId,
            Detail__c = detail,
            OccurredAt__c = System.now()
          )
        );
      }

      AIMessagingDataService.insertAndLogFailures(
        violations,
        'AIViolationService',
        'recordDeterministicViolation'
      );

      if (userId != null) {
        AIMessagingDataService.UsageDelta usageDelta = new AIMessagingDataService.UsageDelta();
        usageDelta.userId = userId;
        usageDelta.agentId = agentId;
        usageDelta.modelConfigurationId = agentId == null
          ? null
          : AIMessagingSelector.getAgent(agentId)?.AIModelConfiguration__c;
        usageDelta.violations = violations.size();
        try {
          AIMessagingDataService.addToDailyUsage(usageDelta);
        } catch (Exception usageException) {
          AIPlatformLogManager.logException(
            usageException,
            'AIViolationService',
            'recordDeterministicViolation'
          );
        }
      }

      // The record above is the evidence; the event is skipped while publishing is paused to protect the org's event allowance.
      for (
        Database.SaveResult publishResult : EventBus.publish(
          AIOrgLimitMonitor.isViolationEventAllowed()
            ? violationEvents
            : new List<AIViolationEvent__e>()
        )
      ) {
        if (!publishResult.isSuccess())
          AIPlatformLogManager.logCustomMessage(
            'AIViolationEvent__e was not published.',
            publishResult.getErrors()[0].getMessage(),
            'AIViolationService',
            'raise',
            null
          );
      }

      return isBlocking;
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIViolationService',
        'recordDeterministicViolation'
      );
      return false;
    }
  }
}
