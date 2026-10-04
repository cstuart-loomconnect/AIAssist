/*
Class Name: AIMessagingSelectorTest

=================================================================
=================================================================

Description: Testing utility for AIMessagingSelector: the system-mode queries on data the end user may not read, and that they are bounded and return only what they should.

=================================================================
=================================================================
Applicable Classes:

AIMessagingSelector

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIMessagingSelectorTest {
  // testScenario1: getAgent and getModel return the agent and the model it uses, and null for a missing Id.
  // testScenario2: getTemplate returns only the active template of the agent, with its version, and null when there is none.
  // testScenario3: getDataSources returns only active, linked data sources and caps the list, so an agent with many tools linked cannot bloat every request.
  // testScenario4: getActions returns only the active actions linked to the agent.
  // testScenario5: getUserSettings returns the settings row of a user, and null for a user without one or no user.
  // testScenario6: isAssigned is true for an active assignment to the user or to a permission set they hold, and false for an inactive one, another user or no agent.
  // testScenario7: getTermsStatus distinguishes a user who accepted the current version, one who accepted only an earlier version, one who never accepted, and no terms configured.
  // testScenario8: The usage queries count a user's active conversations, sum their usage for a day, sum the organisation's day and month, and lock a usage row by key.
  // testScenario10: A rule reaches an agent through an active assignment or because it applies to all agents; an inactive assignment, an inactive rule and another agent's rule do not.
  // testScenario11: getUserSettings combines the usage policies of a user (assigned to them, to a permission set they hold, or the default) with their own row as an personalSettings.
  // testScenario12: An agent is offered on its own Object Type and on every object added to it, a general agent on any object, and an agent added to other objects only is not general.
  // testScenario13: A permission set held only through a permission set group still matches an agent assignment and a usage policy assignment, by the permission set's name or the group's, and a user outside the group does not match.
  // testScenario9: countPendingJobs answers with a count, and the trigger queries return nothing for no input and the rows asked for otherwise.

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
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];

    Test.startTest();
    AIAgent__c loadedAgent = AIMessagingSelector.getAgent(agent.Id);
    AIModelConfiguration__c loadedModel = AIMessagingSelector.getModelConfiguration(
      model.Id
    );
    AIAgent__c noAgent = AIMessagingSelector.getAgent(null);
    AIModelConfiguration__c noModel = AIMessagingSelector.getModelConfiguration(
      null
    );
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS,
      loadedAgent.AccessMode__c,
      'The access mode is read, which the AI Assist User permission set cannot do.'
    );
    Assert.areEqual(
      model.Id,
      loadedAgent.AIModelConfiguration__c,
      'The agent names its model.'
    );
    Assert.areEqual(
      'test-model',
      loadedModel.ModelIdentifier__c,
      'The model configuration is read.'
    );
    Assert.isNull(noAgent, 'No Id, no agent.');
    Assert.isNull(noModel, 'No Id, no model.');
  }

  @IsTest
  static void testScenario2() {
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      2,
      model.Id,
      true
    );
    List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(
      agents[0].Id,
      2,
      false
    );
    templates[0].IsActive__c = false;
    insert templates;

    Test.startTest();
    AIPromptTemplate__c active = AIMessagingSelector.getActivePromptTemplate(
      agents[0].Id
    );
    AIPromptTemplate__c none = AIMessagingSelector.getActivePromptTemplate(
      agents[1].Id
    );
    AIPromptTemplate__c noAgent = AIMessagingSelector.getActivePromptTemplate(
      null
    );
    Test.stopTest();

    Assert.areEqual(
      templates[1].Id,
      active.Id,
      'Only the active template is used.'
    );
    Assert.areEqual(
      1,
      active.Version__c,
      'The version is read so it can be stamped on the reply.'
    );
    Assert.isNull(none, 'No active template is a valid state.');
    Assert.isNull(noAgent, 'No Id, no template.');
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    Integer linkedCount = AIAssistApplicationConstants.MAX_TOOLS_PER_KIND + 6;
    List<AIDataSource__c> dataSources = AIAssistTestDataFactory.createAIDataSources(
      linkedCount + 2,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      false
    );
    dataSources[linkedCount].IsActive__c = false;
    insert dataSources;
    AIAssistTestDataFactory.createAIAgentDataSources(
      agent.Id,
      new List<AIDataSource__c>{ dataSources[linkedCount] },
      true
    );
    dataSources.remove(linkedCount + 1);
    List<AIDataSource__c> linkedSources = new List<AIDataSource__c>();
    for (Integer i = 0; i < linkedCount; i++)
      linkedSources.add(dataSources[i]);
    AIAssistTestDataFactory.createAIAgentDataSources(
      agent.Id,
      linkedSources,
      true
    );

    Test.startTest();
    List<AIDataSource__c> loaded = AIMessagingSelector.getAssignedDataSources(
      agent.Id
    );
    List<AIDataSource__c> none = AIMessagingSelector.getAssignedDataSources(
      null
    );
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.MAX_TOOLS_PER_KIND,
      loaded.size(),
      'The list is capped.'
    );
    Assert.isFalse(
      new Map<Id, AIDataSource__c>(loaded)
        .containsKey(dataSources[linkedCount].Id),
      'An inactive data source is never offered to the model.'
    );
    Assert.isTrue(none.isEmpty(), 'No agent, no tools.');
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    List<AIWorkflowAction__c> actions = AIAssistTestDataFactory.createAIWorkflowActions(
      2,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'Some_Flow',
      true
    );
    AIAssistTestDataFactory.createAIAgentWorkflowActions(
      agent.Id,
      new List<AIWorkflowAction__c>{ actions[0] },
      true
    );

    Test.startTest();
    List<AIWorkflowAction__c> loaded = AIMessagingSelector.getAssignedActions(
      agent.Id
    );
    List<AIWorkflowAction__c> none = AIMessagingSelector.getAssignedActions(
      null
    );
    Test.stopTest();

    Assert.areEqual(1, loaded.size(), 'Only the linked action is offered.');
    Assert.areEqual(actions[0].Id, loaded[0].Id, 'It is the linked one.');
    Assert.isTrue(none.isEmpty(), 'No agent, no actions.');
  }

  @IsTest
  static void testScenario5() {
    List<User> users = AIAssistTestDataFactory.createUsers(2, true);
    AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(
      users[0].Id,
      false
    )[0];
    settings.DebugModeEnabled__c = true;
    insert settings;

    Test.startTest();
    AIUserSettings__c found = AIMessagingSelector.getUserSettings(users[0].Id);
    AIUserSettings__c absent = AIMessagingSelector.getUserSettings(users[1].Id);
    AIUserSettings__c noUser = AIMessagingSelector.getUserSettings(null);
    Test.stopTest();

    Assert.isTrue(found.DebugModeEnabled__c, 'The row is found by user.');
    Assert.isNull(absent, 'No row means no personal limits.');
    Assert.isNull(noUser, 'No user, no settings.');
  }

  @IsTest
  static void testScenario6() {
    List<User> users = AIAssistTestDataFactory.createUsers(4, true);
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ users[2] },
      'AIAssistUser'
    );
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      2,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    );
    List<AIAgentAssignment__c> direct = AIAssistTestDataFactory.createAIAgentAssignments(
      agents[0].Id,
      new List<User>{ users[0], users[1] },
      false
    );
    direct[1].IsActive__c = false;
    insert direct;
    AIAssistTestDataFactory.createAIAgentAssignments(
      agents[1].Id,
      'AIAssistUser',
      true
    );

    Test.startTest();
    Boolean isDirect = AIMessagingSelector.isUserAssignedToAgent(
      agents[0].Id,
      users[0].Id
    );
    Boolean isInactive = AIMessagingSelector.isUserAssignedToAgent(
      agents[0].Id,
      users[1].Id
    );
    Boolean isOther = AIMessagingSelector.isUserAssignedToAgent(
      agents[0].Id,
      users[3].Id
    );
    Boolean isByPermissionSet = AIMessagingSelector.isUserAssignedToAgent(
      agents[1].Id,
      users[2].Id
    );
    Boolean isPermissionSetMissing = AIMessagingSelector.isUserAssignedToAgent(
      agents[1].Id,
      users[3].Id
    );
    Boolean isNoAgent = AIMessagingSelector.isUserAssignedToAgent(
      null,
      users[0].Id
    );
    Test.stopTest();

    Assert.isTrue(isDirect, 'An active assignment to the user.');
    Assert.isFalse(isInactive, 'An inactive assignment gives no access.');
    Assert.isFalse(isOther, 'Another user is not covered.');
    Assert.isTrue(
      isByPermissionSet,
      'A user holding the assigned permission set has access.'
    );
    Assert.isFalse(isPermissionSetMissing, 'A user without it does not.');
    Assert.isFalse(isNoAgent, 'No agent, no assignment.');
  }

  @IsTest
  static void testScenario7() {
    List<User> users = AIAssistTestDataFactory.createUsers(3, true);
    AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
    System.runAs(users[0]) {
      insert AIAssistTestDataFactory.createAITermsAcknowledgments(
        users[0].Id,
        'v2',
        1,
        false
      );
    }
    System.runAs(users[1]) {
      insert AIAssistTestDataFactory.createAITermsAcknowledgments(
        users[1].Id,
        'v1',
        1,
        false
      );
    }

    Test.startTest();
    String accepted = AIMessagingSelector.getTermsAcceptanceStatus(
      users[0].Id,
      'v2'
    );
    String outdated = AIMessagingSelector.getTermsAcceptanceStatus(
      users[1].Id,
      'v2'
    );
    String never = AIMessagingSelector.getTermsAcceptanceStatus(
      users[2].Id,
      'v2'
    );
    String noTerms = AIMessagingSelector.getTermsAcceptanceStatus(
      users[2].Id,
      null
    );
    Test.stopTest();

    Assert.areEqual(
      AIMessagingSelector.TERMS_ACCEPTED,
      accepted,
      'The current version was accepted.'
    );
    Assert.areEqual(
      AIMessagingSelector.TERMS_OUTDATED,
      outdated,
      'An earlier version was accepted.'
    );
    Assert.areEqual(AIMessagingSelector.TERMS_NONE, never, 'Never accepted.');
    Assert.areEqual(
      AIMessagingSelector.TERMS_ACCEPTED,
      noTerms,
      'With no terms configured there is nothing to accept.'
    );
  }

  @IsTest
  static void testScenario8() {
    List<User> users = AIAssistTestDataFactory.createUsers(2, true);
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      users[0].Id,
      3,
      false
    );
    conversations[2]
      .Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
    conversations[2]
      .ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED;
    conversations[2].ConversationClosedTimestamp__c = Datetime.now();
    insert conversations;
    AIUsageDaily__c firstUsage = AIAssistTestDataFactory.createAIUsageDailies(
      users[0].Id,
      agent.Id,
      agent.AIModelConfiguration__c,
      1,
      false
    )[0];
    firstUsage.ConversationCount__c = 2;
    firstUsage.InputTokens__c = 100;
    firstUsage.OutputTokens__c = 50;
    firstUsage.MessageCount__c = 3;
    AIUsageDaily__c secondUsage = AIAssistTestDataFactory.createAIUsageDailies(
      users[1].Id,
      agent.Id,
      agent.AIModelConfiguration__c,
      1,
      false
    )[0];
    secondUsage.InputTokens__c = 10;
    secondUsage.OutputTokens__c = 10;
    secondUsage.MessageCount__c = 1;
    insert new List<AIUsageDaily__c>{ firstUsage, secondUsage };
    Date today = AIAssistGlobalUtility.getOrgToday();

    Test.startTest();
    Integer active = AIMessagingSelector.countActiveConversations(users[0].Id);
    AIMessagingSelector.UsageTotals userUsage = AIMessagingSelector.getUserDailyUsage(
      users[0].Id,
      today
    );
    AIMessagingSelector.UsageTotals yesterdayUsage = AIMessagingSelector.getUserDailyUsage(
      users[0].Id,
      today.addDays(-1)
    );
    AIMessagingSelector.OrgUsage orgUsage = AIMessagingSelector.getOrganisationUsage(
      today
    );
    AIUsageDaily__c lockedRow = AIMessagingSelector.lockDailyUsageRow(
      firstUsage.UsageKey__c
    );
    AIUsageDaily__c missingRow = AIMessagingSelector.lockDailyUsageRow(
      'no-such-key'
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      active,
      'Only the user\'s own Active conversations count.'
    );
    Assert.areEqual(2, userUsage.conversations, 'Conversations started today.');
    Assert.areEqual(150, userUsage.tokens, 'Tokens are input plus output.');
    Assert.areEqual(0, yesterdayUsage.tokens, 'Yesterday has no usage.');
    Assert.areEqual(4, orgUsage.month.messages, 'The month sums every user.');
    Assert.areEqual(170, orgUsage.today.tokens, 'And so does today.');
    Assert.areEqual(
      firstUsage.Id,
      lockedRow.Id,
      'The usage row is found by its key.'
    );
    Assert.isNull(missingRow, 'No row, null.');
  }

  @IsTest
  static void testScenario9() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];

    Test.startTest();
    Integer pending = AIMessagingSelector.countQueuedMessageJobs();
    Map<Id, AIAgent__c> retention = AIMessagingSelector.getAgentRetentionSettings(
      new Set<Id>{ agent.Id }
    );
    List<AIConversation__c> targets = AIMessagingSelector.lockConversationsForRollup(
      new Set<Id>{ conversation.Id }
    );
    Map<Id, AIAgent__c> noRetention = AIMessagingSelector.getAgentRetentionSettings(
      null
    );
    List<AIConversation__c> noTargets = AIMessagingSelector.lockConversationsForRollup(
      new Set<Id>()
    );
    Test.stopTest();

    Assert.isTrue(pending >= 0, 'The count is a number.');
    Assert.isTrue(
      retention.containsKey(agent.Id),
      'The agent\'s retention settings are returned.'
    );
    Assert.areEqual(
      1,
      targets.size(),
      'The conversation is returned, locked, for a roll-up.'
    );
    Assert.isTrue(
      noRetention.isEmpty() && noTargets.isEmpty(),
      'Nothing asked for, nothing returned.'
    );
  }

  @IsTest
  static void testScenario10() {
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
      true
    );
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, true);
    List<AIViolationRule__c> rules = AIAssistTestDataFactory.createAIViolationRules(
      null,
      4,
      AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED,
      false
    );
    rules[1].AppliesToAllAgents__c = true;
    rules[3].IsActive__c = false;
    insert rules;
    List<AIAgentViolationRule__c> links = AIAssistTestDataFactory.createAIAgentViolationRules(
      agents[0].Id,
      new List<AIViolationRule__c>{ rules[0], rules[2], rules[3] },
      false
    );
    links[1].IsActive__c = false;
    insert links;
    AIAssistTestDataFactory.createAIAgentViolationRules(
      agents[1].Id,
      new List<AIViolationRule__c>{ rules[0] },
      true
    );

    Test.startTest();
    Map<Id, AIViolationRule__c> forFirst = new Map<Id, AIViolationRule__c>(
      AIMessagingSelector.getActiveAiEvaluatedRules(agents[0].Id)
    );
    Map<Id, AIViolationRule__c> forSecond = new Map<Id, AIViolationRule__c>(
      AIMessagingSelector.getActiveAiEvaluatedRules(agents[1].Id)
    );
    Test.stopTest();

    Assert.areEqual(
      new Set<Id>{ rules[0].Id, rules[1].Id },
      forFirst.keySet(),
      'The assigned rule and the rule for all agents; not the inactive assignment or the inactive rule.'
    );
    Assert.areEqual(
      new Set<Id>{ rules[0].Id, rules[1].Id },
      forSecond.keySet(),
      'One rule is shared by two agents.'
    );
  }

  @IsTest
  static void testScenario11() {
    List<User> users = AIAssistTestDataFactory.createUsers(3, true);
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ users[1] },
      AIAssistApplicationConstants.PERMISSION_SET_USER
    );
    List<AIUsagePolicy__c> policies = AIAssistTestDataFactory.createAIUsagePolicies(
      3,
      false
    );
    policies[0].MaxTokensPer24Hours__c = 1000;
    policies[0].IsDefault__c = true;
    policies[1].MaxTokensPer24Hours__c = 5000;
    policies[2].MaxTokensPer24Hours__c = 7000;
    policies[2].IsActive__c = false;
    insert policies;
    AIAssistTestDataFactory.createAIUsagePolicyAssignments(
      policies[1].Id,
      new List<User>{ users[0] },
      null,
      true
    );
    AIAssistTestDataFactory.createAIUsagePolicyAssignments(
      policies[1].Id,
      null,
      AIAssistApplicationConstants.PERMISSION_SET_USER,
      true
    );
    AIAssistTestDataFactory.createAIUsagePolicyAssignments(
      policies[2].Id,
      new List<User>{ users[2] },
      null,
      true
    );
    AIUserSettings__c personalSettings = AIAssistTestDataFactory.createAIUserSettings(
      users[0].Id,
      false
    )[0];
    personalSettings.MaxTokensPer24Hours__c = 9000;
    insert personalSettings;

    Test.startTest();
    AIUserSettings__c byUserAndOverride = AIMessagingSelector.getUserSettings(
      users[0].Id
    );
    AIUserSettings__c byPermissionSet = AIMessagingSelector.getUserSettings(
      users[1].Id
    );
    AIUserSettings__c byDefault = AIMessagingSelector.getUserSettings(
      users[2].Id
    );
    Test.stopTest();

    Assert.areEqual(
      9000,
      byUserAndOverride.MaxTokensPer24Hours__c,
      'The personal row overrides the assigned policy.'
    );
    Assert.areEqual(
      5000,
      byPermissionSet.MaxTokensPer24Hours__c,
      'A policy assigned to a permission set the user holds.'
    );
    Assert.areEqual(
      1000,
      byDefault.MaxTokensPer24Hours__c,
      'An inactive policy is ignored, so the default covers the user.'
    );
  }

  @IsTest
  static void testScenario12() {
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      3,
      model.Id,
      false
    );
    // agents[0] is for Account and Contact; agents[1] is general; agents[2] is for Contact only.
    insert agents;
    AIAssistTestDataFactory.createAIAgentObjects(
      agents[0].Id,
      new List<String>{ 'Account', 'Contact' },
      true
    );
    AIAssistTestDataFactory.createAIAgentObjects(
      agents[2].Id,
      new List<String>{ 'Contact' },
      true
    );

    Test.startTest();
    Set<Id> onContact = new Map<Id, AIAgent__c>(
        AIMessagingSelector.getAgentsAvailableForChat(
          'Contact',
          UserInfo.getUserId()
        )
      )
      .keySet();
    Set<Id> onAccount = new Map<Id, AIAgent__c>(
        AIMessagingSelector.getAgentsAvailableForChat(
          'Account',
          UserInfo.getUserId()
        )
      )
      .keySet();
    Set<Id> onCase = new Map<Id, AIAgent__c>(
        AIMessagingSelector.getAgentsAvailableForChat(
          'Case',
          UserInfo.getUserId()
        )
      )
      .keySet();
    Boolean ownType = AIMessagingSelector.agentSupportsObject(
      agents[0].Id,
      'Account',
      'Account'
    );
    Boolean addedType = AIMessagingSelector.agentSupportsObject(
      agents[0].Id,
      'Contact',
      'Contact'
    );
    Boolean otherType = AIMessagingSelector.agentSupportsObject(
      agents[0].Id,
      'Case',
      'Case'
    );
    Boolean general = AIMessagingSelector.agentSupportsObject(
      agents[1].Id,
      'Case',
      'Case'
    );
    Boolean addedOnly = AIMessagingSelector.agentSupportsObject(
      agents[2].Id,
      'Case',
      'Case'
    );
    Test.stopTest();

    Assert.areEqual(
      new Set<Id>{ agents[0].Id, agents[1].Id, agents[2].Id },
      onContact,
      'The agent added to Contact, the one added only to Contact, and the general one.'
    );
    Assert.areEqual(
      new Set<Id>{ agents[0].Id, agents[1].Id },
      onAccount,
      'The agent for Account and the general agent; the Contact-only agent is not general.'
    );
    Assert.areEqual(
      new Set<Id>{ agents[1].Id },
      onCase,
      'Only the general agent.'
    );
    Assert.isTrue(ownType && addedType, 'Each object it was added to.');
    Assert.isFalse(otherType, 'An object it was never given.');
    Assert.isTrue(general, 'No object configured means every object.');
    Assert.isFalse(
      addedOnly,
      'Objects were configured and this is not one of them.'
    );
  }

  @IsTest
  static void testScenario13() {
    List<User> users = AIAssistTestDataFactory.createUsers(2, true);
    AIAssistTestDataFactory.assignPermissionSetGroup(
      new List<User>{ users[0] },
      'AIAssistTestGroup',
      'AIAssistUser'
    );
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      2,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    );
    AIAssistTestDataFactory.createAIAgentAssignments(
      agents[0].Id,
      'AIAssistUser',
      true
    );
    AIAssistTestDataFactory.createAIAgentAssignments(
      agents[1].Id,
      'AIAssistTestGroup',
      true
    );
    AIUsagePolicy__c restrictive = AIAssistTestDataFactory.createAIUsagePolicies(
      1,
      false
    )[0];
    restrictive.MaxTokensPer24Hours__c = 10;
    insert restrictive;
    AIAssistTestDataFactory.createAIUsagePolicyAssignments(
      restrictive.Id,
      null,
      'AIAssistUser',
      true
    );
    AIUsagePolicy__c looser = AIAssistTestDataFactory.createAIUsagePolicies(
      1,
      false
    )[0];
    looser.MaxTokensPer24Hours__c = 1000000;
    looser.IsDefault__c = true;
    insert looser;

    Test.startTest();
    Boolean viaMember = AIMessagingSelector.isUserAssignedToAgent(
      agents[0].Id,
      users[0].Id
    );
    Boolean viaGroup = AIMessagingSelector.isUserAssignedToAgent(
      agents[1].Id,
      users[0].Id
    );
    Boolean outsideGroup = AIMessagingSelector.isUserAssignedToAgent(
      agents[0].Id,
      users[1].Id
    );
    Set<Id> assignedAgents = AIMessagingSelector.getAgentIdsAssignedToUser(
      users[0].Id,
      new Set<Id>{ agents[0].Id, agents[1].Id }
    );
    AIUserSettings__c inGroup = AIMessagingSelector.getUserSettings(
      users[0].Id
    );
    AIUserSettings__c notInGroup = AIMessagingSelector.getUserSettings(
      users[1].Id
    );
    Test.stopTest();

    Assert.isTrue(
      viaMember,
      'The permission set inside the group matches an assignment to it.'
    );
    Assert.isTrue(viaGroup, 'The group itself matches an assignment to it.');
    Assert.isFalse(outsideGroup, 'A user outside the group does not match.');
    Assert.areEqual(2, assignedAgents.size(), 'Both agents are open.');
    Assert.areEqual(
      10,
      inGroup.MaxTokensPer24Hours__c,
      'The restrictive policy applies through the group instead of the looser default.'
    );
    Assert.areEqual(
      1000000,
      notInGroup.MaxTokensPer24Hours__c,
      'A user outside the group falls back to the default.'
    );
  }
}
