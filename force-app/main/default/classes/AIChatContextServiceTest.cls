/*
Class Name: AIChatContextServiceTest

=================================================================
=================================================================

Description: Testing utility for AIChatContextService: the record strip and the agents offered for it.

=================================================================
=================================================================
Applicable Classes:

AIChatContextService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIChatContextServiceTest {
  // testScenario1: A record gives its object labels and name, and a blank or invalid Id gives no context.
  // testScenario2: An object covered by a synced, active PII registry is marked protected.
  // testScenario3: Agents for the object come before general agents, inactive agents and agents for another object are left out.
  // testScenario4: An Assigned Users Only agent is offered only to an assigned user.
  // testScenario5: selectAgent takes a 15 or 18 character Id or a Developer Name, and falls back to the first agent.

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
    Account record = AIAssistTestDataFactory.createAccounts(1, true)[0];

    Test.startTest();
    AIChatDataStructure.RecordContext context = AIChatContextService.buildRecordContext(
      String.valueOf(record.Id),
      null
    );
    AIChatDataStructure.RecordContext blank = AIChatContextService.buildRecordContext(
      null,
      null
    );
    AIChatDataStructure.RecordContext invalid = AIChatContextService.buildRecordContext(
      'not an id',
      null
    );
    Test.stopTest();

    Assert.areEqual('Account', context.objectApiName, 'The object.');
    Assert.areEqual('Accounts', context.objectLabelPlural, 'The plural label.');
    Assert.areEqual(record.Name, context.recordName, 'The record name.');
    Assert.isFalse(context.piiProtected, 'No registry.');
    Assert.isNull(blank.recordId, 'Blank.');
    Assert.isNull(invalid.recordId, 'Invalid.');
  }

  @IsTest
  static void testScenario2() {
    Account record = AIAssistTestDataFactory.createAccounts(1, true)[0];
    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      'Account',
      false
    )[0];
    registry.Active__c = true;
    registry.SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED;
    insert registry;

    Test.startTest();
    AIChatDataStructure.RecordContext context = AIChatContextService.buildRecordContext(
      String.valueOf(record.Id),
      'Account'
    );
    Test.stopTest();

    Assert.isTrue(context.piiProtected, 'Protected.');
  }

  @IsTest
  static void testScenario3() {
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      4,
      model.Id,
      false
    );
    for (AIAgent__c agent : agents)
      agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
    agents[0].Name = 'A General';
    agents[1].Name = 'B Account';
    agents[1].ObjectType__c = 'Account';
    agents[2].Name = 'C Contact';
    agents[2].ObjectType__c = 'Contact';
    agents[3].IsActive__c = false;
    insert agents;

    Test.startTest();
    List<AIChatDataStructure.AgentOption> options = AIChatContextService.getAvailableAgents(
      'Account'
    );
    Test.stopTest();

    Assert.areEqual(2, options.size(), 'Two are offered.');
    Assert.areEqual('B Account', options[0].name, 'The object agent first.');
    Assert.areEqual('A General', options[1].name, 'Then the general one.');
  }

  @IsTest
  static void testScenario4() {
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c closed = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      false
    )[0];
    closed.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
    insert closed;

    Test.startTest();
    Integer before = AIChatContextService.getAvailableAgents(null).size();
    AIAssistTestDataFactory.createAIAgentAssignments(
      closed.Id,
      new List<User>{ new User(Id = UserInfo.getUserId()) },
      true
    );
    Integer after = AIChatContextService.getAvailableAgents(null).size();
    Test.stopTest();

    Assert.areEqual(0, before, 'Not offered while unassigned.');
    Assert.areEqual(1, after, 'Offered once assigned.');
  }

  @IsTest
  static void testScenario5() {
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      2,
      model.Id,
      false
    );
    for (AIAgent__c agent : agents)
      agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
    agents[0].Name = 'First';
    agents[1].Name = 'Second';
    insert agents;
    List<AIChatDataStructure.AgentOption> options = AIChatContextService.getAvailableAgents(
      null
    );
    String secondDeveloperName = [
      SELECT DeveloperName__c
      FROM AIAgent__c
      WHERE Id = :agents[1].Id
    ]
    .DeveloperName__c;

    Test.startTest();
    AIChatDataStructure.AgentOption byId = AIChatContextService.selectAgent(
      options,
      String.valueOf(agents[1].Id)
    );
    AIChatDataStructure.AgentOption byShortId = AIChatContextService.selectAgent(
      options,
      String.valueOf(agents[1].Id).left(15)
    );
    AIChatDataStructure.AgentOption byName = AIChatContextService.selectAgent(
      options,
      secondDeveloperName
    );
    AIChatDataStructure.AgentOption fallback = AIChatContextService.selectAgent(
      options,
      'nothing'
    );
    AIChatDataStructure.AgentOption none = AIChatContextService.selectAgent(
      new List<AIChatDataStructure.AgentOption>(),
      'x'
    );
    Test.stopTest();

    Assert.areEqual(agents[1].Id, byId.id, 'By Id.');
    Assert.areEqual(agents[1].Id, byShortId.id, 'By 15 character Id.');
    Assert.areEqual(agents[1].Id, byName.id, 'By Developer Name.');
    Assert.areEqual(agents[0].Id, fallback.id, 'Unknown falls back.');
    Assert.isNull(none, 'No agents, none.');
  }
}
