/*
Class Name: AIPiiMappingServiceTest

=================================================================
=================================================================

Description: Testing utility for AIPiiMappingService: remembering which fake value stands in for which real value, per conversation.

=================================================================
=================================================================
Applicable Classes:

AIPiiMappingService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIPiiMappingServiceTest {
  // testScenario1: addMapping stores a real/fake pair that can be read back both ways, and a second pair for another real value merges into the same record.
  // testScenario2: A real value that is already paired is not paired again, and the first fake value stays.
  // testScenario3: A pairing already saved in the database is read back for the conversation.
  // testScenario4: While writes are deferred nothing is saved, and saveCached then writes every pending pair for several conversations in one pass.
  // testScenario5: Anything that is not a conversation, and blank values, are refused or ignored without error.

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

    Test.startTest();
    Boolean wasAdded = AIPiiMappingService.addMapping(
      conversation.Id,
      'real@example.com',
      'fake@example.com'
    );
    Boolean wasSecondAdded = AIPiiMappingService.addMapping(
      conversation.Id,
      '555-0100',
      '555-9999'
    );
    String fakeValue = AIPiiMappingService.getFakeValue(
      conversation.Id,
      'real@example.com'
    );
    String realValue = AIPiiMappingService.getRealValue(
      conversation.Id,
      'fake@example.com'
    );
    Test.stopTest();

    Assert.isTrue(wasAdded && wasSecondAdded, 'Both pairs are added.');
    Assert.areEqual('fake@example.com', fakeValue, 'Real to fake.');
    Assert.areEqual('real@example.com', realValue, 'Fake to real.');
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AIPIIMapping__c
        WHERE AIConversation__c = :conversation.Id
        WITH SYSTEM_MODE
      ],
      'One record per conversation holds every pair.'
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
    AIPiiMappingService.addMapping(conversation.Id, 'real', 'first');

    Test.startTest();
    Boolean wasAdded = AIPiiMappingService.addMapping(
      conversation.Id,
      'real',
      'second'
    );
    Test.stopTest();

    Assert.isFalse(wasAdded, 'The real value is already paired.');
    Assert.areEqual(
      'first',
      AIPiiMappingService.getFakeValue(conversation.Id, 'real'),
      'The first fake value stays.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIAssistTestDataFactory.createAIPIIMappings(
      conversation.Id,
      new Map<String, String>{
        'saved-real' => 'saved-fake',
        'blank-fake' => ''
      },
      true
    );

    Test.startTest();
    Map<String, String> mapping = AIPiiMappingService.getMapping(
      conversation.Id
    );
    String realValue = AIPiiMappingService.getRealValue(
      conversation.Id,
      'saved-fake'
    );
    Test.stopTest();

    Assert.areEqual(
      'saved-fake',
      mapping.get('saved-real'),
      'The saved pair is read.'
    );
    Assert.isFalse(
      mapping.containsKey('blank-fake'),
      'A pair with a blank fake value has nothing to restore to, so it is dropped.'
    );
    Assert.areEqual(
      'saved-real',
      realValue,
      'The reverse lookup works on saved pairs.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      3,
      true
    );
    AIPiiMappingService.isDeferringWrites = true;

    Test.startTest();
    Integer dmlBefore = Limits.getDmlStatements();
    for (AIConversation__c conversation : conversations)
      AIPiiMappingService.addMapping(
        conversation.Id,
        'real-' + conversation.Id,
        'fake-' + conversation.Id
      );
    Integer dmlWhileDeferred = Limits.getDmlStatements() - dmlBefore;
    Integer savedWhileDeferred = [
      SELECT COUNT()
      FROM AIPIIMapping__c
      WITH SYSTEM_MODE
    ];
    AIPiiMappingService.saveCached();
    Test.stopTest();

    Assert.areEqual(
      0,
      dmlWhileDeferred,
      'Deferred writes cause no DML, which would block the next callout.'
    );
    Assert.areEqual(0, savedWhileDeferred, 'Nothing is saved yet.');
    Assert.areEqual(
      3,
      [SELECT COUNT() FROM AIPIIMapping__c WITH SYSTEM_MODE],
      'saveCached writes one record per conversation.'
    );
    Assert.areEqual(
      'fake-' + conversations[0].Id,
      AIPiiMappingService.getFakeValue(
        conversations[0].Id,
        'real-' + conversations[0].Id
      ),
      'The pairs are still readable.'
    );
  }

  @IsTest
  static void testScenario5() {
    Test.startTest();
    Boolean wasAddedToUser = AIPiiMappingService.addMapping(
      UserInfo.getUserId(),
      'real',
      'fake'
    );
    Boolean wasAddedBlank = AIPiiMappingService.addMapping(
      null,
      'real',
      'fake'
    );
    Map<String, String> mapping = AIPiiMappingService.getMapping(
      UserInfo.getUserId()
    );
    String fakeValue = AIPiiMappingService.getFakeValue(null, 'real');
    String realValue = AIPiiMappingService.getRealValue(
      UserInfo.getUserId(),
      ''
    );
    AIPiiMappingService.saveCached();
    Test.stopTest();

    Assert.isFalse(
      wasAddedToUser || wasAddedBlank,
      'A non-conversation is refused.'
    );
    Assert.isTrue(mapping.isEmpty(), 'And has no mapping.');
    Assert.isNull(fakeValue, 'No conversation, no fake value.');
    Assert.isNull(realValue, 'No fake value, no real value.');
  }
}
