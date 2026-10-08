/*
Class Name: AIAgentTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIAgentTrigger and AIAgentTriggerHandler: the retention recalculation batch started when an agent's retention days or retention trigger change.

=================================================================
=================================================================
Applicable Classes:

AIAgentTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Developer Name scenarios removed: names are typed by the user, never stamped. Tests the retention recalculation instead.
*/

@IsTest
private class AIAgentTriggerHandlerTest {
  // testScenario1: Changing an agent's retention days starts the retention recalculation batch.
  // testScenario2: Changing an agent's retention trigger starts the retention recalculation batch.
  // testScenario3: An unrelated change to an agent does not start the batch.
  // testScenario4: The handler does nothing, and does not throw, for no records.
  // testScenario5: An unexpected failure inside the handler is logged and never stops the save.

  private static final String BATCH_NAME = 'AIConversationRetentionRecalcBatch';

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  private static AIAgent__c createAgentWithRetention() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    agent.ConversationRetentionDays__c = 30;
    agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
    insert agent;
    return agent;
  }

  private static Integer countBatchJobs() {
    return [
      SELECT COUNT()
      FROM AsyncApexJob
      WHERE ApexClass.Name = :BATCH_NAME
    ];
  }

  @IsTest
  static void testScenario1() {
    AIAgent__c agent = createAgentWithRetention();
    Assert.areEqual(0, countBatchJobs(), 'No batch before the change.');

    Test.startTest();
    agent.ConversationRetentionDays__c = 60;
    update agent;
    Test.stopTest();

    Assert.areEqual(1, countBatchJobs(), 'The recalculation batch ran once.');
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c agent = createAgentWithRetention();

    Test.startTest();
    agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_LAST_MESSAGE_DATE;
    update agent;
    Test.stopTest();

    Assert.areEqual(1, countBatchJobs(), 'The recalculation batch ran once.');
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = createAgentWithRetention();

    Test.startTest();
    agent.Name = 'A completely new name';
    update agent;
    Test.stopTest();

    Assert.areEqual(0, countBatchJobs(), 'Retention did not change.');
  }

  @IsTest
  static void testScenario4() {
    Test.startTest();
    try {
      AIAgentTriggerHandler.handleAfterUpdate(null, null);
      AIAgentTriggerHandler.handleAfterUpdate(
        new Map<Id, AIAgent__c>(),
        new List<AIAgent__c>()
      );
    } catch (Exception ex) {
      Assert.fail('The handler must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(0, countBatchJobs(), 'No batch.');
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIPlatformLog__c],
      'Nothing to do is not a fault.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIAgentTriggerHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    try {
      AIAgentTriggerHandler.handleAfterUpdate(
        new Map<Id, AIAgent__c>(),
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
