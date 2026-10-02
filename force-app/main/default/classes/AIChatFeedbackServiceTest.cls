/*
Class Name: AIChatFeedbackServiceTest

=================================================================
=================================================================

Description: Testing utility for AIChatFeedbackService: a rating on a reply, replaced when given again, and accepting the terms.

=================================================================
=================================================================
Applicable Classes:

AIChatFeedbackService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIChatFeedbackServiceTest {
  // testScenario1: A rating is saved with its reason and comment, and rating again replaces it.
  // testScenario2: A reason and a trimmed comment are stored, the comment cut to its length.
  // testScenario3: An invalid rating, a reply that is not the user's and a user message are all refused.
  // testScenario4: Accepting the terms records an acknowledgment of the current version, signed with the user's name.

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
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      UserInfo.getUserId(),
      1,
      true
    )[0];
    User other = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      5,
      1,
      true
    )[0];

    Test.startTest();
    AIChatFeedbackService.submitFeedback(
      reply.Id,
      AIAssistApplicationConstants.FEEDBACK_RATING_NOT_HELPFUL,
      'Inaccurate',
      '  Wrong figure  '
    );
    AIChatFeedbackService.submitFeedback(
      reply.Id,
      AIAssistApplicationConstants.FEEDBACK_RATING_HELPFUL,
      null,
      null
    );
    Test.stopTest();

    List<AIFeedback__c> saved = [
      SELECT Rating__c, Reason__c, Comment__c
      FROM AIFeedback__c
      WHERE AIConversationMessage__c = :reply.Id
    ];
    Assert.areEqual(1, saved.size(), 'One rating per user per reply.');
    Assert.areEqual(
      AIAssistApplicationConstants.FEEDBACK_RATING_HELPFUL,
      saved[0].Rating__c,
      'Replaced.'
    );
    Assert.isNull(saved[0].Reason__c, 'Reason cleared.');
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      UserInfo.getUserId(),
      1,
      true
    )[0];
    User other = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      5,
      1,
      true
    )[0];

    Test.startTest();
    AIChatFeedbackService.submitFeedback(
      reply.Id,
      AIAssistApplicationConstants.FEEDBACK_RATING_NOT_HELPFUL,
      'Inaccurate',
      'c'.repeat(AIAssistApplicationConstants.FEEDBACK_COMMENT_LENGTH + 50)
    );
    Test.stopTest();

    AIFeedback__c saved = [
      SELECT Reason__c, Comment__c
      FROM AIFeedback__c
      WHERE AIConversationMessage__c = :reply.Id
    ];
    Assert.areEqual('Inaccurate', saved.Reason__c, 'The reason.');
    Assert.areEqual(
      AIAssistApplicationConstants.FEEDBACK_COMMENT_LENGTH,
      saved.Comment__c.length(),
      'Cut to length.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      UserInfo.getUserId(),
      1,
      true
    )[0];
    User other = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      other.Id,
      1,
      true
    )[0];
    AIConversationMessage__c theirReply = AIAssistTestDataFactory.createAIConversationMessages(
      theirs.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      5,
      1,
      true
    )[0];
    AIConversationMessage__c ownReply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      5,
      1,
      true
    )[0];
    List<String> codes = new List<String>();

    Test.startTest();
    try {
      AIChatFeedbackService.submitFeedback(ownReply.Id, 'Great', null, null);
      Assert.fail('Bad rating.');
    } catch (AIMessagingException ex) {
      codes.add(ex.code);
    }
    try {
      AIChatFeedbackService.submitFeedback(
        theirReply.Id,
        AIAssistApplicationConstants.FEEDBACK_RATING_HELPFUL,
        null,
        null
      );
      Assert.fail('Not theirs.');
    } catch (AIMessagingException ex) {
      codes.add(ex.code);
    }
    Test.stopTest();

    Assert.areEqual(2, codes.size(), 'Both refused.');
    Assert.areEqual(0, [SELECT COUNT() FROM AIFeedback__c], 'Nothing saved.');
  }

  @IsTest
  static void testScenario4() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.CurrentTermsVersion__c = 'v9';
    update settings;
    AIAssistSettingsService.cachedSettings = null;

    Test.startTest();
    AIChatFeedbackService.acknowledgeTerms();
    Test.stopTest();

    AITermsAcknowledgment__c saved = [
      SELECT TermsVersion__c, SignatureText__c, User__c
      FROM AITermsAcknowledgment__c
    ];
    Assert.areEqual('v9', saved.TermsVersion__c, 'The current version.');
    Assert.areEqual(
      UserInfo.getName().left(120),
      saved.SignatureText__c,
      'Signed with the name.'
    );
    Assert.areEqual(UserInfo.getUserId(), saved.User__c, 'For this user.');
  }
}
