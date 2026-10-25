/*
Class Name: AIChatFeedbackServiceTest

=================================================================
=================================================================

Description: Testing utility for AIChatFeedbackService: a rating on a reply, replaced when given again.

=================================================================
=================================================================
Applicable Classes:

AIChatFeedbackService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIChatFeedbackServiceTest {

    // testScenario1: A rating is saved with its reason and comment, and rating again replaces it -> one rating is left, with the later rating and no reason.
    // testScenario2: A reason and an over-long comment are submitted -> the reason is stored and the comment is cut to its length.
    // testScenario3: An invalid rating and a reply that is not the user's are submitted -> both are refused and nothing is saved.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent, a conversation and an AI reply
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            // [2] Rate the reply, then rate it again
            Test.startTest();
                AIChatFeedbackService.submitFeedback(reply.Id, AIAssistApplicationConstants.FEEDBACK_RATING_NOT_HELPFUL, 'Inaccurate', '  Wrong figure  ');
                AIChatFeedbackService.submitFeedback(reply.Id, AIAssistApplicationConstants.FEEDBACK_RATING_HELPFUL, null, null);
            Test.stopTest();

            // [3] Read the saved ratings
            List<AIFeedback__c> saved = [SELECT Rating__c, Reason__c, Comment__c FROM AIFeedback__c WHERE AIConversationMessage__c = :reply.Id];

            // [4] Check one rating is left and it replaced the first
            Assert.areEqual(1, saved.size(), 'There should be one rating per user per reply.');
            Assert.areEqual(AIAssistApplicationConstants.FEEDBACK_RATING_HELPFUL, saved[0].Rating__c, 'The second rating should replace the first.');
            Assert.isNull(saved[0].Reason__c, 'The reason should be cleared when the new rating has none.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent, a conversation and an AI reply
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            // [2] Rate the reply with a reason and an over-long comment
            Test.startTest();
                AIChatFeedbackService.submitFeedback(reply.Id, AIAssistApplicationConstants.FEEDBACK_RATING_NOT_HELPFUL, 'Inaccurate', 'c'.repeat(AIAssistApplicationConstants.FEEDBACK_COMMENT_LENGTH + 50));
            Test.stopTest();

            // [3] Read the saved rating
            AIFeedback__c saved = [SELECT Reason__c, Comment__c FROM AIFeedback__c WHERE AIConversationMessage__c = :reply.Id];

            // [4] Check the reason and the cut comment
            Assert.areEqual('Inaccurate', saved.Reason__c, 'The reason should be stored.');
            Assert.areEqual(AIAssistApplicationConstants.FEEDBACK_COMMENT_LENGTH, saved.Comment__c.length(), 'The comment should be cut to the maximum length.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent, the user's conversation, another user's conversation and an AI reply in each
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];

            User other = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(agent.Id, other.Id, 1, true)[0];
            AIConversationMessage__c theirReply = AIAssistTestDataFactory.createAIConversationMessages(theirs.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            AIConversationMessage__c ownReply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            List<String> messages = new List<String>();

            // [2] Submit a bad rating, then a rating on another user's reply
            Test.startTest();
                try {
                    AIChatFeedbackService.submitFeedback(ownReply.Id, 'Great', null, null);
                } catch (AIChatFeedbackService.AIChatFeedbackServiceException ex) {
                    messages.add(ex.getMessage());
                }
                try {
                    AIChatFeedbackService.submitFeedback(theirReply.Id, AIAssistApplicationConstants.FEEDBACK_RATING_HELPFUL, null, null);
                } catch (AIChatConversationService.AIChatConversationServiceException ex) {
                    messages.add(ex.getMessage());
                }
            Test.stopTest();

            // [3] Count the saved ratings
            Integer savedCount = [SELECT COUNT() FROM AIFeedback__c];

            // [4] Check both were refused and nothing was saved
            Assert.areEqual(2, messages.size(), 'Both submissions should be refused.');

            Assert.areEqual(Label.AI_Error_Feedback_Invalid, messages[0], 'A bad rating should give the invalid feedback message.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, messages[1], 'A reply that is not the user\'s should give the not found message.');

            Assert.areEqual(0, savedCount, 'Nothing should be saved.');
        }
    }
}
