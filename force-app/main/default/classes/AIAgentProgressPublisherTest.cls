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
  // testScenario3: With events off, or the org near an event limit, nothing is published: the window polls instead.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    settings.IsEventNotificationEnabled__c = true; // Events are optional and off by default; these tests are about the events.
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

  @IsTest
  static void testScenario3() {
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
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEventNotificationEnabled__c = false;
    update settings;
    AIAssistSettingsService.clearCache();
    AIAgentProgressPublisher.publishStep(conversation.Id, message.Id, 'Off');
    Integer publishedWhenOff =
      Limits.getPublishImmediateDML() - publishedBefore;

    settings.IsEventNotificationEnabled__c = true;
    update settings;
    AIAssistSettingsService.clearCache();
    AIOrgLimitMonitor.transactionState = null;
    AIOrgLimitMonitor.testLimits = new Map<String, List<Decimal>>{
      'HourlyPublishedPlatformEvents' => new List<Decimal>{ 90, 100 }
    };
    AIAgentProgressPublisher.publishStep(conversation.Id, message.Id, 'Near');
    Integer publishedNearLimit =
      Limits.getPublishImmediateDML() - publishedBefore;
    Test.stopTest();

    Assert.areEqual(0, publishedWhenOff, 'Events are off by default.');
    Assert.areEqual(0, publishedNearLimit, 'Events stop near an event limit.');
  }
}
