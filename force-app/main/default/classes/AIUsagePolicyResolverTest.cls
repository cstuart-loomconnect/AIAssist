/*
Class Name: AIUsagePolicyResolverTest

=================================================================
=================================================================

Description: Testing utility for AIUsagePolicyResolver: how a user's own settings row and the usage policies that apply to them combine into what they are allowed.

=================================================================
=================================================================
Applicable Classes:

AIUsagePolicyResolver

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIUsagePolicyResolverTest {
  // testScenario1: With no row and no policy the answer is null; an inactive row counts as no row.
  // testScenario2: With policies only, limits take the lowest value, the behavior that blocks most, and the widest visibility.
  // testScenario3: Capabilities add up: a flag, or a channel, allowed by any policy is allowed, and a policy with no channels opens every channel.
  // testScenario4: The user row overrides a policy where it has a value, and falls through to the policies where it is blank.
  // testScenario5: A user row can switch a capability on, but cannot switch off one a policy grants.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  private static AIUsagePolicy__c policy(
    Decimal concurrent,
    Decimal perDay,
    Decimal tokens,
    String behavior
  ) {
    return new AIUsagePolicy__c(
      MaxConcurrentConversations__c = concurrent,
      MaxConversationsPer24Hours__c = perDay,
      MaxTokensPer24Hours__c = tokens,
      UsageLimitReachedBehavior__c = behavior
    );
  }

  @IsTest
  static void testScenario1() {
    Test.startTest();
    AIUserSettings__c nothing = AIUsagePolicyResolver.resolve(null, null);
    AIUserSettings__c emptyList = AIUsagePolicyResolver.resolve(
      null,
      new List<AIUsagePolicy__c>()
    );
    AIUserSettings__c inactiveRow = AIUsagePolicyResolver.resolve(
      new AIUserSettings__c(IsActive__c = false, DebugModeEnabled__c = true),
      null
    );
    Test.stopTest();

    Assert.isNull(nothing, 'No row and no policy means no personal limits.');
    Assert.isNull(emptyList, 'An empty list is the same.');
    Assert.isNull(inactiveRow, 'An inactive row is ignored.');
  }

  @IsTest
  static void testScenario2() {
    AIUsagePolicy__c loose = policy(
      5,
      100,
      500000,
      AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY
    );
    loose.ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN;
    AIUsagePolicy__c strict = policy(
      2,
      null,
      100000,
      AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES
    );
    strict.ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL;
    AIUsagePolicy__c middle = policy(
      null,
      20,
      null,
      AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY
    );

    Test.startTest();
    AIUserSettings__c resolved = AIUsagePolicyResolver.resolve(
      null,
      new List<AIUsagePolicy__c>{ loose, strict, middle }
    );
    Test.stopTest();

    Assert.areEqual(2, resolved.MaxConcurrentConversations__c, 'The lowest.');
    Assert.areEqual(
      20,
      resolved.MaxConversationsPer24Hours__c,
      'The lowest that is set; a blank limit sets nothing.'
    );
    Assert.areEqual(100000, resolved.MaxTokensPer24Hours__c, 'The lowest.');
    Assert.areEqual(
      AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES,
      resolved.UsageLimitReachedBehavior__c,
      'The behavior that blocks most.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL,
      resolved.ConversationVisibilityScope__c,
      'The widest scope.'
    );
    Assert.isTrue(resolved.IsActive__c, 'The answer is always active.');
  }

  @IsTest
  static void testScenario3() {
    AIUsagePolicy__c first = new AIUsagePolicy__c(
      AllowedChannels__c = AIAssistApplicationConstants.CHANNEL_MOBILE,
      WorkflowActionsEnabled__c = true
    );
    AIUsagePolicy__c second = new AIUsagePolicy__c(
      AllowedChannels__c = AIAssistApplicationConstants.CHANNEL_UTILITY_BAR,
      DebugModeEnabled__c = true
    );
    AIUsagePolicy__c unrestricted = new AIUsagePolicy__c(
      ConversationExportEnabled__c = true
    );

    Test.startTest();
    AIUserSettings__c both = AIUsagePolicyResolver.resolve(
      null,
      new List<AIUsagePolicy__c>{ first, second }
    );
    AIUserSettings__c open = AIUsagePolicyResolver.resolve(
      null,
      new List<AIUsagePolicy__c>{ first, unrestricted }
    );
    Test.stopTest();

    Set<String> channels = new Set<String>(both.AllowedChannels__c.split(';'));
    Assert.isTrue(
      channels.contains(AIAssistApplicationConstants.CHANNEL_MOBILE) &&
      channels.contains(AIAssistApplicationConstants.CHANNEL_UTILITY_BAR),
      'Channels allowed by either policy.'
    );
    Assert.isTrue(both.WorkflowActionsEnabled__c, 'Granted by the first.');
    Assert.isTrue(both.DebugModeEnabled__c, 'Granted by the second.');
    Assert.isFalse(both.ConversationExportEnabled__c, 'Granted by neither.');
    Assert.isNull(
      open.AllowedChannels__c,
      'A policy with no list allows every channel.'
    );
    Assert.isTrue(open.ConversationExportEnabled__c, 'Granted by that policy.');
  }

  @IsTest
  static void testScenario4() {
    AIUsagePolicy__c groupPolicy = policy(
      3,
      50,
      200000,
      AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES
    );
    AIUserSettings__c row = new AIUserSettings__c(
      IsActive__c = true,
      MaxTokensPer24Hours__c = 900000,
      UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY
    );

    Test.startTest();
    AIUserSettings__c resolved = AIUsagePolicyResolver.resolve(
      row,
      new List<AIUsagePolicy__c>{ groupPolicy }
    );
    Test.stopTest();

    Assert.areEqual(
      900000,
      resolved.MaxTokensPer24Hours__c,
      'The user\'s own value wins, even where it is higher.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY,
      resolved.UsageLimitReachedBehavior__c,
      'The user\'s own behavior wins.'
    );
    Assert.areEqual(
      3,
      resolved.MaxConcurrentConversations__c,
      'Blank on the row, so taken from the policy.'
    );
    Assert.areEqual(
      50,
      resolved.MaxConversationsPer24Hours__c,
      'Blank on the row, so taken from the policy.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIUsagePolicy__c grants = new AIUsagePolicy__c(
      DebugModeEnabled__c = true,
      WorkflowActionsEnabled__c = true
    );
    AIUserSettings__c row = new AIUserSettings__c(
      IsActive__c = true,
      DebugModeEnabled__c = false,
      ConversationExportEnabled__c = true
    );

    Test.startTest();
    AIUserSettings__c resolved = AIUsagePolicyResolver.resolve(
      row,
      new List<AIUsagePolicy__c>{ grants }
    );
    Test.stopTest();

    Assert.isTrue(
      resolved.DebugModeEnabled__c,
      'An unticked box on the row does not take away what the policy grants.'
    );
    Assert.isTrue(
      resolved.ConversationExportEnabled__c,
      'A ticked box on the row switches it on for that user.'
    );
    Assert.isTrue(resolved.WorkflowActionsEnabled__c, 'From the policy.');
  }
}
