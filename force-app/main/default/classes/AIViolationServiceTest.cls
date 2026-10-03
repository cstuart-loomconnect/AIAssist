/*
Class Name: AIViolationServiceTest

=================================================================
=================================================================

Description: Testing utility for AIViolationService: the instructions added to the prompt, the exact signal tags looked for in a reply, and the deterministic violations other classes raise.

=================================================================
=================================================================
Applicable Classes:

AIViolationService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIViolationServiceTest {
  // testScenario1: promptInstructions lists each rule's tag and instruction, and is null for no rules or a plan without AI evaluated rules.
  // testScenario2: A tag in the reply records a violation, takes the tag out of the reply, and names the rule in the detail without repeating any content.
  // testScenario3: A blocking rule withholds the reply and records a High severity violation with Request Blocked.
  // testScenario4: Only the exact tag counts: a longer tag that contains it, a different case and a tag inside another word do not fire.
  // testScenario5: A reply with no tag, no reply, no rules, no turn, or a plan without AI rules records nothing.
  // testScenario6: raise records a violation for each active deterministic rule of that type on the agent, and says whether one blocks.
  // testScenario7: Violations are counted on the user's daily usage row for the agent.
  // testScenario8: loadAiRules returns the agent's active AI evaluated rules up to the cap, and none without the plan.
  // testScenario9: Bulk: every rule up to the cap fires from one reply, in one insert.

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
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
    AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
    responseContext.conversationId = conversation.Id;
    responseContext.triggeringMessageId = question.Id;
    responseContext.userId = chatUser.Id;
    responseContext.agentId = agent.Id;
    List<AIViolationRule__c> rules = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      2,
      AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED,
      true
    );
    String withPlan;
    String noRules;
    String withoutPlan;

    Test.startTest();
    withPlan = AIViolationService.buildPromptInstructions(rules);
    noRules = AIViolationService.buildPromptInstructions(
      new List<AIViolationRule__c>()
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      false
    );
    withoutPlan = AIViolationService.buildPromptInstructions(rules);
    Test.stopTest();

    Assert.isTrue(
      withPlan.contains(
        rules[0].SignalTag__c + ': ' + rules[0].AIDetectionInstruction__c
      ) && withPlan.contains(rules[1].SignalTag__c),
      'Both rules are in the prompt.'
    );
    Assert.isNull(noRules, 'Nothing to add.');
    Assert.isNull(withoutPlan, 'The plan does not include them.');
  }

  @IsTest
  static void testScenario2() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
    AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
    responseContext.conversationId = conversation.Id;
    responseContext.triggeringMessageId = question.Id;
    responseContext.userId = chatUser.Id;
    responseContext.agentId = agent.Id;
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED,
      true
    )[0];
    responseContext.aiRules = new List<AIViolationRule__c>{ rule };
    AIViolationService.Inspection inspection;

    Test.startTest();
    inspection = AIViolationService.checkReplyForSignalTags(
      responseContext,
      'I cannot help with that.\n' + rule.SignalTag__c
    );
    Test.stopTest();

    AIViolation__c violation = [
      SELECT
        ViolationType__c,
        Severity__c,
        ReviewStatus__c,
        RequestBlocked__c,
        User__c,
        AIConversation__c,
        AIConversationMessage__c,
        Detail__c
      FROM AIViolation__c
      WHERE AIViolationRule__c = :rule.Id
    ];
    Assert.areEqual(
      'I cannot help with that.',
      inspection.replyText,
      'The tag is removed.'
    );
    Assert.isFalse(inspection.isBlocked, 'This rule does not block.');
    Assert.areEqual(1, inspection.violationCount, 'One violation.');
    Assert.areEqual(
      AIAssistApplicationConstants.VIOLATION_TYPE_AI_FLAGGED_INTENT,
      violation.ViolationType__c,
      'The rule\'s type.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.SEVERITY_MEDIUM,
      violation.Severity__c,
      'Medium for flagged intent.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.REVIEW_STATUS_NEW,
      violation.ReviewStatus__c,
      'New until reviewed.'
    );
    Assert.areEqual(chatUser.Id, violation.User__c, 'The user.');
    Assert.areEqual(
      question.Id,
      violation.AIConversationMessage__c,
      'The message that caused it.'
    );
    Assert.isTrue(
      violation.Detail__c.contains(rule.Name) &&
      !violation.Detail__c.contains('cannot help'),
      'The rule, not the content.'
    );
  }

  @IsTest
  static void testScenario3() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
    AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
    responseContext.conversationId = conversation.Id;
    responseContext.triggeringMessageId = question.Id;
    responseContext.userId = chatUser.Id;
    responseContext.agentId = agent.Id;
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED,
      false
    )[0];
    rule.BlockRequest__c = true;
    insert rule;
    AIAssistTestDataFactory.createAIAgentViolationRules(
      agent.Id,
      new List<AIViolationRule__c>{ rule },
      true
    );
    responseContext.aiRules = new List<AIViolationRule__c>{ rule };
    AIViolationService.Inspection inspection;

    Test.startTest();
    inspection = AIViolationService.checkReplyForSignalTags(
      responseContext,
      rule.SignalTag__c
    );
    Test.stopTest();

    AIViolation__c violation = [
      SELECT Severity__c, RequestBlocked__c
      FROM AIViolation__c
      WHERE AIViolationRule__c = :rule.Id
    ];
    Assert.isTrue(inspection.isBlocked, 'Blocked.');
    Assert.areEqual(
      AIAssistApplicationConstants.SEVERITY_HIGH,
      violation.Severity__c,
      'High.'
    );
    Assert.isTrue(violation.RequestBlocked__c, 'Recorded as blocked.');
  }

  @IsTest
  static void testScenario4() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
    AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
    responseContext.conversationId = conversation.Id;
    responseContext.triggeringMessageId = question.Id;
    responseContext.userId = chatUser.Id;
    responseContext.agentId = agent.Id;
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED,
      false
    )[0];
    rule.SignalTag__c = 'EXPORT';
    insert rule;
    AIAssistTestDataFactory.createAIAgentViolationRules(
      agent.Id,
      new List<AIViolationRule__c>{ rule },
      true
    );
    responseContext.aiRules = new List<AIViolationRule__c>{ rule };
    List<Integer> counts = new List<Integer>();

    Test.startTest();
    for (
      String reply : new List<String>{
        'EXPORT_ALL',
        'export',
        'MYEXPORT',
        'PREEXPORT_X',
        'Here is EXPORT.'
      }
    )
      counts.add(
        AIViolationService.checkReplyForSignalTags(responseContext, reply)
          .violationCount
      );
    Test.stopTest();

    Assert.areEqual(
      new List<Integer>{ 0, 0, 0, 0, 1 },
      counts,
      'Only a whole, exact tag fires.'
    );
  }

  @IsTest
  static void testScenario5() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
    AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
    responseContext.conversationId = conversation.Id;
    responseContext.triggeringMessageId = question.Id;
    responseContext.userId = chatUser.Id;
    responseContext.agentId = agent.Id;
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED,
      true
    )[0];
    responseContext.aiRules = new List<AIViolationRule__c>{ rule };

    Test.startTest();
    AIViolationService.checkReplyForSignalTags(
      responseContext,
      'A normal answer.'
    );
    AIViolationService.checkReplyForSignalTags(responseContext, null);
    AIViolationService.checkReplyForSignalTags(null, rule.SignalTag__c);
    responseContext.aiRules = null;
    AIViolationService.checkReplyForSignalTags(
      responseContext,
      rule.SignalTag__c
    );
    responseContext.aiRules = new List<AIViolationRule__c>{ rule };
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      false
    );
    AIViolationService.checkReplyForSignalTags(
      responseContext,
      rule.SignalTag__c
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIViolation__c],
      'Nothing was recorded.'
    );
  }

  @IsTest
  static void testScenario6() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
    AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
    responseContext.conversationId = conversation.Id;
    responseContext.triggeringMessageId = question.Id;
    responseContext.userId = chatUser.Id;
    responseContext.agentId = agent.Id;
    List<AIViolationRule__c> rules = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      3,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      false
    );
    for (AIViolationRule__c rule : rules)
      rule.ViolationTypeProduced__c = AIAssistApplicationConstants.VIOLATION_TYPE_USAGE_LIMIT_EXCEEDED;
    rules[1].BlockRequest__c = true;
    rules[2].IsActive__c = false;
    insert rules;
    AIAssistTestDataFactory.createAIAgentViolationRules(agent.Id, rules, true);
    AIAgent__c otherAgent = AIAssistTestDataFactory.createAIAgents(
      1,
      agent.AIModelConfiguration__c,
      true
    )[0];
    AIViolationRule__c otherRule = AIAssistTestDataFactory.createAIViolationRules(
      otherAgent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      false
    )[0];
    otherRule.ViolationTypeProduced__c = AIAssistApplicationConstants.VIOLATION_TYPE_USAGE_LIMIT_EXCEEDED;
    insert otherRule;
    AIAssistTestDataFactory.createAIAgentViolationRules(
      otherAgent.Id,
      new List<AIViolationRule__c>{ otherRule },
      true
    );
    Boolean isBlocking;
    Boolean noRule;

    Test.startTest();
    isBlocking = AIViolationService.recordDeterministicViolation(
      AIAssistApplicationConstants.VIOLATION_TYPE_USAGE_LIMIT_EXCEEDED,
      agent.Id,
      chatUser.Id,
      conversation.Id,
      question.Id
    );
    noRule = AIViolationService.recordDeterministicViolation(
      AIAssistApplicationConstants.VIOLATION_TYPE_PII_MASKING_FAILURE,
      agent.Id,
      chatUser.Id,
      conversation.Id,
      question.Id
    );
    Test.stopTest();

    Assert.isTrue(isBlocking, 'One of the two active rules blocks.');
    Assert.isFalse(noRule, 'No rule for that type.');
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM AIViolation__c],
      'The two active rules of this agent; not the inactive one and not another agent\'s.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.SEVERITY_LOW,
      [SELECT Severity__c FROM AIViolation__c WHERE RequestBlocked__c = FALSE]
      .Severity__c,
      'A usage limit that does not block is Low.'
    );
  }

  @IsTest
  static void testScenario7() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
    AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
    responseContext.conversationId = conversation.Id;
    responseContext.triggeringMessageId = question.Id;
    responseContext.userId = chatUser.Id;
    responseContext.agentId = agent.Id;
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      false
    )[0];
    rule.ViolationTypeProduced__c = AIAssistApplicationConstants.VIOLATION_TYPE_PII_MASKING_FAILURE;
    insert rule;
    AIAssistTestDataFactory.createAIAgentViolationRules(
      agent.Id,
      new List<AIViolationRule__c>{ rule },
      true
    );

    Test.startTest();
    AIViolationService.recordDeterministicViolation(
      AIAssistApplicationConstants.VIOLATION_TYPE_PII_MASKING_FAILURE,
      agent.Id,
      chatUser.Id,
      conversation.Id,
      question.Id
    );
    AIViolationService.recordDeterministicViolation(
      AIAssistApplicationConstants.VIOLATION_TYPE_PII_MASKING_FAILURE,
      agent.Id,
      chatUser.Id,
      conversation.Id,
      question.Id
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      [
        SELECT ViolationCount__c
        FROM AIUsageDaily__c
        WHERE User__c = :chatUser.Id
      ]
      .ViolationCount__c,
      'Two violations today.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.SEVERITY_HIGH,
      [SELECT Severity__c FROM AIViolation__c LIMIT 1].Severity__c,
      'Masking failures are High.'
    );
  }

  @IsTest
  static void testScenario8() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
    AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
    responseContext.conversationId = conversation.Id;
    responseContext.triggeringMessageId = question.Id;
    responseContext.userId = chatUser.Id;
    responseContext.agentId = agent.Id;
    Integer tooMany = AIAssistApplicationConstants.MAX_AI_RULES_PER_AGENT + 3;
    AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      tooMany,
      AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED,
      true
    );
    AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      2,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      true
    );
    Integer withPlan;
    Integer withoutPlan;

    Test.startTest();
    withPlan = AIViolationService.loadActiveAiRules(agent.Id).size();
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      false
    );
    withoutPlan = AIViolationService.loadActiveAiRules(agent.Id).size();
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.MAX_AI_RULES_PER_AGENT,
      withPlan,
      'Capped, and deterministic rules are not included.'
    );
    Assert.areEqual(0, withoutPlan, 'None without the plan.');
  }

  @IsTest
  static void testScenario9() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
    AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
    responseContext.conversationId = conversation.Id;
    responseContext.triggeringMessageId = question.Id;
    responseContext.userId = chatUser.Id;
    responseContext.agentId = agent.Id;
    Integer ruleCount = AIAssistApplicationConstants.MAX_AI_RULES_PER_AGENT;
    List<AIViolationRule__c> rules = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      ruleCount,
      AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED,
      true
    );
    responseContext.aiRules = rules;
    List<String> tags = new List<String>();
    for (AIViolationRule__c rule : rules)
      tags.add(rule.SignalTag__c);
    Integer statements;
    Integer fired;

    Test.startTest();
    fired = AIViolationService.checkReplyForSignalTags(
        responseContext,
        String.join(tags, '\n')
      )
      .violationCount;
    statements = Limits.getDmlStatements();
    Test.stopTest();

    Assert.areEqual(ruleCount, fired, 'All fired.');
    Assert.areEqual(
      ruleCount,
      [SELECT COUNT() FROM AIViolation__c],
      'All recorded.'
    );
    Assert.isTrue(
      statements <= 4,
      'The violations are one insert, plus the usage row: ' + statements
    );
  }
}
