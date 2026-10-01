/*
Class Name: AIAgentTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIAgentTrigger and AIAgentTriggerHandler: the Public Id and Developer Name stamped on a new agent, bulk-safe and quiet when the application is switched off.

=================================================================
=================================================================
Applicable Classes:

AIAgentTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAgentTriggerHandlerTest {
  // testScenario1: A new agent gets a Public Id and a Developer Name derived from its name.
  // testScenario2: Two agents with the same name in one insert, or the name of an existing agent, still get different Developer Names.
  // testScenario3: A Public Id and a Developer Name supplied by the caller are kept.
  // testScenario4: An update leaves both identifiers alone.
  // testScenario5: Bulk: 201 agents all get both identifiers, distinct, within a few queries.
  // testScenario6: Switched off, nothing is stamped and the agent still saves.
  // testScenario7: The handler does nothing, and does not throw, for no records.
  // testScenario8: An unexpected failure inside the handler is logged and never stops the save.

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
      false
    )[0];
    agent.Name = 'Support Assistant (EMEA)';

    Test.startTest();
    insert agent;
    Test.stopTest();

    AIAgent__c saved = [
      SELECT PublicId__c, DeveloperName__c
      FROM AIAgent__c
      WHERE Id = :agent.Id
    ];
    Assert.areEqual(36, saved.PublicId__c.length(), 'A UUID.');
    Assert.areEqual(
      'Support_Assistant_EMEA',
      saved.DeveloperName__c,
      'Letters and numbers with single underscores.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c existing = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    existing.Name = 'Duplicate Name';
    insert existing;
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      2,
      existing.AIModelConfiguration__c,
      false
    );
    agents[0].Name = 'Duplicate Name';
    agents[1].Name = 'Duplicate Name';

    Test.startTest();
    insert agents;
    Test.stopTest();

    Assert.areEqual(
      3,
      [
        SELECT COUNT()
        FROM AIAgent__c
        WHERE DeveloperName__c LIKE 'Duplicate_Name%'
      ],
      'All three saved.'
    );
    Assert.areEqual(
      3,
      [
          SELECT COUNT_DISTINCT(DeveloperName__c)
          FROM AIAgent__c
          WHERE DeveloperName__c LIKE 'Duplicate_Name%'
        ][0]
        .get('expr0'),
      'Each is different.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    agent.PublicId__c = 'fixed-public-id';
    agent.DeveloperName__c = 'Fixed_Name';

    Test.startTest();
    insert agent;
    Test.stopTest();

    AIAgent__c saved = [
      SELECT PublicId__c, DeveloperName__c
      FROM AIAgent__c
      WHERE Id = :agent.Id
    ];
    Assert.areEqual('fixed-public-id', saved.PublicId__c, 'Kept.');
    Assert.areEqual('Fixed_Name', saved.DeveloperName__c, 'Kept.');
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIAgent__c before = [
      SELECT PublicId__c, DeveloperName__c
      FROM AIAgent__c
      WHERE Id = :agent.Id
    ];

    Test.startTest();
    agent.Name = 'A completely new name';
    update agent;
    Test.stopTest();

    AIAgent__c after = [
      SELECT PublicId__c, DeveloperName__c
      FROM AIAgent__c
      WHERE Id = :agent.Id
    ];
    Assert.areEqual(
      before.PublicId__c,
      after.PublicId__c,
      'The Public Id never changes.'
    );
    Assert.areEqual(
      before.DeveloperName__c,
      after.DeveloperName__c,
      'Neither does the Developer Name.'
    );
  }

  @IsTest
  static void testScenario5() {
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      201,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    );
    Integer queries;

    Test.startTest();
    insert agents;
    queries = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(
      201,
      [
        SELECT COUNT()
        FROM AIAgent__c
        WHERE PublicId__c != NULL AND DeveloperName__c != NULL
      ],
      'All stamped.'
    );
    Assert.areEqual(
      201,
      [SELECT COUNT_DISTINCT(PublicId__c) FROM AIAgent__c][0].get('expr0'),
      'All Public Ids differ.'
    );
    Assert.isTrue(
      queries <= 5,
      'Queries do not grow with the number of agents: ' + queries
    );
  }

  @IsTest
  static void testScenario6() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];

    Test.startTest();
    insert agent;
    Test.stopTest();

    AIAgent__c saved = [
      SELECT PublicId__c, DeveloperName__c
      FROM AIAgent__c
      WHERE Id = :agent.Id
    ];
    Assert.isNull(saved.PublicId__c, 'No Public Id.');
    Assert.isNull(saved.DeveloperName__c, 'No Developer Name.');
  }

  @IsTest
  static void testScenario7() {
    Test.startTest();
    try {
      AIAgentTriggerHandler.handleBeforeInsert(null);
      AIAgentTriggerHandler.handleBeforeInsert(new List<AIAgent__c>());
    } catch (Exception ex) {
      Assert.fail('The handler must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIPlatformLog__c],
      'Nothing to do is not a fault.'
    );
  }

  @IsTest
  static void testScenario8() {
    AIAgentTriggerHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    try {
      AIAgentTriggerHandler.handleBeforeInsert(
        new List<AIAgent__c>{ new AIAgent__c() }
      );
    } catch (Exception ex) {
      Assert.fail('The handler must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AIPlatformLog__c
        WHERE ClassName__c = 'AIAgentTriggerHandler'
      ],
      'Logged once.'
    );
  }
}
