/*
Class Name: AIChatFeedbackService

=================================================================
=================================================================

Description: Thumbs up or down on an AI reply, and accepting the usage terms.

One rating per user per reply: rating again replaces it. The reason is the object model's Reason field,
no longer folded into the comment. Accepting the terms records an acknowledgment for the current terms
version, signed with the user's name, as the object model requires; the acknowledgment is the evidence
and nothing else is copied onto the user's settings.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from the old feedback service. Uses the Reason field and the signature the terms record needs.
*/

public with sharing class AIChatFeedbackService {
  public class AIChatFeedbackServiceException extends Exception {
  }

  public static void submitFeedback(
    Id messageId,
    String rating,
    String reason,
    String comment
  ) {
    if (
      rating != AIAssistApplicationConstants.FEEDBACK_RATING_HELPFUL &&
      rating != AIAssistApplicationConstants.FEEDBACK_RATING_NOT_HELPFUL
    )
      throw new AIChatFeedbackServiceException(Label.AI_Error_Feedback_Invalid);

    AIConversationMessage__c assertedMessage = AIChatConversationService.assertOwnsAgentMessage(
      messageId
    );

    List<AIFeedback__c> existingFeedbacks = [
      SELECT Id
      FROM AIFeedback__c
      WHERE
        AIConversationMessage__c = :messageId
        AND CreatedById = :UserInfo.getUserId()
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];

    AIFeedback__c feedbackRecord = existingFeedbacks.isEmpty()
      ? new AIFeedback__c(
          AIConversationMessage__c = messageId,
          AIConversation__c = assertedMessage.AIConversation__c
        )
      : existingFeedbacks[0];
    feedbackRecord.Rating__c = rating;
    feedbackRecord.Reason__c = String.isBlank(reason) ? null : reason;
    feedbackRecord.Comment__c = String.isBlank(comment)
      ? null
      : comment.trim()
          .left(AIAssistApplicationConstants.FEEDBACK_COMMENT_LENGTH);

    Database.UpsertResult upsertResult = Database.upsert(
      feedbackRecord,
      false,
      AccessLevel.SYSTEM_MODE
    );
    if (!upsertResult.isSuccess()) {
      AIPlatformLogManager.logCustomMessage(
        'Feedback could not be saved: ' +
        upsertResult.getErrors()[0].getMessage(),
        null,
        'AIChatFeedbackService',
        'submitFeedback',
        null
      );
      throw new AIChatFeedbackServiceException(Label.AI_Error_Generic);
    }
  }

  // Written as the user, in user mode, because the object model only lets users acknowledge for themselves.
  public static void acknowledgeTerms() {
    String currentTermsVersion = AIAssistSettingsService.getSettings()
      .CurrentTermsVersion__c;
    Database.SaveResult insertResult = Database.insert(
      new AITermsAcknowledgment__c(
        User__c = UserInfo.getUserId(),
        TermsVersion__c = String.isBlank(currentTermsVersion)
          ? null
          : currentTermsVersion.trim(),
        AcknowledgedDate__c = System.now(),
        SignatureText__c = UserInfo.getName().left(120)
      ),
      false,
      AccessLevel.USER_MODE
    );

    if (!insertResult.isSuccess()) {
      AIPlatformLogManager.logCustomMessage(
        'Terms could not be acknowledged: ' +
        insertResult.getErrors()[0].getMessage(),
        null,
        'AIChatFeedbackService',
        'acknowledgeTerms',
        null
      );
      throw new AIChatFeedbackServiceException(Label.AI_Error_Generic);
    }
  }
}
