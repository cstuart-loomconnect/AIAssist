/*
Class Name: AIDataSourceTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIDataSourceTrigger and AIDataSourceTriggerHandler: the Developer Name stamped on a new data source, kept within the 64 characters providers accept for a tool name.

=================================================================
=================================================================
Applicable Classes:

AIDataSourceTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIDataSourceTriggerHandlerTest {
  // testScenario1: A new data source gets a Developer Name derived from its source name, and one supplied is kept.
  // testScenario2: A Developer Name longer than 64 characters is cut to 64, at the limit it is kept whole, and one over it is cut.
  // testScenario3: A long source name produces a Developer Name of 64 characters or fewer.
  // testScenario4: Bulk: 201 data sources are all named, distinct, within a few queries.
  // testScenario5: Switched off, nothing is stamped, and the handler ignores empty input.
  // testScenario6: An unexpected failure inside the handler is logged and never stops the save.

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
    List<AIDataSource__c> sources = AIAssistTestDataFactory.createAIDataSources(
      2,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      false
    );
    sources[0].SourceName__c = 'Open Cases (last 30 days)';
    sources[1].DeveloperName__c = 'Fixed_Source';

    Test.startTest();
    insert sources;
    Test.stopTest();

    Map<Id, AIDataSource__c> byId = new Map<Id, AIDataSource__c>(
      [SELECT DeveloperName__c FROM AIDataSource__c WHERE Id IN :sources]
    );
    Assert.areEqual(
      'Open_Cases_last_30_days',
      byId.get(sources[0].Id).DeveloperName__c,
      'Derived.'
    );
    Assert.areEqual(
      'Fixed_Source',
      byId.get(sources[1].Id).DeveloperName__c,
      'Kept.'
    );
  }

  @IsTest
  static void testScenario2() {
    List<AIDataSource__c> sources = AIAssistTestDataFactory.createAIDataSources(
      3,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      false
    );
    sources[0].DeveloperName__c = 'a'.repeat(64);
    sources[1].DeveloperName__c = 'b'.repeat(65);
    sources[2].DeveloperName__c = 'c'.repeat(75);

    Test.startTest();
    insert sources;
    Test.stopTest();

    Map<Id, AIDataSource__c> byId = new Map<Id, AIDataSource__c>(
      [SELECT DeveloperName__c FROM AIDataSource__c WHERE Id IN :sources]
    );
    Assert.areEqual(
      64,
      byId.get(sources[0].Id).DeveloperName__c.length(),
      'At the limit, whole.'
    );
    Assert.areEqual(
      64,
      byId.get(sources[1].Id).DeveloperName__c.length(),
      'One over, cut.'
    );
    Assert.areEqual(
      64,
      byId.get(sources[2].Id).DeveloperName__c.length(),
      'Well over, cut.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIDataSource__c source = AIAssistTestDataFactory.createAIDataSources(
      1,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      false
    )[0];
    source.SourceName__c = 'Very long data source name '.repeat(5).left(80);

    Test.startTest();
    insert source;
    Test.stopTest();

    Assert.isTrue(
      [SELECT DeveloperName__c FROM AIDataSource__c WHERE Id = :source.Id]
      .DeveloperName__c.length() <= 64,
      'Fits a tool name.'
    );
  }

  @IsTest
  static void testScenario4() {
    List<AIDataSource__c> sources = AIAssistTestDataFactory.createAIDataSources(
      201,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      false
    );
    Integer queries;

    Test.startTest();
    insert sources;
    queries = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(
      201,
      [SELECT COUNT_DISTINCT(DeveloperName__c) FROM AIDataSource__c][0]
        .get('expr0'),
      'All distinct.'
    );
    Assert.isTrue(
      queries <= 5,
      'Queries do not grow with the number of records: ' + queries
    );
  }

  @IsTest
  static void testScenario5() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    AIDataSource__c source = AIAssistTestDataFactory.createAIDataSources(
      1,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      false
    )[0];

    Test.startTest();
    insert source;
    AIDataSourceTriggerHandler.handleBeforeInsert(null);
    Test.stopTest();

    Assert.isNull(
      [SELECT DeveloperName__c FROM AIDataSource__c WHERE Id = :source.Id]
      .DeveloperName__c,
      'No Developer Name.'
    );
  }

  @IsTest
  static void testScenario6() {
    AIDataSourceTriggerHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    try {
      AIDataSourceTriggerHandler.handleBeforeInsert(
        new List<AIDataSource__c>{ new AIDataSource__c() }
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
        WHERE ClassName__c = 'AIDataSourceTriggerHandler'
      ],
      'Logged once.'
    );
  }
}
