/*
Class Name: AIAssistGlobalUtilityTest

=================================================================
=================================================================

Description: Testing utility for AIAssistGlobalUtility: stamping PublicId__c (Agent and Conversation only) and DeveloperName__c (the five configuration objects).

=================================================================
=================================================================
Applicable Classes:

AIAssistGlobalUtility

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAssistGlobalUtilityTest {
  // testScenario1: generatePublicId gives an agent and a conversation each a UUID, and keeps a Public Id that is already set.
  // testScenario2: Objects that do not have the identifier fields are left alone and nothing is logged: PublicId__c exists only on Agent and Conversation.
  // testScenario3: A bulk of more than two hundred conversations each gets its own Public Id.
  // testScenario4: Empty, null and null-entry input is tolerated, and the record after a null entry is still stamped.
  // testScenario5: generateDeveloperName derives the name from Name with single underscores, keeps one that is already set, and cuts a long name to the field length without a trailing underscore.
  // testScenario6: A Developer Name that collides with a saved record, in any case, gets a short suffix and still fits the field.
  // testScenario7: Two hundred and one records with the same name get 201 different Developer Names from a single uniqueness lookup.
  // testScenario8: A Data Source and a Workflow Action, whose Name is an auto-number, derive their Developer Name from SourceName__c and ActionName__c, and a record with no name yet is skipped.
  // testScenario9: A name made entirely of characters that cannot be kept still gets a usable Developer Name.
  // testScenario10: Stamping does not depend on the field-level security of the running user: a user who can only read the fields still gets an agent stamped.
  // testScenario11: toIntegerSet parses a comma separated setting into numbers, skipping blank and non-numeric entries, and returns an empty set for blank input.

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
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, false);
    agents[1].PublicId__c = 'existing-public-id';
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      null,
      1,
      false
    );

    Test.startTest();
    AIAssistGlobalUtility.generatePublicId(
      new List<SObject>{ agents[0], agents[1], conversations[0] }
    );
    Test.stopTest();

    String uuidPattern = '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}';

    Assert.isTrue(
      Pattern.matches(uuidPattern, agents[0].PublicId__c),
      'The agent gets a UUID.'
    );
    Assert.isTrue(
      Pattern.matches(uuidPattern, conversations[0].PublicId__c),
      'The conversation gets a UUID.'
    );
    Assert.areNotEqual(
      agents[0].PublicId__c,
      conversations[0].PublicId__c,
      'Two records never share an identifier.'
    );
    Assert.areEqual(
      'existing-public-id',
      agents[1].PublicId__c,
      'An existing Public Id is not overwritten.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIConversationMessage__c message = AIAssistTestDataFactory.createAIConversationMessages(
      null,
      1,
      1,
      false
    )[0];
    AIExecutionStep__c step = AIAssistTestDataFactory.createAIExecutionSteps(
      null,
      1,
      false
    )[0];
    Account account = AIAssistTestDataFactory.createAccounts(1, false)[0];
    String accountName = account.Name;

    Test.startTest();
    AIAssistGlobalUtility.generatePublicId(
      new List<SObject>{ message, step, account }
    );
    AIAssistGlobalUtility.generateDeveloperName(
      new List<SObject>{ message, step, account }
    );
    Test.stopTest();

    Assert.areEqual(
      accountName,
      account.Name,
      'A subscriber record is untouched.'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIPlatformLog__c],
      'Skipping an object without the field is not an error.'
    );
  }

  @IsTest
  static void testScenario3() {
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      null,
      201,
      false
    );

    Test.startTest();
    AIAssistGlobalUtility.generatePublicId(conversations);
    Test.stopTest();

    Set<String> publicIds = new Set<String>();
    for (AIConversation__c conversation : conversations)
      publicIds.add(conversation.PublicId__c);

    Assert.areEqual(
      201,
      publicIds.size(),
      'Every record in a bulk gets its own identifier.'
    );
    Assert.isFalse(publicIds.contains(null), 'Every record gets one.');
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];

    Test.startTest();
    AIAssistGlobalUtility.generatePublicId(null);
    AIAssistGlobalUtility.generatePublicId(new List<SObject>());
    AIAssistGlobalUtility.generateDeveloperName(null);
    AIAssistGlobalUtility.generateDeveloperName(new List<SObject>());
    AIAssistGlobalUtility.generatePublicId(new List<SObject>{ null, agent });
    AIAssistGlobalUtility.generateDeveloperName(
      new List<SObject>{ null, agent }
    );
    Test.stopTest();

    Assert.isNotNull(
      agent.PublicId__c,
      'One bad entry does not abort the rest of the batch.'
    );
    Assert.isNotNull(
      agent.DeveloperName__c,
      'The same holds for the Developer Name.'
    );
  }

  @IsTest
  static void testScenario5() {
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(3, false);
    agents[0].Name = '  My Agent 123!! ';
    agents[1].Name = 'Has A Name';
    agents[1].DeveloperName__c = 'Chosen_By_Admin';
    agents[2]
      .Name = 'A very long agent name that goes on and on and on well past the seventy five characters the field can hold';

    Test.startTest();
    AIAssistGlobalUtility.generateDeveloperName(agents);
    Test.stopTest();

    Assert.areEqual(
      'My_Agent_123',
      agents[0].DeveloperName__c,
      'Non-alphanumerics become single underscores, none at either end.'
    );
    Assert.areEqual(
      'Chosen_By_Admin',
      agents[1].DeveloperName__c,
      'An existing Developer Name is not overwritten.'
    );
    Assert.isTrue(
      agents[2].DeveloperName__c.length() <= 75,
      'The value fits the field, or the save would fail. Length: ' +
      agents[2].DeveloperName__c.length()
    );
    Assert.isFalse(
      agents[2].DeveloperName__c.endsWith('_'),
      'Cutting does not leave a trailing underscore.'
    );
    Assert.isTrue(
      agents[2].DeveloperName__c.startsWith('A_very_long_agent_name'),
      'The start of the name is kept.'
    );
  }

  @IsTest
  static void testScenario6() {
    AIAgent__c savedAgent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
    savedAgent.Name = 'Support Agent';
    insert savedAgent;

    List<AIAgent__c> newAgents = AIAssistTestDataFactory.createAIAgents(
      2,
      false
    );
    newAgents[0].Name = 'Support Agent';
    newAgents[1].Name = 'SUPPORT AGENT';

    Test.startTest();
    AIAssistGlobalUtility.generateDeveloperName(newAgents);
    Test.stopTest();

    Assert.areEqual(
      'Support_Agent',
      [SELECT DeveloperName__c FROM AIAgent__c WHERE Id = :savedAgent.Id]
      .DeveloperName__c,
      'The saved agent kept the plain name.'
    );
    Assert.isTrue(
      newAgents[0].DeveloperName__c.startsWith('Support_Agent_'),
      'The name is taken, so a suffix is added.'
    );
    Assert.isTrue(
      newAgents[1].DeveloperName__c.startsWith('SUPPORT_AGENT_'),
      'The unique setting ignores case, so this is a collision too.'
    );
    Assert.areNotEqual(
      newAgents[0].DeveloperName__c.toLowerCase(),
      newAgents[1].DeveloperName__c.toLowerCase(),
      'And the two new records do not collide with each other.'
    );
  }

  @IsTest
  static void testScenario7() {
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      201,
      false
    );
    for (AIAgent__c agent : agents)
      agent.Name = 'Bulk Agent';

    Integer queriesBefore = Limits.getQueries();

    Test.startTest();
    AIAssistGlobalUtility.generateDeveloperName(agents);
    Integer queriesUsed = Limits.getQueries() - queriesBefore;
    Test.stopTest();

    Set<String> names = new Set<String>();
    for (AIAgent__c agent : agents)
      names.add(agent.DeveloperName__c.toLowerCase());

    Assert.areEqual(201, names.size(), 'Every agent gets its own name.');
    Assert.areEqual(
      'Bulk_Agent',
      agents[0].DeveloperName__c,
      'The first record keeps the plain name.'
    );
    Assert.isTrue(
      queriesUsed <= 1,
      'Uniqueness is checked once for the whole batch, not once per record. Queries used: ' +
      queriesUsed
    );
  }

  @IsTest
  static void testScenario8() {
    AIDataSource__c namedSource = AIAssistTestDataFactory.createAIDataSources(
      1,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      false
    )[0];
    namedSource.SourceName__c = 'Open cases';
    AIDataSource__c unnamedSource = AIAssistTestDataFactory.createAIDataSources(
      1,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      false
    )[0];
    unnamedSource.SourceName__c = null;
    AIWorkflowAction__c namedAction = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'Some_Flow',
      false
    )[0];
    namedAction.ActionName__c = 'Create follow-up task';

    Test.startTest();
    AIAssistGlobalUtility.generateDeveloperName(
      new List<SObject>{ namedSource, unnamedSource, namedAction }
    );
    Test.stopTest();

    Assert.areEqual(
      'Open_cases',
      namedSource.DeveloperName__c,
      'The Source Name is used.'
    );
    Assert.areEqual(
      'Create_follow_up_task',
      namedAction.DeveloperName__c,
      'The Action Name is used.'
    );
    Assert.isNull(
      unnamedSource.DeveloperName__c,
      'With nothing to derive from, no Developer Name is made up.'
    );
  }

  @IsTest
  static void testScenario9() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
    agent.Name = '日本語のエージェント';

    Test.startTest();
    AIAssistGlobalUtility.generateDeveloperName(new List<SObject>{ agent });
    Test.stopTest();

    Assert.isTrue(
      agent.DeveloperName__c.startsWith('Record_'),
      'A name of non-Latin script still needs a usable value. Got: ' +
      agent.DeveloperName__c
    );
  }

  @IsTest
  static void testScenario10() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, false)[0];
    agent.Name = 'Secured Agent';

    System.runAs(chatUser) {
      Test.startTest();
      AIAssistGlobalUtility.generatePublicId(new List<SObject>{ agent });
      AIAssistGlobalUtility.generateDeveloperName(new List<SObject>{ agent });
      Test.stopTest();
    }

    Assert.isNotNull(
      agent.PublicId__c,
      'A user without edit access to the field still gets a Public Id.'
    );
    Assert.areEqual(
      'Secured_Agent',
      agent.DeveloperName__c,
      'And a Developer Name.'
    );
  }

  @IsTest
  static void testScenario11() {
    Test.startTest();
    Set<Integer> parsed = AIAssistGlobalUtility.toIntegerSet(
      '200, 201,abc,, 202 '
    );
    Set<Integer> fromBlank = AIAssistGlobalUtility.toIntegerSet('');
    Set<Integer> fromNull = AIAssistGlobalUtility.toIntegerSet(null);
    Set<Integer> noneNumeric = AIAssistGlobalUtility.toIntegerSet('none, x');
    Test.stopTest();

    Assert.areEqual(
      new Set<Integer>{ 200, 201, 202 },
      parsed,
      'Numbers are kept; blanks and words are skipped.'
    );
    Assert.isTrue(fromBlank.isEmpty(), 'Blank input gives an empty set.');
    Assert.isTrue(fromNull.isEmpty(), 'Null input gives an empty set.');
    Assert.isTrue(noneNumeric.isEmpty(), 'Words alone give an empty set.');
  }
}
