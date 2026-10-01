/*
Class Name: AITokenUsageService

=================================================================
=================================================================

Description: Token usage over a period, read from AIUsageDaily__c: one row per user, agent, model and day, which
outlives the conversations it describes. Replaces the old version that summed conversations and
disappeared when retention deleted them.

Dates are UTC calendar days and the range includes both ends. Every method returns 0, never null,
when there is no usage. Read in system mode, because only Admin and Super User can read the usage
object and the chat window's own meter needs the signed-in user's figure; callers must pass the
signed-in user's Id or an agent the caller is authorised to see.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, rebuilt on AIUsageDaily__c.
*/

public inherited sharing class AITokenUsageService {
  // Every user's tokens on every agent.
  public static Decimal getGlobalUsage(Date startDate, Date endDate) {
    if (startDate == null || endDate == null || startDate > endDate)
      throw AIMessagingException.newFailure(
        'A start date on or before an end date is required.',
        null
      );
    List<AggregateResult> usageRows = [
      SELECT SUM(InputTokens__c) inputTokens, SUM(OutputTokens__c) outputTokens
      FROM AIUsageDaily__c
      WHERE UsageDate__c >= :startDate AND UsageDate__c <= :endDate
      WITH SYSTEM_MODE
    ];
    if (usageRows.isEmpty())
      return 0; // SUM returns one row with null totals when nothing matches.
    Decimal inputTokens = (Decimal) usageRows[0].get('inputTokens');
    Decimal outputTokens = (Decimal) usageRows[0].get('outputTokens');
    return (inputTokens == null ? 0 : inputTokens) +
      (outputTokens == null ? 0 : outputTokens);
  }

  public static Decimal getAgentUsage(
    Id agentId,
    Date startDate,
    Date endDate
  ) {
    if (startDate == null || endDate == null || startDate > endDate)
      throw AIMessagingException.newFailure(
        'A start date on or before an end date is required.',
        null
      );
    if (agentId == null || agentId.getSobjectType() != AIAgent__c.SObjectType)
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_AGENT_NOT_FOUND,
        Label.AI_Error_Agent_Not_Available
      );
    List<AggregateResult> usageRows = [
      SELECT SUM(InputTokens__c) inputTokens, SUM(OutputTokens__c) outputTokens
      FROM AIUsageDaily__c
      WHERE
        AIAgent__c = :agentId
        AND UsageDate__c >= :startDate
        AND UsageDate__c <= :endDate
      WITH SYSTEM_MODE
    ];
    if (usageRows.isEmpty())
      return 0; // SUM returns one row with null totals when nothing matches.
    Decimal inputTokens = (Decimal) usageRows[0].get('inputTokens');
    Decimal outputTokens = (Decimal) usageRows[0].get('outputTokens');
    return (inputTokens == null ? 0 : inputTokens) +
      (outputTokens == null ? 0 : outputTokens);
  }

  public static Decimal getUserUsage(Id userId, Date startDate, Date endDate) {
    if (startDate == null || endDate == null || startDate > endDate)
      throw AIMessagingException.newFailure(
        'A start date on or before an end date is required.',
        null
      );
    if (userId == null || userId.getSobjectType() != User.SObjectType)
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_NOT_AUTHORISED,
        Label.AI_Error_Not_Authorised
      );
    List<AggregateResult> usageRows = [
      SELECT SUM(InputTokens__c) inputTokens, SUM(OutputTokens__c) outputTokens
      FROM AIUsageDaily__c
      WHERE
        User__c = :userId
        AND UsageDate__c >= :startDate
        AND UsageDate__c <= :endDate
      WITH SYSTEM_MODE
    ];
    if (usageRows.isEmpty())
      return 0; // SUM returns one row with null totals when nothing matches.
    Decimal inputTokens = (Decimal) usageRows[0].get('inputTokens');
    Decimal outputTokens = (Decimal) usageRows[0].get('outputTokens');
    return (inputTokens == null ? 0 : inputTokens) +
      (outputTokens == null ? 0 : outputTokens);
  }

  // One conversation's running total, kept on the conversation by the message trigger. Read in user mode: only its owner or someone who can see it.
  public static Decimal getConversationUsage(Id conversationId) {
    if (
      conversationId == null ||
      conversationId.getSobjectType() != AIConversation__c.SObjectType
    )
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
        Label.AI_Error_Conversation_Not_Found
      );

    List<AIConversation__c> conversationRows = [
      SELECT ConversationTokenUsage__c
      FROM AIConversation__c
      WHERE Id = :conversationId
      WITH USER_MODE
      LIMIT 1
    ];
    if (conversationRows.isEmpty())
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
        Label.AI_Error_Conversation_Not_Found
      );

    return conversationRows[0].ConversationTokenUsage__c == null
      ? 0
      : conversationRows[0].ConversationTokenUsage__c;
  }
}
