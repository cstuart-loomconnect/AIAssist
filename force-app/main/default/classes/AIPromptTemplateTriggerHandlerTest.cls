/*
Class Name: AIPromptTemplateTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIPromptTemplateTrigger and AIPromptTemplateTriggerHandler: the version that goes up only when the wording the model is given changes.

=================================================================
=================================================================
Applicable Classes:

AIPromptTemplateTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Developer Name scenarios removed: templates no longer have one.
*/

@IsTest
private class AIPromptTemplateTriggerHandlerTest {
  // testScenario2: Changing the prompt, the system context, the tone or the exclusion rules each goes up the version by one.
  // testScenario3: Changing something that is not the wording leaves the version alone.
  // testScenario5: Bulk: a bulk wording change versions every one once.
  // testScenario6: Switched off, nothing is versioned, and the handler ignores empty input.
  // testScenario7: An unexpected failure inside the handler is logged and never stops the save.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(
      agent.Id,
      4,
      false
    );
    for (AIPromptTemplate__c template : templates)
      template.IsActive__c = false;
    insert templates;
    Decimal startVersion = [
      SELECT Version__c
      FROM AIPromptTemplate__c
      WHERE Id = :templates[0].Id
    ]
    .Version__c;

    Test.startTest();
    templates[0].AIPrompt__c = 'A new prompt.';
    templates[1].AISystemContext__c = 'New context.';
    templates[2].AITone__c = 'Formal';
    templates[3].AIExclusionRules__c = 'Never discuss pricing.';
    update templates;
    Test.stopTest();

    for (AIPromptTemplate__c saved : [
      SELECT Version__c
      FROM AIPromptTemplate__c
      WHERE Id IN :templates
    ])
      Assert.areEqual(
        startVersion + 1,
        saved.Version__c,
        'One version for the change.'
      );
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(
      agent.Id,
      1,
      true
    )[0];
    Decimal startVersion = [
      SELECT Version__c
      FROM AIPromptTemplate__c
      WHERE Id = :template.Id
    ]
    .Version__c;

    Test.startTest();
    template.IsActive__c = false;
    update template;
    Test.stopTest();

    Assert.areEqual(
      startVersion,
      [SELECT Version__c FROM AIPromptTemplate__c WHERE Id = :template.Id]
      .Version__c,
      'Unchanged.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(
      agent.Id,
      201,
      false
    );
    for (AIPromptTemplate__c template : templates)
      template.IsActive__c = false;
    insert templates;
    Integer queries;

    Test.startTest();
    for (AIPromptTemplate__c template : templates)
      template.AISystemContext__c = 'New context';
    update templates;
    queries = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(
      201,
      [SELECT COUNT() FROM AIPromptTemplate__c WHERE Version__c = 2],
      'Every one was versioned once.'
    );
    Assert.isTrue(queries <= 3, 'No queries in the update: ' + queries);
  }

  @IsTest
  static void testScenario6() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(
      agent.Id,
      1,
      true
    );
    Decimal startVersion = [
      SELECT Version__c
      FROM AIPromptTemplate__c
      WHERE Id = :templates[0].Id
    ]
    .Version__c;
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;

    Test.startTest();
    templates[0].AIPrompt__c = 'Changed while off.';
    update templates;
    AIPromptTemplateTriggerHandler.handleBeforeUpdate(null, null);
    Test.stopTest();

    Assert.areEqual(
      startVersion,
      [SELECT Version__c FROM AIPromptTemplate__c WHERE Id = :templates[0].Id]
      .Version__c,
      'Not versioned.'
    );
  }

  @IsTest
  static void testScenario7() {
    AIPromptTemplateTriggerHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    try {
      AIPromptTemplateTriggerHandler.handleBeforeUpdate(
        new Map<Id, AIPromptTemplate__c>(),
        new Map<Id, AIPromptTemplate__c>()
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
        WHERE ClassName__c = 'AIPromptTemplateTriggerHandler'
      ],
      'Logged once.'
    );
  }
}
