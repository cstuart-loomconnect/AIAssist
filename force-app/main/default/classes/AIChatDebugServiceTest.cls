/*
Class Name: AIChatDebugServiceTest

=================================================================
=================================================================

Description: Testing utility for AIChatDebugService: the debug trace, masking pairs, failure detail and restoring real values in text.

=================================================================
=================================================================
Applicable Classes:

AIChatDebugService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIChatDebugServiceTest {

    // testScenario1: The trace names the model, counts tool calls and masked values, and carries the payloads the recorder saved.
    // testScenario2: The mapping is only ever handed back as fake value to real value for restoring a reply; an unmasked conversation gives an empty map.
    // testScenario3: Fake values are swapped back longest first, so a longer fake value is replaced whole.
    // testScenario4: The failure detail gives the debug text of this turn's System message only, and nothing without debug mode.
    // testScenario5: The real value map is the masking map reversed.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Create an agent, a conversation, messages, a data source and two execution steps
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];

        User other = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 11, 1, true)[0];
        AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 22, 1, true)[0];

        AIDataSource__c source = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true)[0];

        List<AIExecutionStep__c> steps = AIAssistTestDataFactory.createAIExecutionSteps(reply.Id, 2, false);
        steps[0].AIDataSource__c = source.Id;
        steps[1].RequestJson__c = '{"req":1}';
        steps[1].ResponseJson__c = '{"res":1}';
        steps[1].AttemptNumber__c = 2;
        insert steps;

        // [2] Get the debug trace for the reply
        AIChatDataStructure.DebugTrace trace;

        Test.startTest();
            trace = AIChatDebugService.getDebugTrace(AIChatConversationService.getOwnedAgentMessage(reply.Id));
        Test.stopTest();

        // [3] Check the trace details
        Assert.areEqual(11, trace.promptTokens, 'The prompt tokens should come from the question.');
        Assert.areEqual(22, trace.replyTokens, 'The reply tokens should come from the reply.');
        Assert.areEqual('test-model', trace.model, 'The trace should name the model.');

        Assert.areEqual(1, trace.toolCalls, 'The data source step should count as one tool call.');
        Assert.areEqual(2, trace.steps.size(), 'Both steps should be on the trace.');

        Assert.areEqual('{"req":1}', trace.requestJson, 'The trace should carry the request payload.');
        Assert.areEqual(2, trace.attemptNumber, 'The trace should carry the attempt number.');
    }

    @IsTest static void testScenario2() {

        // [1] Create an agent, a masked conversation and a plain conversation
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];

        AIConversation__c plain = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];

        AIAssistTestDataFactory.createAIPIIMappings(conversation.Id, new Map<String, String>{
            'Zed' => 'Z2',
            'Abe' => 'A2'
        }, true);

        // [2] Get the real value by fake value map for each conversation
        Map<String, String> realByFake;
        Map<String, String> empty;

        Test.startTest();
            realByFake = AIChatDebugService.getRealValueByFakeValue(conversation.Id);
            empty = AIChatDebugService.getRealValueByFakeValue(plain.Id);
        Test.stopTest();

        // [3] Check the map and the empty map
        Assert.areEqual('Zed', realByFake.get('Z2'), 'The fake value Z2 should give the real value Zed.');
        Assert.areEqual('Abe', realByFake.get('A2'), 'The fake value A2 should give the real value Abe.');
        Assert.isTrue(empty.isEmpty(), 'A conversation with nothing masked should give an empty map.');
    }

    @IsTest static void testScenario3() {

        // [1] Define fake values where one contains the other
        Map<String, String> realByFake = new Map<String, String>{
            'Morgan' => 'Jo',
            'Morgan Reyes' => 'Jo Smith'
        };

        // [2] Restore the real values in text, in text with no mappings and in null
        String restored;
        String untouched;
        String blank;

        Test.startTest();
            restored = AIChatDebugService.restorePii('Morgan Reyes met Morgan.', realByFake);
            untouched = AIChatDebugService.restorePii('Nothing here', new Map<String, String>());
            blank = AIChatDebugService.restorePii(null, realByFake);
        Test.stopTest();

        // [3] Check the restored text
        Assert.areEqual('Jo Smith met Jo.', restored, 'The longer fake value should be replaced whole before the shorter one.');
        Assert.areEqual('Nothing here', untouched, 'Text should be unchanged when there are no mappings.');
        Assert.isNull(blank, 'Blank text should stay blank.');
    }

    @IsTest static void testScenario4() {

        // [1] Create an agent, a conversation, another user and System and user messages
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];

        User other = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_SYSTEM, 5, 1, true);
        AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 5, 1, true);

        // [2] Create a System message that holds the failure
        AIConversationMessage__c failure = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_SYSTEM, 5, 1, false)[0];
        failure.MessageBody__c = 'Turn failed: Timeout';
        AIMessagingDataService.insertOrThrow(new List<SObject>{ failure });

        // [3] Get the failure detail with and without debug mode
        AIChatDataStructure.FailureDetail withDebug;
        AIChatDataStructure.FailureDetail without;

        Test.startTest();
            withDebug = AIChatDebugService.getFailureDetail(conversation.Id, true);
            without = AIChatDebugService.getFailureDetail(conversation.Id, false);
        Test.stopTest();

        // [4] Check the detail is only given with debug mode
        Assert.areEqual('Turn failed: Timeout', withDebug.debugDetail, 'The detail should be the newest failure after the newest question.');
        Assert.isNull(without.debugDetail, 'There should be no detail without debug mode.');
    }

    @IsTest static void testScenario5() {

        // [1] Create an agent, a conversation, another user and a masking pair
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];

        User other = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAssistTestDataFactory.createAIPIIMappings(conversation.Id, new Map<String, String>{ 'Jane' => 'Mary' }, true);

        // [2] Get the real value by fake value map
        Map<String, String> realByFake;

        Test.startTest();
            realByFake = AIChatDebugService.getRealValueByFakeValue(conversation.Id);
        Test.stopTest();

        // [3] Check the fake value gives the real value
        Assert.areEqual('Jane', realByFake.get('Mary'), 'The fake value should give the real value.');
    }
}
