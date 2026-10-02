/*
Class Name: AIModelConfigurationTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIModelConfigurationTrigger and AIModelConfigurationTriggerHandler: the Developer Name stamped on a new model configuration.

=================================================================
=================================================================
Applicable Classes:

AIModelConfigurationTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIModelConfigurationTriggerHandlerTest {
  // testScenario1: A new model configuration gets a Developer Name derived from its name, and one supplied is kept.
  // testScenario2: Bulk: 201 model configurations are all named, distinct, within a few queries.
  // testScenario3: Switched off, nothing is stamped, and the handler ignores empty input.
  // testScenario4: An unexpected failure inside the handler is logged and never stops the save.

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
    List<AIModelConfiguration__c> models = AIAssistTestDataFactory.createAIModelConfigurations(
      2,
      false
    );
    models[0].Name = 'Claude Sonnet - Production';
    models[1].DeveloperName__c = 'Fixed_Model';

    Test.startTest();
    insert models;
    Test.stopTest();

    Map<Id, AIModelConfiguration__c> byId = new Map<Id, AIModelConfiguration__c>(
      [SELECT DeveloperName__c FROM AIModelConfiguration__c WHERE Id IN :models]
    );
    Assert.areEqual(
      'Claude_Sonnet_Production',
      byId.get(models[0].Id).DeveloperName__c,
      'Derived.'
    );
    Assert.areEqual(
      'Fixed_Model',
      byId.get(models[1].Id).DeveloperName__c,
      'Kept.'
    );
  }

  @IsTest
  static void testScenario2() {
    List<AIModelConfiguration__c> models = AIAssistTestDataFactory.createAIModelConfigurations(
      201,
      false
    );
    Integer queries;

    Test.startTest();
    insert models;
    queries = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(
      201,
      [SELECT COUNT_DISTINCT(DeveloperName__c) FROM AIModelConfiguration__c][0]
        .get('expr0'),
      'All distinct.'
    );
    Assert.isTrue(
      queries <= 5,
      'Queries do not grow with the number of records: ' + queries
    );
  }

  @IsTest
  static void testScenario3() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      false
    )[0];

    Test.startTest();
    insert model;
    AIModelConfigurationTriggerHandler.handleBeforeInsert(null);
    Test.stopTest();

    Assert.isNull(
      [
        SELECT DeveloperName__c
        FROM AIModelConfiguration__c
        WHERE Id = :model.Id
      ]
      .DeveloperName__c,
      'No Developer Name.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIModelConfigurationTriggerHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    try {
      AIModelConfigurationTriggerHandler.handleBeforeInsert(
        new List<AIModelConfiguration__c>{ new AIModelConfiguration__c() }
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
        WHERE ClassName__c = 'AIModelConfigurationTriggerHandler'
      ],
      'Logged once.'
    );
  }
}
