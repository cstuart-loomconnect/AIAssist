/*
Class Name: AIChatUsageServiceTest

=================================================================
=================================================================

Description: Testing utility for AIChatUsageService: the usage meter and the three limit behaviours.

=================================================================
=================================================================
Applicable Classes:

AIChatUsageService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIChatUsageServiceTest {
  // testScenario1: Tokens used today come from the daily usage rows, with no limits when the user has no settings.
  // testScenario2: Block New Messages blocks messages at the token limit and new conversations at any limit.
  // testScenario3: Block New Conversations Only blocks only new conversations, and Notify Only only notifies.
  // testScenario4: The conversation and concurrent limits are counted, and an inactive settings row applies no limits.

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
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIUsageDaily__c row = AIAssistTestDataFactory.createAIUsageDailies(
      UserInfo.getUserId(),
      agent.Id,
      agent.AIModelConfiguration__c,
      1,
      false
    )[0];
    row.InputTokens__c = 70;
    row.OutputTokens__c = 30;
    insert row;

    Test.startTest();
    AIChatDataStructure.UsageState usage = AIChatUsageService.buildUsageState(
      null
    );
    Test.stopTest();

    Assert.areEqual(100, usage.tokensUsed, 'Input plus output.');
    Assert.isNull(usage.tokenLimit, 'No limit.');
    Assert.isFalse(usage.limitReached, 'Not reached.');
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(
      UserInfo.getUserId(),
      false
    )[0];
    settings.MaxTokensPer24Hours__c = 100;
    settings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES;
    AIUsageDaily__c row = AIAssistTestDataFactory.createAIUsageDailies(
      UserInfo.getUserId(),
      agent.Id,
      agent.AIModelConfiguration__c,
      1,
      false
    )[0];
    row.InputTokens__c = 100;
    insert row;

    Test.startTest();
    AIChatDataStructure.UsageState usage = AIChatUsageService.buildUsageState(
      settings
    );
    Test.stopTest();

    Assert.isTrue(
      usage.blockMessages && usage.blockNewConversations && usage.limitReached,
      'Blocked.'
    );
    Assert.isNotNull(usage.resetsInMinutes, 'With a reset time.');
    Assert.isTrue(
      usage.resetsInMinutes >= 1 && usage.resetsInMinutes <= 1440,
      'Within a day.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIUserSettings__c blockNew = AIAssistTestDataFactory.createAIUserSettings(
      UserInfo.getUserId(),
      false
    )[0];
    blockNew.MaxTokensPer24Hours__c = 10;
    blockNew.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY;
    AIUserSettings__c notify = new AIUserSettings__c(
      IsActive__c = true,
      MaxTokensPer24Hours__c = 10,
      UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY
    );
    AIUsageDaily__c row = AIAssistTestDataFactory.createAIUsageDailies(
      UserInfo.getUserId(),
      agent.Id,
      agent.AIModelConfiguration__c,
      1,
      false
    )[0];
    row.InputTokens__c = 50;
    insert row;

    Test.startTest();
    AIChatDataStructure.UsageState first = AIChatUsageService.buildUsageState(
      blockNew
    );
    AIChatDataStructure.UsageState second = AIChatUsageService.buildUsageState(
      notify
    );
    Test.stopTest();

    Assert.isTrue(
      first.blockNewConversations && !first.blockMessages,
      'Only new conversations.'
    );
    Assert.isTrue(
      second.notifyOnly &&
        !second.blockMessages &&
        !second.blockNewConversations,
      'Notify only.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(
      UserInfo.getUserId(),
      false
    )[0];
    settings.MaxConcurrentConversations__c = 1;
    settings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY;
    AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      UserInfo.getUserId(),
      1,
      true
    );
    AIChatDataStructure.UsageState inactive;
    AIChatDataStructure.UsageState active;

    Test.startTest();
    active = AIChatUsageService.buildUsageState(settings);
    settings.IsActive__c = false;
    inactive = AIChatUsageService.buildUsageState(settings);
    Test.stopTest();

    Assert.isTrue(
      active.blockNewConversations,
      'One active conversation reaches the limit of one.'
    );
    Assert.isFalse(inactive.limitReached, 'An inactive row applies nothing.');
  }
}
