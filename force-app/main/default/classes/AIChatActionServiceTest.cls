/*
Class Name: AIChatActionServiceTest

=================================================================
=================================================================

Description: Testing utility for AIChatActionService: the Suggested Action card, its input fields, and running it through the dispatcher.

=================================================================
=================================================================
Applicable Classes:

AIChatActionService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIChatActionServiceTest {
  // testScenario1: A card shows the action, its confirmation requirement, and the default confirmation text when none is set.
  // testScenario2: An input schema becomes fields with types, labels and required flags, and a malformed schema becomes none.
  // testScenario3: run executes the suggested action and returns its output, and a refusal comes back as a result with the Custom Label, not an exception.
  // testScenario4: A reply with no suggested action cannot be run.

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
    AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'Some_Flow',
      false
    )[0];
    action.RequiresConfirmation__c = false;

    Test.startTest();
    AIChatDataStructure.SuggestedAction card = AIChatActionService.toSuggestedAction(
      action
    );
    Test.stopTest();

    Assert.areEqual(action.ActionName__c, card.name, 'The name.');
    Assert.isFalse(card.requiresConfirmation, 'No confirmation.');
    Assert.areEqual(
      Label.AI_Chat_Confirm_Action_Default,
      card.confirmationMessage,
      'The default text is a Custom Label.'
    );
  }

  @IsTest
  static void testScenario2() {
    String schema = '{"properties":{"due_date":{"type":"string","format":"date"},"count":{"type":"integer","title":"How many"},"notes":{"type":"string","maxLength":1000,"description":"Anything"},"flag":{"type":"boolean"},"name":{}},"required":["name"]}';
    Map<String, AIChatDataStructure.ActionInputField> byName = new Map<String, AIChatDataStructure.ActionInputField>();

    Test.startTest();
    for (
      AIChatDataStructure.ActionInputField field : AIChatActionService.parseInputSchema(
        schema
      )
    )
      byName.put(field.name, field);
    Integer malformed = AIChatActionService.parseInputSchema('{not json')
      .size();
    Integer blank = AIChatActionService.parseInputSchema(null).size();
    Test.stopTest();

    Assert.areEqual('date', byName.get('due_date').inputType, 'Date.');
    Assert.areEqual('number', byName.get('count').inputType, 'Number.');
    Assert.areEqual('How many', byName.get('count').label, 'Title.');
    Assert.areEqual('textarea', byName.get('notes').inputType, 'Long text.');
    Assert.areEqual('checkbox', byName.get('flag').inputType, 'Boolean.');
    Assert.isTrue(
      byName.get('name').required && byName.get('name').label == 'Name',
      'Required, humanised label.'
    );
    Assert.areEqual(0, malformed + blank, 'No fields.');
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      false
    )[0];
    settings.WorkflowActionsEnabled__c = true;
    insert settings;
    AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
      'AIWorkflowActionDispatcherTest.EchoExecutor',
      true
    )[0];
    action.InputSchema__c = '{"properties":{"x":{}}}';
    update action;
    AIAssistTestDataFactory.createAIAgentWorkflowActions(
      agent.Id,
      new List<AIWorkflowAction__c>{ action },
      true
    );
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      5,
      1,
      false
    )[0];
    reply.SuggestedWorkflowAction__c = action.Id;
    AIMessagingDataService.insertAsPackage(new List<SObject>{ reply });
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      true
    );
    AIChatDataStructure.ActionResult ran;
    AIChatDataStructure.ActionResult refused;

    System.runAs(chatUser) {
      AIConversationMessage__c loaded = AIChatConversationService.assertOwnsAgentMessage(
        reply.Id
      );
      Test.startTest();
      ran = AIChatActionService.runSuggestedAction(loaded, '{"x":"hi"}', true);
      AIPlanLimitService.setLimitForTest(
        AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
        false
      );
      refused = AIChatActionService.runSuggestedAction(loaded, null, true);
      Test.stopTest();
    }

    Assert.isTrue(ran.isSuccess, 'It ran.');
    Assert.areEqual('echo:hi', ran.message, 'Its output.');
    Assert.isFalse(refused.isSuccess, 'Refused.');
    Assert.areEqual(
      Label.AI_Error_Plan_Actions_Not_Included,
      refused.message,
      'The text is the Custom Label.'
    );
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
    AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      5,
      1,
      true
    )[0];
    AIConversationMessage__c loaded = AIChatConversationService.assertOwnsAgentMessage(
      reply.Id
    );
    String code;

    Test.startTest();
    try {
      AIChatActionService.runSuggestedAction(loaded, null, true);
      Assert.fail('Nothing to run.');
    } catch (AIMessagingException ex) {
      code = ex.code;
    }
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_ACTION_NOT_PERMITTED,
      code,
      'Not permitted.'
    );
  }
}
