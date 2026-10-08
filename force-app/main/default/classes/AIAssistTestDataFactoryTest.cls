/*
Class Name: AIAssistTestDataFactoryTest

=================================================================
=================================================================

Description: Testing utility for AIAssistTestDataFactory: every builder produces records the object model accepts, so a failing test is never a failing fixture.

=================================================================
=================================================================
Applicable Classes:

AIAssistTestDataFactory

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAssistTestDataFactoryTest {
  // testScenario1: createUsers builds standard users and assignPermissionSet gives each the permission set, so a test can run as a real end user.
  // testScenario2: The configuration builders insert valid records: an active model, an agent open to all users, a template, data sources, workflow actions and their links, with unique Developer Names stamped by the triggers.
  // testScenario3: The conversation, message, settings, PII and step builders insert valid records, and an AI Agent message goes in through the package gateway.

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
    Test.startTest();
    List<User> users = AIAssistTestDataFactory.createUsers(2, true);
    AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
    Test.stopTest();

    Assert.isNotNull(users[0].Id, 'The users are inserted.');
    Assert.areNotEqual(
      users[0].Username,
      users[1].Username,
      'Usernames are unique.'
    );
    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE AssigneeId IN :users AND PermissionSet.Name = 'AIAssistUser'
      ],
      'Each user holds the permission set.'
    );
    Assert.areEqual(
      0,
      AIAssistTestDataFactory.createUsers(0, true).size(),
      'Asking for none builds none.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];

    Test.startTest();
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      2,
      model.Id,
      true
    );
    List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(
      agents[0].Id,
      1,
      true
    );
    List<AIDataSource__c> dataSources = AIAssistTestDataFactory.createAIDataSources(
      2,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      true
    );
    List<AIWorkflowAction__c> actions = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'Some_Flow',
      true
    );
    List<AIAgentDataSource__c> sourceLinks = AIAssistTestDataFactory.createAIAgentDataSources(
      agents[0].Id,
      dataSources,
      true
    );
    List<AIAgentWorkflowAction__c> actionLinks = AIAssistTestDataFactory.createAIAgentWorkflowActions(
      agents[0].Id,
      actions,
      true
    );
    List<AIAgentAssignment__c> assignments = AIAssistTestDataFactory.createAIAgentAssignments(
      agents[1].Id,
      'AIAssistUser',
      true
    );
    Test.stopTest();

    List<AIAgent__c> savedAgents = [
      SELECT DeveloperName__c, PublicId__c, IsActive__c, AccessMode__c
      FROM AIAgent__c
      WHERE Id IN :agents
    ];

    Assert.areEqual(2, savedAgents.size(), 'Both agents are saved.');
    Assert.isTrue(
      savedAgents[0].IsActive__c &&
      savedAgents[0].AccessMode__c ==
      AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS,
      'Agents are active and open to all users.'
    );
    Assert.isNotNull(
      savedAgents[0].DeveloperName__c,
      'The trigger stamped a Developer Name.'
    );
    Assert.areNotEqual(
      savedAgents[0].DeveloperName__c,
      savedAgents[1].DeveloperName__c,
      'Developer Names are unique.'
    );
    Assert.areEqual(1, templates.size() + 0, 'One template.');
    Assert.areEqual(2, sourceLinks.size(), 'Both data sources are linked.');
    Assert.areEqual(1, actionLinks.size(), 'The action is linked.');
    Assert.areEqual(
      1,
      assignments.size(),
      'The permission set assignment is built.'
    );
    Assert.isNotNull(dataSources[0].Id, 'Data sources are inserted.');
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

    Test.startTest();
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    List<AIConversationMessage__c> userMessages = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      5,
      2,
      true
    );
    List<AIConversationMessage__c> replies = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      7,
      1,
      true
    );
    List<AIExecutionStep__c> steps = AIAssistTestDataFactory.createAIExecutionSteps(
      replies[0].Id,
      2,
      true
    );
    List<AIUserSettings__c> settings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      true
    );
    List<AIPIIRegistry__c> registries = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      'Contact',
      true
    );
    List<AIPIIFieldMetadata__c> piiFields = AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registries[0].Id,
      'Contact',
      'Email',
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      true
    );
    List<AIPIIMapping__c> mappings = AIAssistTestDataFactory.createAIPIIMappings(
      conversation.Id,
      new Map<String, String>{ 'a@example.com' => 'fake@example.com' },
      true
    );
    AIPiiDataMaskingRule__mdt rule = AIAssistTestDataFactory.createAIPiiMaskingRule(
      AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST,
      'x,y',
      true
    );
    Test.stopTest();

    Assert.areEqual(
      chatUser.Id,
      [SELECT OwnerId FROM AIConversation__c WHERE Id = :conversation.Id]
      .OwnerId,
      'The conversation belongs to the given owner.'
    );
    Assert.areEqual(2, userMessages.size(), 'Two user messages.');
    Assert.areEqual(
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      [SELECT Sender__c FROM AIConversationMessage__c WHERE Id = :replies[0].Id]
      .Sender__c,
      'The AI message was inserted as the package.'
    );
    Assert.areEqual(2, steps.size(), 'Two steps.');
    Assert.areEqual(1, settings.size(), 'One settings row.');
    Assert.isNotNull(piiFields[0].Id, 'The PII field metadata is saved.');
    Assert.isNotNull(mappings[0].Id, 'The PII mapping is saved.');
    Assert.isTrue(
      rule.IsActive__c,
      'The in-memory masking rule is built active.'
    );
  }
}
