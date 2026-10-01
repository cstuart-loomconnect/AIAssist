/*
Class Name: AIAgentProgressPublisher

=================================================================
=================================================================

Description: Publishes AIAgentProgressEvent__e (PublishImmediately) so the chat window can show
"Looking up information" or "Thinking" while a turn is still running, before the reply exists.

The text is content-free: a step label (a Custom Label such as AI_Step_Calling_Model) and the
Ids of the conversation and message. Every user holding the event can subscribe to it, so it
carries nothing from the conversation.

It is cosmetic, and so it gives way first: it publishes nothing when the transaction is close to
its Publish Immediately allowance (AIGovernorLimits), leaving the rest for the platform log. A
failed publish is ignored.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Sharing relaxed to inherited. Event field sizes respected.
*/

public inherited sharing class AIAgentProgressPublisher {
  public static void publishStep(
    Id conversationId,
    Id userMessageId,
    String stepLabel
  ) {
    if (
      conversationId == null ||
      userMessageId == null ||
      String.isBlank(stepLabel)
    )
      return;
    if (!AIGovernorLimits.isSafeToPublishProgress())
      return;

    EventBus.publish(
      new AIAgentProgressEvent__e(
        AIConversationId__c = String.valueOf(conversationId),
        UserMessageId__c = String.valueOf(userMessageId),
        StepLabel__c = stepLabel.abbreviate(255)
      )
    );
  }
}
