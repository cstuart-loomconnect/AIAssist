/*
Class Name: AIPiiMappingServiceTest

=================================================================
=================================================================

Description: Testing utility for AIPiiMappingService: remembering which fake value stands in for which real value, per conversation.

=================================================================
=================================================================
Applicable Classes:

AIPiiMappingService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIPiiMappingServiceTest {
  // testScenario1: Two real/fake pairs are added -> they read back both ways and share one record.
  // testScenario2: A real value that is already paired is paired again -> it is refused and the first fake value stays.
  // testScenario3: A pairing already saved in the database is read for the conversation -> it is returned, and a blank fake value is dropped.
  // testScenario4: Pairs are added for several conversations while writes are deferred -> nothing is saved until saveCached writes every pending pair in one pass.
  // testScenario5: Something that is not a conversation, and blank values, are used -> they are refused or ignored without error.

  private static final String REAL_EMAIL = 'real@example.com';
  private static final String FAKE_EMAIL = 'fake@example.com';

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
    // [1] Create an agent and a conversation
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, null, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
      1,
      true
    )[0];

    Boolean wasAdded;
    Boolean wasSecondAdded;
    String fakeValue;
    String realValue;

    // [2] Add two real and fake pairs and read one back both ways
    Test.startTest();
    wasAdded = AIPiiMappingService.addMapping(
      conversation.Id,
      REAL_EMAIL,
      FAKE_EMAIL
    );
    wasSecondAdded = AIPiiMappingService.addMapping(
      conversation.Id,
      '555-0100',
      '555-9999'
    );
    fakeValue = AIPiiMappingService.getFakeValue(conversation.Id, REAL_EMAIL);
    realValue = AIPiiMappingService.getRealValue(conversation.Id, FAKE_EMAIL);
    Test.stopTest();

    // [3] Count the mapping records for the conversation
    Integer mappingCount = [
      SELECT COUNT()
      FROM AIPIIMapping__c
      WHERE AIConversation__c = :conversation.Id
      WITH SYSTEM_MODE
    ];

    // [4] Check both pairs are added, readable both ways and held in one record
    Assert.isTrue(wasAdded && wasSecondAdded, 'Both pairs are added.');
    Assert.areEqual(FAKE_EMAIL, fakeValue, 'Real to fake.');
    Assert.areEqual(REAL_EMAIL, realValue, 'Fake to real.');

    Assert.areEqual(
      1,
      mappingCount,
      'One record per conversation holds every pair.'
    );
  }

  @IsTest
  static void testScenario2() {
    // [1] Create an agent and a conversation
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, null, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
      1,
      true
    )[0];

    // [2] Pair a real value with a first fake value
    AIPiiMappingService.addMapping(conversation.Id, 'real', 'first');

    Boolean wasAdded;

    // [3] Pair the same real value with a second fake value
    Test.startTest();
    wasAdded = AIPiiMappingService.addMapping(
      conversation.Id,
      'real',
      'second'
    );
    Test.stopTest();

    // [4] Read the fake value for the real value
    String fakeValue = AIPiiMappingService.getFakeValue(
      conversation.Id,
      'real'
    );

    // [5] Check the second pairing is refused and the first stays
    Assert.isFalse(wasAdded, 'The real value is already paired.');
    Assert.areEqual('first', fakeValue, 'The first fake value stays.');
  }

  @IsTest
  static void testScenario3() {
    // [1] Create an agent and a conversation
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, null, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
      1,
      true
    )[0];

    // [2] Save one good pair and one with a blank fake value
    AIAssistTestDataFactory.createAIPIIMappings(
      conversation.Id,
      new Map<String, String>{
        'saved-real' => 'saved-fake',
        'blank-fake' => ''
      },
      true
    );

    Map<String, String> mapping;
    String realValue;

    // [3] Read the mapping and the real value for the conversation
    Test.startTest();
    mapping = AIPiiMappingService.getMapping(conversation.Id);
    realValue = AIPiiMappingService.getRealValue(conversation.Id, 'saved-fake');
    Test.stopTest();

    // [4] Check the good pair is read, the blank is dropped and the reverse lookup works
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
    // [1] Create an agent and three conversations
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, null, true)[0];
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
      3,
      true
    );

    // [2] Defer writes
    AIPiiMappingService.isDeferringWrites = true;

    // [3] Note the DML count before the pairs are added
    Integer dmlBefore = Limits.getDmlStatements();
    Integer dmlWhileDeferred;
    Integer savedWhileDeferred;

    // [4] Add a pair for each conversation, then save the cache
    Test.startTest();
    for (AIConversation__c conversation : conversations)
      AIPiiMappingService.addMapping(
        conversation.Id,
        'real-' + conversation.Id,
        'fake-' + conversation.Id
      );
    dmlWhileDeferred = Limits.getDmlStatements() - dmlBefore;
    savedWhileDeferred = [SELECT COUNT() FROM AIPIIMapping__c WITH SYSTEM_MODE];
    AIPiiMappingService.saveCached();
    Test.stopTest();

    // [5] Count the saved mappings and read one pair back
    Integer savedAfter = [SELECT COUNT() FROM AIPIIMapping__c WITH SYSTEM_MODE];
    String fakeValue = AIPiiMappingService.getFakeValue(
      conversations[0].Id,
      'real-' + conversations[0].Id
    );

    // [6] Check nothing was written until saveCached, then one record per conversation
    Assert.areEqual(
      0,
      dmlWhileDeferred,
      'Deferred writes cause no DML, which would block the next callout.'
    );
    Assert.areEqual(0, savedWhileDeferred, 'Nothing is saved yet.');

    Assert.areEqual(
      3,
      savedAfter,
      'saveCached writes one record per conversation.'
    );
    Assert.areEqual(
      'fake-' + conversations[0].Id,
      fakeValue,
      'The pairs are still readable.'
    );
  }

  @IsTest
  static void testScenario5() {
    // [1] Declare what the test reads back
    Boolean wasAddedToUser;
    Boolean wasAddedBlank;
    Map<String, String> mapping;
    String fakeValue;
    String realValue;

    // [2] Use a user Id, a null Id and blank values
    Test.startTest();
    wasAddedToUser = AIPiiMappingService.addMapping(
      UserInfo.getUserId(),
      'real',
      'fake'
    );
    wasAddedBlank = AIPiiMappingService.addMapping(null, 'real', 'fake');

    mapping = AIPiiMappingService.getMapping(UserInfo.getUserId());
    fakeValue = AIPiiMappingService.getFakeValue(null, 'real');
    realValue = AIPiiMappingService.getRealValue(UserInfo.getUserId(), '');

    AIPiiMappingService.saveCached();
    Test.stopTest();

    // [3] Check non-conversations are refused and give nothing back
    Assert.isFalse(
      wasAddedToUser || wasAddedBlank,
      'A non-conversation is refused.'
    );
    Assert.isTrue(mapping.isEmpty(), 'And has no mapping.');

    Assert.isNull(fakeValue, 'No conversation, no fake value.');
    Assert.isNull(realValue, 'No fake value, no real value.');
  }
}
