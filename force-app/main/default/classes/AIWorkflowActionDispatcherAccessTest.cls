/*
Class Name: AIWorkflowActionDispatcherAccessTest

=================================================================
=================================================================

Description: Testing utility for the record checks AIWorkflowActionDispatcher makes before an action runs: the user's access to every record handed to a Flow, and recordId always being the server's. Flow versions cannot be created in a test, so a Flow that passes the checks goes on to fail at start (Action Failed), which is how "allowed" is told from "refused" (Action Not Permitted).

=================================================================
=================================================================
Applicable Classes:

AIWorkflowActionDispatcher

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIWorkflowActionDispatcherAccessTest {
  // testScenario1: A Flow handed the Id of a record the user cannot read is refused, a Blocked step is recorded, and the same Flow handed the user's own record gets past the check.
  // testScenario2: A Write Flow needs edit access: a record the user can only read is refused, and a Read Only Flow handed the same record gets past the check.
  // testScenario3: The conversation's own record is checked too: a Flow is refused when the user cannot read it.
  // testScenario4: A recordId sent by the browser is ignored even when the schema declares it; the action receives the server's record.
  // testScenario5: An input that is not a record Id is not checked.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  public class RecordExecutor implements IAIWorkflowActionExecutor {
    public AIWorkflowActionResponse execute(AIWorkflowActionRequest request) {
      return new AIWorkflowActionResponse(
        request.recordId +
          '|' +
          String.join(new List<String>(request.inputParameters.keySet()), ',')
      );
    }
  }

  // A user who may run actions, an agent, an action assigned to it, the reply it was suggested on, and a conversation the user cannot read.
  private class Fixture {
    User chatUser;
    AIAgent__c agent;
    AIWorkflowAction__c action;
    AIConversation__c conversation;
    AIConversation__c othersConversation;
    AIConversationMessage__c reply;
  }

  private static Fixture createFixture(
    String actionType,
    String source,
    String executionType
  ) {
    Fixture fixture = new Fixture();
    List<User> users = AIAssistTestDataFactory.createUsers(2, true);
    fixture.chatUser = users[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ fixture.chatUser },
      AIAssistApplicationConstants.PERMISSION_SET_USER
    );
    fixture.agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(
      fixture.chatUser.Id,
      false
    )[0];
    userSettings.WorkflowActionsEnabled__c = true;
    insert userSettings;
    fixture.action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      actionType,
      source,
      false
    )[0];
    fixture.action.InputSchema__c = '{"properties":{"targetId":{"type":"string"},"recordId":{"type":"string"}}}';
    fixture.action.ExecutionType__c = executionType;
    fixture.action.RequiresConfirmation__c =
      executionType == AIAssistApplicationConstants.WORKFLOW_EXECUTION_WRITE;
    fixture.action.ConfirmationMessage__c = fixture.action.RequiresConfirmation__c
      ? 'Change this record?'
      : null;
    insert fixture.action;
    AIAssistTestDataFactory.createAIAgentWorkflowActions(
      fixture.agent.Id,
      new List<AIWorkflowAction__c>{ fixture.action },
      true
    );
    fixture.conversation = AIAssistTestDataFactory.createAIConversations(
      fixture.agent.Id,
      fixture.chatUser.Id,
      1,
      true
    )[0];
    fixture.othersConversation = AIAssistTestDataFactory.createAIConversations(
      fixture.agent.Id,
      users[1].Id,
      1,
      true
    )[0];
    fixture.reply = AIAssistTestDataFactory.createAIConversationMessages(
      fixture.conversation.Id,
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

    return fixture;
  }

  private static String refusalCode(
    Fixture fixture,
    Id recordId,
    Map<String, Object> inputs
  ) {
    String code;
    try {
      AIWorkflowActionDispatcher.runWorkflowAction(
        fixture.action.Id,
        fixture.agent.Id,
        fixture.reply.Id,
        recordId,
        inputs,
        true
      );
    } catch (AIMessagingException refusal) {
      code = refusal.code;
    }
    return code;
  }

  @IsTest
  static void testScenario1() {
    Fixture fixture = createFixture(
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'No_Such_Flow',
      AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY
    );
    String withoutAccess;
    String withAccess;

    System.runAs(fixture.chatUser) {
      Test.startTest();
      withoutAccess = refusalCode(
        fixture,
        null,
        new Map<String, Object>{ 'targetId' => fixture.othersConversation.Id }
      );
      Integer blockedSteps = [
        SELECT COUNT()
        FROM AIExecutionStep__c
        WHERE
          AIConversationMessage__c = :fixture.reply.Id
          AND Status__c = :AIAssistApplicationConstants.EXECUTION_STEP_STATUS_BLOCKED
        WITH SYSTEM_MODE
      ];
      withAccess = refusalCode(
        fixture,
        null,
        new Map<String, Object>{
          'targetId' => String.valueOf(fixture.conversation.Id)
        }
      );
      Test.stopTest();

      Assert.areEqual(1, blockedSteps, 'The refusal is recorded as Blocked.');
    }

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_ACTION_NOT_PERMITTED,
      withoutAccess,
      'A record the user cannot read is not handed to a Flow.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_ACTION_FAILED,
      withAccess,
      'The user\'s own record passes the check; only the missing Flow fails.'
    );
  }

  @IsTest
  static void testScenario2() {
    Fixture fixture = createFixture(
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'No_Such_Flow',
      AIAssistApplicationConstants.WORKFLOW_EXECUTION_WRITE
    );
    String asWrite;
    String asReadOnly;
    // The User permission set reads agents and cannot edit them.
    Map<String, Object> inputs = new Map<String, Object>{
      'targetId' => fixture.agent.Id
    };

    System.runAs(fixture.chatUser) {
      Test.startTest();
      asWrite = refusalCode(fixture, null, inputs);
      Test.stopTest();
    }
    fixture.action.ExecutionType__c = AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY;
    update fixture.action;
    System.runAs(fixture.chatUser) {
      asReadOnly = refusalCode(fixture, null, inputs);
    }

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_ACTION_NOT_PERMITTED,
      asWrite,
      'A Write action needs edit access to the record.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_ACTION_FAILED,
      asReadOnly,
      'Read access is enough for a Read Only action.'
    );
  }

  @IsTest
  static void testScenario3() {
    Fixture fixture = createFixture(
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'No_Such_Flow',
      AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY
    );
    String code;

    System.runAs(fixture.chatUser) {
      Test.startTest();
      code = refusalCode(fixture, fixture.othersConversation.Id, null);
      Test.stopTest();
    }

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_ACTION_NOT_PERMITTED,
      code,
      'The conversation\'s record is checked like any other.'
    );
  }

  @IsTest
  static void testScenario4() {
    Fixture fixture = createFixture(
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
      'AIWorkflowActionDispatcherAccessTest.RecordExecutor',
      AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY
    );
    Object output;

    System.runAs(fixture.chatUser) {
      Test.startTest();
      output = AIWorkflowActionDispatcher.runWorkflowAction(
        fixture.action.Id,
        fixture.agent.Id,
        fixture.reply.Id,
        fixture.conversation.Id,
        new Map<String, Object>{
          'recordId' => fixture.othersConversation.Id,
          'RecordID' => fixture.othersConversation.Id,
          'targetId' => 'kept'
        },
        true
      );
      Test.stopTest();
    }

    Assert.areEqual(
      fixture.conversation.Id + '|targetId',
      output,
      'The record is the server\'s, and the browser\'s recordId never reaches the action.'
    );
  }

  @IsTest
  static void testScenario5() {
    Fixture fixture = createFixture(
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'No_Such_Flow',
      AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY
    );
    String code;

    System.runAs(fixture.chatUser) {
      Test.startTest();
      code = refusalCode(
        fixture,
        null,
        new Map<String, Object>{ 'targetId' => 'Call the customer back' }
      );
      Test.stopTest();
    }

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_ACTION_FAILED,
      code,
      'Plain text is passed on; only the missing Flow fails.'
    );
  }
}
