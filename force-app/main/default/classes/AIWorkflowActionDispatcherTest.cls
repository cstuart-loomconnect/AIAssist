/*
Class Name: AIWorkflowActionDispatcherTest

=================================================================
=================================================================

Description: Testing utility for AIWorkflowActionDispatcher: every gate before a Workflow Action runs, what is shown when it cannot, and the evidence recorded on the reply for each outcome.

=================================================================
=================================================================
Applicable Classes:

AIWorkflowActionDispatcher

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIWorkflowActionDispatcherTest {
  // testScenario1: An assigned, active action runs as the user, returns its output, and a Success step records the target and the time.
  // testScenario2: A plan that does not include Workflow Actions refuses with the plan label and records a Blocked step.
  // testScenario3: A user without the actions setting, or with no settings at all, is refused, and the agent's Unauthorized Workflow Action rule records a violation.
  // testScenario4: An action that is inactive, not assigned to the agent, or not found is refused the same way, and says nothing about which.
  // testScenario5: An action that changes data runs only when confirmed, and the step then records who confirmed it and when.
  // testScenario6: A class that does not implement the interface, one that cannot be found, and one that throws all give the Action Failed label with no class name or detail, and a Failed step.
  // testScenario7: A Flow action whose flow cannot be started fails the same way, and one with no flow name is refused as a failure.
  // testScenario8: An Apex action on a plan without Apex is refused with the Apex plan label.
  // testScenario9: cancel records that the user declined, and a missing message or action records nothing.
  // testScenario10: Switched off, nothing runs.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  // An action class, one that throws, and one that is not an action at all.
  public class EchoExecutor implements IAIWorkflowActionExecutor {
    public Object execute(Id recordId, Map<String, Object> inputParameters) {
      return 'echo:' + inputParameters.get('x');
    }
  }

  public class ThrowingExecutor implements IAIWorkflowActionExecutor {
    public Object execute(Id recordId, Map<String, Object> inputParameters) {
      throw new CalloutException('Secret internal detail');
    }
  }

  public class NotAnExecutor {
    public Object execute(Id recordId, Map<String, Object> inputParameters) {
      return 'should never run';
    }
  }

  @IsTest
  static void testScenario1() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      false
    )[0];
    userSettings.WorkflowActionsEnabled__c = true;
    insert userSettings;
    AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
      'AIWorkflowActionDispatcherTest.EchoExecutor',
      true
    )[0];
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
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      true
    );
    Object output;

    System.runAs(chatUser) {
      Test.startTest();
      output = AIWorkflowActionDispatcher.runWorkflowAction(
        action.Id,
        agent.Id,
        reply.Id,
        null,
        new Map<String, Object>{ 'x' => 'hello' },
        false
      );
      Test.stopTest();
    }

    AIExecutionStep__c step = [
      SELECT
        StepType__c,
        Status__c,
        AIWorkflowAction__c,
        RequiredConfirmation__c,
        DurationMilliseconds__c
      FROM AIExecutionStep__c
      WHERE AIConversationMessage__c = :reply.Id
    ];
    Assert.areEqual('echo:hello', output, 'The action\'s output.');
    Assert.areEqual(
      AIAssistApplicationConstants.STEP_TYPE_WORKFLOW_ACTION,
      step.StepType__c,
      'A Workflow Action step.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS,
      step.Status__c,
      'Success.'
    );
    Assert.areEqual(action.Id, step.AIWorkflowAction__c, 'The action.');
    Assert.isFalse(
      step.RequiredConfirmation__c,
      'It did not need confirmation.'
    );
  }

  @IsTest
  static void testScenario2() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      false
    )[0];
    userSettings.WorkflowActionsEnabled__c = true;
    insert userSettings;
    AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
      'AIWorkflowActionDispatcherTest.EchoExecutor',
      true
    )[0];
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
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      false
    );
    String code;
    String shown;

    System.runAs(chatUser) {
      Test.startTest();
      try {
        AIWorkflowActionDispatcher.runWorkflowAction(
          action.Id,
          agent.Id,
          reply.Id,
          null,
          null,
          false
        );
        Assert.fail(
          'The plan does not include actions, so this should have been refused.'
        );
      } catch (AIMessagingException ex) {
        code = ex.code;
        shown = ex.getMessage();
      }
      Test.stopTest();
    }

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_PLAN_ACTIONS_NOT_INCLUDED,
      code,
      'The code.'
    );
    Assert.areEqual(
      Label.AI_Error_Plan_Actions_Not_Included,
      shown,
      'The text is the Custom Label.'
    );
  }

  @IsTest
  static void testScenario3() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      false
    )[0];
    userSettings.WorkflowActionsEnabled__c = true;
    insert userSettings;
    AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
      'AIWorkflowActionDispatcherTest.EchoExecutor',
      true
    )[0];
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
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      true
    );
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      false
    )[0];
    rule.ViolationTypeProduced__c = AIAssistApplicationConstants.VIOLATION_TYPE_UNAUTHORIZED_WORKFLOW_ACTION;
    insert rule;
    AIAssistTestDataFactory.createAIAgentViolationRules(
      agent.Id,
      new List<AIViolationRule__c>{ rule },
      true
    );
    userSettings.WorkflowActionsEnabled__c = false;
    update userSettings;
    List<String> codes = new List<String>();

    System.runAs(chatUser) {
      Test.startTest();
      try {
        AIWorkflowActionDispatcher.runWorkflowAction(
          action.Id,
          agent.Id,
          reply.Id,
          null,
          null,
          false
        );
      } catch (AIMessagingException ex) {
        codes.add(ex.code);
        Assert.areEqual(
          Label.AI_Error_Action_Not_Permitted,
          ex.getMessage(),
          'The text is the Custom Label.'
        );
      }
      Test.stopTest();
    }

    delete userSettings;
    System.runAs(chatUser) {
      try {
        AIWorkflowActionDispatcher.runWorkflowAction(
          action.Id,
          agent.Id,
          reply.Id,
          null,
          null,
          false
        );
      } catch (AIMessagingException ex) {
        codes.add(ex.code);
      }
    }

    Assert.areEqual(
      new List<String>{
        AIAssistApplicationConstants.ERROR_ACTION_NOT_PERMITTED,
        AIAssistApplicationConstants.ERROR_ACTION_NOT_PERMITTED
      },
      codes,
      'Refused both times.'
    );
    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM AIViolation__c
        WHERE
          AIViolationRule__c = :rule.Id
          AND ViolationType__c = :AIAssistApplicationConstants.VIOLATION_TYPE_UNAUTHORIZED_WORKFLOW_ACTION
      ],
      'A violation each time.'
    );
  }

  @IsTest
  static void testScenario4() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      false
    )[0];
    userSettings.WorkflowActionsEnabled__c = true;
    insert userSettings;
    AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
      'AIWorkflowActionDispatcherTest.EchoExecutor',
      true
    )[0];
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
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      true
    );
    AIWorkflowAction__c unassigned = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
      'AIWorkflowActionDispatcherTest.EchoExecutor',
      true
    )[0];
    AIWorkflowAction__c inactive = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
      'AIWorkflowActionDispatcherTest.EchoExecutor',
      true
    )[0];
    AIAssistTestDataFactory.createAIAgentWorkflowActions(
      agent.Id,
      new List<AIWorkflowAction__c>{ inactive },
      true
    );
    inactive.IsActive__c = false;
    update inactive;
    List<String> codes = new List<String>();

    System.runAs(chatUser) {
      Test.startTest();
      for (
        Id actionId : new List<Id>{ unassigned.Id, inactive.Id, agent.Id, null }
      ) {
        try {
          AIWorkflowActionDispatcher.runWorkflowAction(
            actionId,
            agent.Id,
            reply.Id,
            null,
            null,
            false
          );
          Assert.fail('This action should have been refused.');
        } catch (AIMessagingException ex) {
          codes.add(ex.code);
        }
      }
      Test.stopTest();
    }

    for (String code : codes)
      Assert.areEqual(
        AIAssistApplicationConstants.ERROR_ACTION_NOT_PERMITTED,
        code,
        'Not permitted, whatever the reason.'
      );
    Assert.areEqual(4, codes.size(), 'All four were refused.');
  }

  @IsTest
  static void testScenario5() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      false
    )[0];
    userSettings.WorkflowActionsEnabled__c = true;
    insert userSettings;
    AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
      'AIWorkflowActionDispatcherTest.EchoExecutor',
      true
    )[0];
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
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      true
    );
    action.ExecutionType__c = AIAssistApplicationConstants.WORKFLOW_EXECUTION_WRITE;
    action.RequiresConfirmation__c = true;
    action.ConfirmationMessage__c = 'This changes data. Are you sure?';
    update action;
    String code;
    Object output;

    System.runAs(chatUser) {
      Test.startTest();
      try {
        AIWorkflowActionDispatcher.runWorkflowAction(
          action.Id,
          agent.Id,
          reply.Id,
          null,
          null,
          false
        );
        Assert.fail('An unconfirmed write should have been refused.');
      } catch (AIMessagingException ex) {
        code = ex.code;
        Assert.areEqual(
          Label.AI_Error_Action_Confirmation_Required,
          ex.getMessage(),
          'The text is the Custom Label.'
        );
      }
      output = AIWorkflowActionDispatcher.runWorkflowAction(
        action.Id,
        agent.Id,
        reply.Id,
        null,
        new Map<String, Object>{ 'x' => 'ok' },
        true
      );
      Test.stopTest();
    }

    List<AIExecutionStep__c> steps = [
      SELECT
        Status__c,
        RequiredConfirmation__c,
        ConfirmedBy__c,
        ConfirmedDate__c
      FROM AIExecutionStep__c
      WHERE AIConversationMessage__c = :reply.Id
      ORDER BY StepOrder__c
    ];
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_ACTION_CONFIRMATION_REQUIRED,
      code,
      'The code.'
    );
    Assert.areEqual('echo:ok', output, 'Ran once confirmed.');
    Assert.areEqual(
      AIAssistApplicationConstants.EXECUTION_STEP_STATUS_BLOCKED,
      steps[0].Status__c,
      'The first attempt is evidence too.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS,
      steps[1].Status__c,
      'The second succeeded.'
    );
    Assert.isTrue(
      steps[1].RequiredConfirmation__c,
      'It required confirmation.'
    );
    Assert.areEqual(chatUser.Id, steps[1].ConfirmedBy__c, 'Who confirmed.');
    Assert.isNotNull(steps[1].ConfirmedDate__c, 'And when.');
  }

  @IsTest
  static void testScenario6() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      false
    )[0];
    userSettings.WorkflowActionsEnabled__c = true;
    insert userSettings;
    AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
      'AIWorkflowActionDispatcherTest.EchoExecutor',
      true
    )[0];
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
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      true
    );
    List<AIWorkflowAction__c> actions = AIAssistTestDataFactory.createAIWorkflowActions(
      3,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
      'AIWorkflowActionDispatcherTest.NotAnExecutor',
      false
    );
    actions[1].ApexClassName__c = 'AIWorkflowActionDispatcherTest.NoSuchClass';
    actions[2]
      .ApexClassName__c = 'AIWorkflowActionDispatcherTest.ThrowingExecutor';
    insert actions;
    AIAssistTestDataFactory.createAIAgentWorkflowActions(
      agent.Id,
      actions,
      true
    );
    List<String> shown = new List<String>();

    System.runAs(chatUser) {
      Test.startTest();
      for (AIWorkflowAction__c each : actions) {
        try {
          AIWorkflowActionDispatcher.runWorkflowAction(
            each.Id,
            agent.Id,
            reply.Id,
            null,
            null,
            false
          );
          Assert.fail('This action should have failed.');
        } catch (AIMessagingException ex) {
          Assert.areEqual(
            AIAssistApplicationConstants.ERROR_ACTION_FAILED,
            ex.code,
            'The code.'
          );
          shown.add(ex.getMessage());
        }
      }
      Test.stopTest();
    }

    for (String text : shown)
      Assert.areEqual(
        Label.AI_Error_Action_Failed,
        text,
        'Only the label is shown: nothing about classes or errors.'
      );
    Assert.areEqual(
      3,
      [
        SELECT COUNT()
        FROM AIExecutionStep__c
        WHERE
          AIConversationMessage__c = :reply.Id
          AND Status__c = :AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED
      ],
      'A Failed step each.'
    );
  }

  @IsTest
  static void testScenario7() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      false
    )[0];
    userSettings.WorkflowActionsEnabled__c = true;
    insert userSettings;
    AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
      'AIWorkflowActionDispatcherTest.EchoExecutor',
      true
    )[0];
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
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      true
    );
    List<AIWorkflowAction__c> actions = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'No_Such_Flow',
      true
    );
    AIAssistTestDataFactory.createAIAgentWorkflowActions(
      agent.Id,
      actions,
      true
    );
    String code;

    System.runAs(chatUser) {
      Test.startTest();
      try {
        AIWorkflowActionDispatcher.runWorkflowAction(
          actions[0].Id,
          agent.Id,
          reply.Id,
          conversation.Id,
          null,
          false
        );
        Assert.fail('A flow that does not exist cannot run.');
      } catch (AIMessagingException ex) {
        code = ex.code;
      }
      Test.stopTest();
    }

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_ACTION_FAILED,
      code,
      'Action Failed.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AIExecutionStep__c
        WHERE
          AIConversationMessage__c = :reply.Id
          AND TargetRecordId__c = :String.valueOf(conversation.Id)
      ],
      'The target record is on the step.'
    );
  }

  @IsTest
  static void testScenario8() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      false
    )[0];
    userSettings.WorkflowActionsEnabled__c = true;
    insert userSettings;
    AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
      'AIWorkflowActionDispatcherTest.EchoExecutor',
      true
    )[0];
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
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      false
    );
    String code;
    String shown;

    System.runAs(chatUser) {
      Test.startTest();
      try {
        AIWorkflowActionDispatcher.runWorkflowAction(
          action.Id,
          agent.Id,
          reply.Id,
          null,
          null,
          false
        );
        Assert.fail('Apex is not in the plan.');
      } catch (AIMessagingException ex) {
        code = ex.code;
        shown = ex.getMessage();
      }
      Test.stopTest();
    }

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_PLAN_APEX_NOT_INCLUDED,
      code,
      'The code.'
    );
    Assert.areEqual(
      Label.AI_Error_Plan_Apex_Not_Included,
      shown,
      'The text is the Custom Label.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.EXECUTION_STEP_STATUS_BLOCKED,
      [
        SELECT Status__c
        FROM AIExecutionStep__c
        WHERE AIConversationMessage__c = :reply.Id
      ]
      .Status__c,
      'Blocked, not Failed: it never ran.'
    );
  }

  @IsTest
  static void testScenario9() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      false
    )[0];
    userSettings.WorkflowActionsEnabled__c = true;
    insert userSettings;
    AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
      'AIWorkflowActionDispatcherTest.EchoExecutor',
      true
    )[0];
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
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      true
    );

    System.runAs(chatUser) {
      Test.startTest();
      AIWorkflowActionDispatcher.recordDeclinedAction(
        action.Id,
        agent.Id,
        reply.Id,
        null
      );
      AIWorkflowActionDispatcher.recordDeclinedAction(
        action.Id,
        agent.Id,
        null,
        null
      );
      AIWorkflowActionDispatcher.recordDeclinedAction(
        null,
        agent.Id,
        reply.Id,
        null
      );
      Test.stopTest();
    }

    List<AIExecutionStep__c> steps = [
      SELECT Status__c
      FROM AIExecutionStep__c
      WHERE AIConversationMessage__c = :reply.Id
    ];
    Assert.areEqual(1, steps.size(), 'Only the real cancellation.');
    Assert.areEqual(
      AIAssistApplicationConstants.EXECUTION_STEP_STATUS_CANCELLED,
      steps[0].Status__c,
      'Cancelled.'
    );
  }

  @IsTest
  static void testScenario10() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      false
    )[0];
    userSettings.WorkflowActionsEnabled__c = true;
    insert userSettings;
    AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
      'AIWorkflowActionDispatcherTest.EchoExecutor',
      true
    )[0];
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
      true
    )[0];
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      true
    );
    String code;

    System.runAs(chatUser) {
      Test.startTest();
      try {
        AIWorkflowActionDispatcher.runWorkflowAction(
          action.Id,
          agent.Id,
          reply.Id,
          null,
          null,
          false
        );
        Assert.fail('The application is off.');
      } catch (AIMessagingException ex) {
        code = ex.code;
      }
      Test.stopTest();
    }

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_APPLICATION_DISABLED,
      code,
      'Application inactive.'
    );
  }
}
