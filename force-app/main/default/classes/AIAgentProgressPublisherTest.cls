/*
Class Name: AIAgentProgressPublisherTest

=================================================================
=================================================================

Description: Testing utility for AIAgentProgressPublisher: publishing the content-free step label the chat window shows while a turn is running.

=================================================================
=================================================================
Applicable Classes:

AIAgentProgressPublisher

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAgentProgressPublisherTest {
  // testScenario1: A step with a conversation, a message and a label is published as one immediate event.
  // testScenario2: A missing conversation, message or label publishes nothing.

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
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIConversationMessage__c message = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      null,
      1,
      true
    )[0];
    Integer publishedBefore = Limits.getPublishImmediateDML();

    Test.startTest();
    AIAgentProgressPublisher.publishStep(
      conversation.Id,
      message.Id,
      'x'.repeat(300)
    );
    Integer published = Limits.getPublishImmediateDML() - publishedBefore;
    Test.stopTest();

    Assert.areEqual(
      1,
      published,
      'One event was published, with a label cut to the field size.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIConversationMessage__c message = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      null,
      1,
      true
    )[0];
    Integer publishedBefore = Limits.getPublishImmediateDML();

    Test.startTest();
    AIAgentProgressPublisher.publishStep(null, message.Id, 'Thinking');
    AIAgentProgressPublisher.publishStep(conversation.Id, null, 'Thinking');
    AIAgentProgressPublisher.publishStep(conversation.Id, message.Id, '');
    Integer published = Limits.getPublishImmediateDML() - publishedBefore;
    Test.stopTest();

    Assert.areEqual(0, published, 'Nothing is published without all three.');
  }
}
