/*
Class Name: AIAgentDataSourceTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIAgentDataSourceTrigger and AIAgentDataSourceTriggerHandler: the unique key that stops one agent being given the same data source twice.

=================================================================
=================================================================
Applicable Classes:

AIAgentDataSourceTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAgentDataSourceTriggerHandlerTest {
  // testScenario1: A new link gets a key made of its agent and its data source.
  // testScenario2: The same data source cannot be linked to one agent twice, active or not; another agent can have it.
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
    List<AIDataSource__c> children = AIAssistTestDataFactory.createAIDataSources(
      2,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      true
    );

    Test.startTest();
    List<AIAgentDataSource__c> links = AIAssistTestDataFactory.createAIAgentDataSources(
      agent.Id,
      children,
      true
    );
    Test.stopTest();

    Map<Id, AIAgentDataSource__c> savedById = new Map<Id, AIAgentDataSource__c>(
      [
        SELECT Id, AIDataSource__c, AssignmentKey__c
        FROM AIAgentDataSource__c
        WHERE Id IN :links
      ]
    );
    Assert.areEqual(2, savedById.size(), 'Both saved.');
    for (AIAgentDataSource__c saved : savedById.values())
      Assert.areEqual(
        agent.Id + '|' + saved.AIDataSource__c,
        saved.AssignmentKey__c,
        'The agent, then the data source.'
      );
  }

  @IsTest
  static void testScenario2() {
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, true);
    List<AIDataSource__c> children = AIAssistTestDataFactory.createAIDataSources(
      2,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      true
    );
    AIAssistTestDataFactory.createAIAgentDataSources(
      agents[0].Id,
      children,
      true
    );
    List<AIAgentDataSource__c> duplicates = AIAssistTestDataFactory.createAIAgentDataSources(
      agents[0].Id,
      children,
      false
    );
    duplicates[1].IsActive__c = false;

    Test.startTest();
    List<Database.SaveResult> duplicateResults = Database.insert(
      duplicates,
      false
    );
    List<Database.SaveResult> otherAgentResults = Database.insert(
      AIAssistTestDataFactory.createAIAgentDataSources(
        agents[1].Id,
        children,
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
    for (Database.SaveResult otherAgentResult : otherAgentResults)
      Assert.isTrue(otherAgentResult.isSuccess(), 'Another agent may have it.');
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    List<AIDataSource__c> children = AIAssistTestDataFactory.createAIDataSources(
      2,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      true
    );
    AIAgentDataSource__c link = AIAssistTestDataFactory.createAIAgentDataSources(
      agent.Id,
      new List<AIDataSource__c>{ children[0] },
      false
    )[0];

    Test.startTest();
    insert link;
    String keyAfterInsert = [
      SELECT AssignmentKey__c
      FROM AIAgentDataSource__c
      WHERE Id = :link.Id
    ]
    .AssignmentKey__c;
    update new AIAgentDataSource__c(Id = link.Id, IsActive__c = false); // Only what changes: the master-detail to the agent cannot be written again.
    Test.stopTest();

    Assert.areEqual(
      agent.Id + '|' + children[0].Id,
      keyAfterInsert,
      'Set on insert.'
    );
    Assert.areEqual(
      keyAfterInsert,
      [SELECT AssignmentKey__c FROM AIAgentDataSource__c WHERE Id = :link.Id]
      .AssignmentKey__c,
      'And unchanged by an update.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIAgentDataSourceTriggerHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    try {
      AIAgentDataSourceTriggerHandler.handleBeforeInsert(
        new List<AIAgentDataSource__c>{ new AIAgentDataSource__c() }
      );
      AIAgentDataSourceTriggerHandler.handleBeforeUpdate(null);
    } catch (Exception ex) {
      Assert.fail('The handler must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM AIPlatformLog__c
        WHERE ClassName__c = 'AIAgentDataSourceTriggerHandler'
      ],
      'Logged once for each call.'
    );
  }
}
