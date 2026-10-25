/*
Class Name: AIChatFeedbackService

=================================================================
=================================================================

Description: Thumbs up or down on an AI reply.

Step 1: Check the rating is one we allow
Step 2: Load the user's own AI reply and any rating they already gave it
Step 3: Save the rating, replacing the earlier one if there is one

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIChatFeedbackService {

    public class AIChatFeedbackServiceException extends Exception {}

    // Saves a thumbs up or down on an AI reply. One rating per user per reply: rating again replaces it.
    public static void submitFeedback(Id messageId, String rating, String reason, String comment) {

        // [1] Refuse any rating that is not helpful or not-helpful
        if (rating != AIAssistApplicationConstants.FEEDBACK_RATING_HELPFUL && rating != AIAssistApplicationConstants.FEEDBACK_RATING_NOT_HELPFUL) throw new AIChatFeedbackServiceException(Label.AI_Error_Feedback_Invalid);

        // [2] Make sure the reply belongs to this user's conversation
        AIConversationMessage__c assertedMessage = AIChatConversationService.getOwnedAgentMessage(messageId);

        // [3] Find the rating this user already gave this reply, if any
        List<AIFeedback__c> existingFeedbacks = [SELECT Id FROM AIFeedback__c WHERE AIConversationMessage__c = :messageId AND CreatedById = :UserInfo.getUserId() WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 1];

        // [4] Reuse the earlier rating, or start a new one
        AIFeedback__c feedbackRecord = existingFeedbacks.isEmpty() ? new AIFeedback__c(AIConversationMessage__c = messageId, AIConversation__c = assertedMessage.AIConversation__c) : existingFeedbacks[0];

        // [5] Set the rating, reason and comment, cutting the comment to its maximum length
        feedbackRecord.Rating__c = rating;
        feedbackRecord.Reason__c = String.isBlank(reason) ? null : reason;
        feedbackRecord.Comment__c = String.isBlank(comment) ? null : comment.trim().left(AIAssistApplicationConstants.FEEDBACK_COMMENT_LENGTH);

        // [6] Save it, and log and refuse if the save fails
        Database.UpsertResult upsertResult = Database.upsert(feedbackRecord, false, AccessLevel.SYSTEM_MODE);

        if (!upsertResult.isSuccess()) {

            AIPlatformLogManager.logCustomMessage('Feedback could not be saved: ' + upsertResult.getErrors()[0].getMessage(), null, 'AIChatFeedbackService', 'submitFeedback', null);
            throw new AIChatFeedbackServiceException(Label.AI_Error_Generic);
        }
    }
}
