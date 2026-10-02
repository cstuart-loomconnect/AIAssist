/*
Class Name: AIAgentAssignmentTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIAgentAssignmentTrigger and AIAgentAssignmentTriggerHandler: the unique key that stops the same user or permission set being assigned to one agent twice.

=================================================================
=================================================================
Applicable Classes:

AIAgentAssignmentTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAgentAssignmentTriggerHandlerTest {
  // testScenario1: A user assignment and a permission set assignment each get a key made of the agent and the assignee.
  // testScenario2: The same user, or the same permission set, cannot be assigned to one agent twice; another agent can have them.
  // testScenario3: The key is set on insert and is still right after an update. Nobody is granted edit access to it, so it cannot be typed in.
  // testScenario4: An unexpected failure inside the handler is logged and never throws.

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
    List<User> users = AIAssistTestDataFactory.createUsers(1, true);

    Test.startTest();
    AIAgentAssignment__c userAssignment = AIAssistTestDataFactory.createAIAgentAssignments(
      agent.Id,
      users,
      true
    )[0];
    AIAgentAssignment__c permissionSetAssignment = AIAssistTestDataFactory.createAIAgentAssignments(
      agent.Id,
      AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER,
      true
    )[0];
    Test.stopTest();

    Map<Id, AIAgentAssignment__c> savedById = new Map<Id, AIAgentAssignment__c>(
      [SELECT Id, AssignmentKey__c FROM AIAgentAssignment__c]
    );
    Assert.areEqual(
      agent.Id + '|U:' + users[0].Id,
      savedById.get(userAssignment.Id).AssignmentKey__c,
      'The agent, then the user.'
    );
    Assert.areEqual(
      agent.Id +
        '|PS:' +
        AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER,
      savedById.get(permissionSetAssignment.Id).AssignmentKey__c,
      'The agent, then the permission set by name.'
    );
  }

  @IsTest
  static void testScenario2() {
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, true);
    List<User> users = AIAssistTestDataFactory.createUsers(1, true);
    AIAssistTestDataFactory.createAIAgentAssignments(agents[0].Id, users, true);
    AIAssistTestDataFactory.createAIAgentAssignments(
      agents[0].Id,
      AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER,
      true
    );
    List<AIAgentAssignment__c> duplicates = AIAssistTestDataFactory.createAIAgentAssignments(
      agents[0].Id,
      users,
      false
    );
    duplicates.addAll(
      AIAssistTestDataFactory.createAIAgentAssignments(
        agents[0].Id,
        AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER,
        false
      )
    );
    duplicates[0].IsActive__c = false;

    Test.startTest();
    List<Database.SaveResult> duplicateResults = Database.insert(
      duplicates,
      false
    );
    List<Database.SaveResult> otherAgentResults = Database.insert(
      AIAssistTestDataFactory.createAIAgentAssignments(
        agents[1].Id,
        users,
        false
      ),
      false
    );
    Test.stopTest();

    for (Database.SaveResult duplicateResult : duplicateResults) {
      Assert.isFalse(duplicateResult.isSuccess(), 'Refused as a duplicate.');
      Assert.areEqual(
        StatusCode.DUPLICATE_VALUE,
        duplicateResult.getErrors()[0].getStatusCode(),
        'By the unique key.'
      );
    }
    Assert.isTrue(
      otherAgentResults[0].isSuccess(),
      'Another agent may have the same user.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    List<User> users = AIAssistTestDataFactory.createUsers(1, true);
    AIAgentAssignment__c assignment = AIAssistTestDataFactory.createAIAgentAssignments(
      agent.Id,
      users,
      false
    )[0];

    Test.startTest();
    insert assignment;
    String keyAfterInsert = [
      SELECT AssignmentKey__c
      FROM AIAgentAssignment__c
      WHERE Id = :assignment.Id
    ]
    .AssignmentKey__c;
    update new AIAgentAssignment__c(Id = assignment.Id, IsActive__c = false); // Only what changes: the master-detail to the agent cannot be written again.
    Test.stopTest();

    Assert.areEqual(
      agent.Id + '|U:' + users[0].Id,
      keyAfterInsert,
      'Set on insert.'
    );
    Assert.areEqual(
      keyAfterInsert,
      [
        SELECT AssignmentKey__c
        FROM AIAgentAssignment__c
        WHERE Id = :assignment.Id
      ]
      .AssignmentKey__c,
      'And unchanged by an update.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIAgentAssignmentTriggerHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    try {
      AIAgentAssignmentTriggerHandler.handleBeforeInsert(
        new List<AIAgentAssignment__c>{ new AIAgentAssignment__c() }
      );
      AIAgentAssignmentTriggerHandler.handleBeforeUpdate(null);
    } catch (Exception ex) {
      Assert.fail('The handler must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM AIPlatformLog__c
        WHERE ClassName__c = 'AIAgentAssignmentTriggerHandler'
      ],
      'Logged once for each call.'
    );
  }
}
