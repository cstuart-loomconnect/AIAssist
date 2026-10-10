/*
Class Name: AIPromptTemplateTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIPromptTemplateTrigger and AIPromptTemplateTriggerHandler: the version that goes up only when the wording the model is given changes.

=================================================================
=================================================================
Applicable Classes:

AIPromptTemplateTriggerHandler: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIPromptTemplateTriggerHandlerTest {
  // testScenario1: Change the prompt, system context, tone and exclusion rules on four templates -> each version goes up by one.
  // testScenario2: Change something that is not the wording -> the version is left alone.
  // testScenario3: Change the wording on 201 templates in bulk -> every one is versioned once with no queries in the update.
  // testScenario4: Settings switched off, wording changed, and the handler called with null input -> nothing is versioned and nothing is thrown.
  // testScenario5: The handler throws unexpectedly during a wording change -> the version is not raised and one platform log is written.

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
    // [1] Create four inactive templates and note their starting version
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

    // [2] Change the prompt, context, tone and exclusion rules, one per template
    Test.startTest();
    templates[0].AIPrompt__c = 'A new prompt.';
    templates[1].AISystemContext__c = 'New context.';
    templates[2].AITone__c = 'Formal';
    templates[3].AIExclusionRules__c = 'Never discuss pricing.';
    update templates;
    Test.stopTest();

    // [3] Read the templates back
    List<AIPromptTemplate__c> savedTemplates = [
      SELECT Version__c
      FROM AIPromptTemplate__c
      WHERE Id IN :templates
    ];

    // [4] Check each version went up by one
    Assert.areEqual(
      4,
      savedTemplates.size(),
      'All four templates should be saved.'
    );
    for (AIPromptTemplate__c saved : savedTemplates) {
      Assert.areEqual(
        startVersion + 1,
        saved.Version__c,
        'The version should go up by one for the change.'
      );
    }
  }

  @IsTest
  static void testScenario2() {
    // [1] Create a template and note its starting version
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

    // [2] Change something that is not the wording
    Test.startTest();
    template.IsActive__c = false;
    update template;
    Test.stopTest();

    // [3] Read the template back
    AIPromptTemplate__c saved = [
      SELECT Version__c
      FROM AIPromptTemplate__c
      WHERE Id = :template.Id
    ];

    // [4] Check the version is unchanged
    Assert.areEqual(
      startVersion,
      saved.Version__c,
      'The version should be unchanged when the wording is unchanged.'
    );
  }

  @IsTest
  static void testScenario3() {
    // [1] Create 201 inactive templates
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

    // [2] Change the system context on every template and note the queries used
    Test.startTest();
    for (AIPromptTemplate__c template : templates)
      template.AISystemContext__c = 'New context';
    update templates;
    queries = Limits.getQueries();
    Test.stopTest();

    // [3] Count the versioned templates
    Integer versionedCount = [
      SELECT COUNT()
      FROM AIPromptTemplate__c
      WHERE Version__c = 2
    ];

    // [4] Check every template was versioned once with no extra queries
    Assert.areEqual(
      201,
      versionedCount,
      'Every template should be versioned once.'
    );
    Assert.isTrue(
      queries <= 3,
      'There should be no queries in the update: ' + queries
    );
  }

  @IsTest
  static void testScenario4() {
    // [1] Create a template, note its version and switch the application off
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

    // [2] Change the wording, then call the handler with null input
    Test.startTest();
    templates[0].AIPrompt__c = 'Changed while off.';
    update templates;
    AIPromptTemplateTriggerHandler.handleBeforeUpdate(null, null);
    Test.stopTest();

    // [3] Read the template and the logs back
    AIPromptTemplate__c saved = [
      SELECT Version__c
      FROM AIPromptTemplate__c
      WHERE Id = :templates[0].Id
    ];
    Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c];

    // [4] Check the version is unchanged and nothing was logged
    Assert.areEqual(
      startVersion,
      saved.Version__c,
      'The template should not be versioned while the application is switched off.'
    );
    Assert.areEqual(
      0,
      logCount,
      'Null input should be ignored without logging.'
    );
  }

  @IsTest
  static void testScenario5() {
    // [1] Create a template, note its version and force the handler to throw
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

    AIPromptTemplateTriggerHandler.isTestCustomExceptionThrown = true;

    // [2] Change the wording
    Test.startTest();
    template.AIPrompt__c = 'Changed while failing.';
    update template;
    Test.stopTest();

    // [3] Read the template and the logs back
    AIPromptTemplate__c saved = [
      SELECT Version__c
      FROM AIPromptTemplate__c
      WHERE Id = :template.Id
    ];
    List<AIPlatformLog__c> logs = [
      SELECT ClassName__c, MethodName__c
      FROM AIPlatformLog__c
    ];

    // [4] Check the version is unchanged and one log names the handler
    Assert.areEqual(
      startVersion,
      saved.Version__c,
      'The version should not be raised when the handler fails.'
    );
    Assert.areEqual(
      1,
      logs.size(),
      'Exactly one platform log should be written.'
    );

    Assert.areEqual(
      'AIPromptTemplateTriggerHandler',
      logs[0].ClassName__c,
      'The log should name the handler class.'
    );
    Assert.areEqual(
      'handleBeforeUpdate',
      logs[0].MethodName__c,
      'The log should name the failing method.'
    );
  }
}
