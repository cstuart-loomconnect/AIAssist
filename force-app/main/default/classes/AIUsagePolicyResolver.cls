/*
Class Name: AIUsagePolicyResolver

=================================================================
=================================================================

Description: Works out what one user is allowed, from the usage policies that apply to them and their own
AIUserSettings__c row. It is plain logic with no queries; AIMessagingSelector.getUserSettings finds the
policies and the row and passes them in.

The answer is an AIUserSettings__c that is never saved, so everything that already reads a user's
settings (limits, channels, debug mode, workflow actions, visibility) carries on unchanged.

Rules:
[1] The user's own row is an override only. A limit, behavior, channel list or visibility scope left blank
    on the row is taken from the policies.
[2] Limits are strictest-wins across policies: the lowest number, and the behavior that blocks most
    (Block New Messages, then Block New Conversations Only, then Notify Only). Adding a policy can
    therefore never loosen a limit.
[3] Capabilities are additive across policies: a channel, workflow actions, export or debug mode allowed by
    any policy is allowed, and the widest conversation visibility wins. A policy with no channels listed
    allows every channel.
[4] A user's row can switch a capability on for that user. It cannot switch off a capability a policy
    grants; remove the user from that policy instead.
[5] An inactive row is ignored. With neither a row nor a policy the answer is null, which callers treat as
    "no personal limits".

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public inherited sharing class AIUsagePolicyResolver {
  public static AIUserSettings__c resolve(
    AIUserSettings__c userRow,
    List<AIUsagePolicy__c> policies
  ) {
    AIUserSettings__c personalRow = userRow != null &&
      userRow.IsActive__c == true
      ? userRow
      : null;
    List<AIUsagePolicy__c> applicable = policies == null
      ? new List<AIUsagePolicy__c>()
      : policies;

    if (personalRow == null && applicable.isEmpty())
      return null;

    AIUserSettings__c resolved = new AIUserSettings__c(
      Id = personalRow?.Id,
      User__c = personalRow?.User__c,
      IsActive__c = true
    );

    resolved.MaxConcurrentConversations__c = personalRow
        ?.MaxConcurrentConversations__c != null
      ? personalRow.MaxConcurrentConversations__c
      : lowest(applicable, AIUsagePolicy__c.MaxConcurrentConversations__c);
    resolved.MaxConversationsPer24Hours__c = personalRow
        ?.MaxConversationsPer24Hours__c != null
      ? personalRow.MaxConversationsPer24Hours__c
      : lowest(applicable, AIUsagePolicy__c.MaxConversationsPer24Hours__c);
    resolved.MaxTokensPer24Hours__c = personalRow?.MaxTokensPer24Hours__c !=
      null
      ? personalRow.MaxTokensPer24Hours__c
      : lowest(applicable, AIUsagePolicy__c.MaxTokensPer24Hours__c);

    resolved.UsageLimitReachedBehavior__c = String.isNotBlank(
        personalRow?.UsageLimitReachedBehavior__c
      )
      ? personalRow.UsageLimitReachedBehavior__c
      : strictestBehavior(applicable);
    resolved.ConversationVisibilityScope__c = String.isNotBlank(
        personalRow?.ConversationVisibilityScope__c
      )
      ? personalRow.ConversationVisibilityScope__c
      : widestVisibility(applicable);
    resolved.AllowedChannels__c = String.isNotBlank(
        personalRow?.AllowedChannels__c
      )
      ? personalRow.AllowedChannels__c
      : channelsAllowedByAny(applicable);

    resolved.WorkflowActionsEnabled__c =
      personalRow?.WorkflowActionsEnabled__c == true ||
      anyChecked(applicable, AIUsagePolicy__c.WorkflowActionsEnabled__c);
    resolved.ConversationExportEnabled__c =
      personalRow?.ConversationExportEnabled__c == true ||
      anyChecked(applicable, AIUsagePolicy__c.ConversationExportEnabled__c);
    resolved.DebugModeEnabled__c =
      personalRow?.DebugModeEnabled__c == true ||
      anyChecked(applicable, AIUsagePolicy__c.DebugModeEnabled__c);

    return resolved;
  }

  private static Decimal lowest(
    List<AIUsagePolicy__c> policies,
    Schema.SObjectField limitField
  ) {
    Decimal lowestLimit = null;
    for (AIUsagePolicy__c policy : policies) {
      Decimal limitValue = (Decimal) policy.get(limitField);
      if (
        limitValue != null && (lowestLimit == null || limitValue < lowestLimit)
      )
        lowestLimit = limitValue;
    }
    return lowestLimit;
  }

  private static Boolean anyChecked(
    List<AIUsagePolicy__c> policies,
    Schema.SObjectField flagField
  ) {
    for (AIUsagePolicy__c policy : policies) {
      if ((Boolean) policy.get(flagField) == true)
        return true;
    }
    return false;
  }

  private static Integer behaviorRank(String behavior) {
    if (behavior == AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES)
      return 3;
    if (
      behavior ==
      AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY
    )
      return 2;
    if (behavior == AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY)
      return 1;
    return 0;
  }

  private static String strictestBehavior(List<AIUsagePolicy__c> policies) {
    String strictest = null;
    for (AIUsagePolicy__c policy : policies) {
      if (
        behaviorRank(policy.UsageLimitReachedBehavior__c) >
        behaviorRank(strictest)
      )
        strictest = policy.UsageLimitReachedBehavior__c;
    }
    return strictest;
  }

  private static Integer visibilityRank(String scope) {
    if (scope == AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL)
      return 3;
    if (scope == AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES)
      return 2;
    if (scope == AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN)
      return 1;
    return 0;
  }

  private static String widestVisibility(List<AIUsagePolicy__c> policies) {
    String widest = null;
    for (AIUsagePolicy__c policy : policies) {
      if (
        visibilityRank(policy.ConversationVisibilityScope__c) >
        visibilityRank(widest)
      )
        widest = policy.ConversationVisibilityScope__c;
    }
    return widest;
  }

  // Blank means every channel, so one policy with no list opens them all; otherwise the union of the lists.
  private static String channelsAllowedByAny(List<AIUsagePolicy__c> policies) {
    Set<String> channels = new Set<String>();
    for (AIUsagePolicy__c policy : policies) {
      if (String.isBlank(policy.AllowedChannels__c))
        return null;
      channels.addAll(policy.AllowedChannels__c.split(';'));
    }
    return channels.isEmpty()
      ? null
      : String.join(new List<String>(channels), ';');
  }
}
