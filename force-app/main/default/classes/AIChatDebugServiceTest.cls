/*
Class Name: AIChatDebugServiceTest

=================================================================
=================================================================

Description: Testing utility for AIChatDebugService: the debug trace, masking pairs, failure detail and restoring real values in text.

=================================================================
=================================================================
Applicable Classes:

AIChatDebugService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIChatDebugServiceTest {
  // testScenario1: The trace names the model, counts tool calls and masked values, and carries the payloads the recorder saved.
  // testScenario2: Masking pairs come back as sorted JSON, and an unmasked conversation gives an empty object.
  // testScenario3: Fake values are swapped back longest first, so a longer fake value is replaced whole.
  // testScenario4: The failure detail gives the debug text of this turn's System message only, and nothing without debug mode.
  // testScenario5: The real value map is the masking map reversed.

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
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      11,
      1,
      true
    )[0];
    AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      22,
      1,
      true
    )[0];
    AIDataSource__c source = AIAssistTestDataFactory.createAIDataSources(
      1,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      true
    )[0];
    List<AIExecutionStep__c> steps = AIAssistTestDataFactory.createAIExecutionSteps(
      reply.Id,
      2,
      false
    );
    steps[0].AIDataSource__c = source.Id;
    steps[1].RequestJson__c = '{"req":1}';
    steps[1].ResponseJson__c = '{"res":1}';
    steps[1].AttemptNumber__c = 2;
    insert steps;
    AIChatDataStructure.DebugTrace trace;

    Test.startTest();
    trace = AIChatDebugService.getDebugTrace(
      AIChatConversationService.assertOwnsAgentMessage(reply.Id)
    );
    Test.stopTest();

    Assert.areEqual(11, trace.promptTokens, 'Prompt tokens from the question.');
    Assert.areEqual(22, trace.replyTokens, 'Reply tokens.');
    Assert.areEqual('test-model', trace.model, 'The model.');
    Assert.areEqual(1, trace.toolCalls, 'One data source step.');
    Assert.areEqual(2, trace.steps.size(), 'Both steps.');
    Assert.areEqual('{"req":1}', trace.requestJson, 'The payload.');
    Assert.areEqual(2, trace.attemptNumber, 'The attempt.');
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
    AIConversation__c plain = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      UserInfo.getUserId(),
      1,
      true
    )[0];
    AIAssistTestDataFactory.createAIPIIMappings(
      conversation.Id,
      new Map<String, String>{ 'Zed' => 'Z2', 'Abe' => 'A2' },
      true
    );

    Test.startTest();
    String pairs = AIChatDebugService.getPiiMappings(conversation.Id);
    String empty = AIChatDebugService.getPiiMappings(plain.Id);
    Test.stopTest();

    Assert.isTrue(
      pairs.indexOf('Abe') < pairs.indexOf('Zed'),
      'Sorted by real value.'
    );
    Assert.areEqual('{ }', empty, 'Nothing masked.');
  }

  @IsTest
  static void testScenario3() {
    Map<String, String> realByFake = new Map<String, String>{
      'Morgan' => 'Jo',
      'Morgan Reyes' => 'Jo Smith'
    };

    Test.startTest();
    String restored = AIChatDebugService.restorePii(
      'Morgan Reyes met Morgan.',
      realByFake
    );
    String untouched = AIChatDebugService.restorePii(
      'Nothing here',
      new Map<String, String>()
    );
    String blank = AIChatDebugService.restorePii(null, realByFake);
    Test.stopTest();

    Assert.areEqual('Jo Smith met Jo.', restored, 'Longest first.');
    Assert.areEqual('Nothing here', untouched, 'No mappings.');
    Assert.isNull(blank, 'Blank stays blank.');
  }

  @IsTest
  static void testScenario4() {
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
    AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_SYSTEM,
      5,
      1,
      true
    );
    AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      5,
      1,
      true
    );
    AIConversationMessage__c failure = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_SYSTEM,
      5,
      1,
      false
    )[0];
    failure.MessageBody__c = 'Turn failed: Timeout';
    AIMessagingDataService.insertAsPackage(new List<SObject>{ failure });

    Test.startTest();
    AIChatDataStructure.FailureDetail withDebug = AIChatDebugService.getFailureDetail(
      conversation.Id,
      true
    );
    AIChatDataStructure.FailureDetail without = AIChatDebugService.getFailureDetail(
      conversation.Id,
      false
    );
    Test.stopTest();

    Assert.areEqual(
      'Turn failed: Timeout',
      withDebug.debugDetail,
      'The newest failure after the newest question.'
    );
    Assert.isNull(without.debugDetail, 'Not without debug mode.');
  }

  @IsTest
  static void testScenario5() {
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
    AIAssistTestDataFactory.createAIPIIMappings(
      conversation.Id,
      new Map<String, String>{ 'Jane' => 'Mary' },
      true
    );

    Test.startTest();
    Map<String, String> realByFake = AIChatDebugService.getRealValueByFakeValue(
      conversation.Id
    );
    Test.stopTest();

    Assert.areEqual('Jane', realByFake.get('Mary'), 'Fake to real.');
  }
}
