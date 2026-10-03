/*
Class Name: AIUsagePolicyTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIUsagePolicyTrigger and AIUsagePolicyTriggerHandler: the Public Id and Developer Name stamped on a new usage policy.

=================================================================
=================================================================
Applicable Classes:

AIUsagePolicyTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIUsagePolicyTriggerHandlerTest {
  // testScenario1: A new policy gets a Public Id and a Developer Name derived from its name, and a rename later leaves them alone.
  // testScenario2: An unexpected failure inside the handler is logged and never throws.

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
    AIUsagePolicy__c policy = AIAssistTestDataFactory.createAIUsagePolicies(
      1,
      false
    )[0];
    policy.Name = 'Sales Team Policy';

    Test.startTest();
    insert policy;
    Test.stopTest();

    AIUsagePolicy__c saved = [
      SELECT PublicId__c, DeveloperName__c
      FROM AIUsagePolicy__c
      WHERE Id = :policy.Id
    ];
    Assert.isNotNull(saved.PublicId__c, 'A Public Id is stamped.');
    Assert.isTrue(
      saved.DeveloperName__c.startsWithIgnoreCase('Sales'),
      'The Developer Name comes from the name.'
    );

    String developerName = saved.DeveloperName__c;
    saved.Name = 'Renamed Policy';
    update saved;
    Assert.areEqual(
      developerName,
      [SELECT DeveloperName__c FROM AIUsagePolicy__c WHERE Id = :policy.Id]
      .DeveloperName__c,
      'Identifiers are stamped once.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIUsagePolicyTriggerHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    List<AIUsagePolicy__c> policies = AIAssistTestDataFactory.createAIUsagePolicies(
      1,
      true
    );
    Test.stopTest();

    Assert.isNotNull(
      policies[0].Id,
      'The save went through; the failure was logged.'
    );
  }
}
