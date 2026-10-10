/*
Class Name: AIConversationVisibilityServiceTest

=================================================================
=================================================================

Description: Testing utility for AIConversationVisibilityService: who may read a conversation they did not start.

=================================================================
=================================================================
Applicable Classes:

AIConversationVisibilityService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Every scenario runs as the viewer: the service reads in user mode, so sharing decides first. All Conversations with and without View All or the custom permission.
*/

@IsTest
private class AIConversationVisibilityServiceTest {
  // testScenario1: A blank, missing or unrecognised scope is the narrowest one; the two wider scopes are kept.
  // testScenario2: The starter always reads their own conversation; a Private agent shows it to nobody else, even a viewer with View All and the All Conversations scope.
  // testScenario3: All Conversations on a Global agent reaches another user's conversation for a viewer with View All, and nobody's for a viewer with neither View All nor the custom permission.
  // testScenario4: All Conversations with the custom permission and no View All reaches only what sharing gives: a subordinate's conversation, not a peer's.
  // testScenario5: My Subordinates Conversations reaches users in a role below the viewer's, at any depth, and not a peer, a user without a role or the viewer's manager.
  // testScenario6: My Conversations Only, no settings, and a wrong or missing Id are all "not found", even for a viewer sharing would let read the conversation.
  // testScenario7: A conversation about a value that is not a record Id is not shown to another user.
  // testScenario8: getSharedConversations lists other users' Global-agent conversations within the viewer's scope and sharing, never the viewer's own or a Private agent's, and keeps to the row cap.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  private static AIAgent__c createAgent(String visibility) {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    agent.ConversationVisibility__c = visibility;
    insert agent;

    return agent;
  }

  // Five chat users. Parent role above child role, child above grandchild, and an unrelated role; users are given the roles in the order of the list, and the last has none. The first is the viewer.
  private static List<User> createUsersInRoles() {
    List<User> users = AIAssistTestDataFactory.createUsers(5, true);
    System.runAs(new User(Id = UserInfo.getUserId())) {
      UserRole parentRole = new UserRole(Name = 'AI Assist Test Parent');
      insert parentRole;
      UserRole childRole = new UserRole(
        Name = 'AI Assist Test Child',
        ParentRoleId = parentRole.Id
      );
      insert childRole;
      UserRole grandchildRole = new UserRole(
        Name = 'AI Assist Test Grandchild',
        ParentRoleId = childRole.Id
      );
      insert grandchildRole;
      UserRole peerRole = new UserRole(Name = 'AI Assist Test Peer');
      insert peerRole;

      users[0].UserRoleId = parentRole.Id;
      users[1].UserRoleId = childRole.Id;
      users[2].UserRoleId = grandchildRole.Id;
      users[3].UserRoleId = peerRole.Id;
      update users;
    }
    AIAssistTestDataFactory.assignPermissionSet(
      users,
      AIAssistApplicationConstants.PERMISSION_SET_USER
    );

    return users;
  }

  private static void setScope(Id userId, String scope) {
    AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(
      userId,
      false
    )[0];
    userSettings.ConversationVisibilityScope__c = scope;
    insert userSettings;
  }

  // One conversation per owner, in the order given.
  private static List<AIConversation__c> createConversations(
    Id agentId,
    List<User> owners
  ) {
    List<AIConversation__c> conversations = new List<AIConversation__c>();
    for (User owner : owners)
      conversations.addAll(
        AIAssistTestDataFactory.createAIConversations(
          agentId,
          owner.Id,
          1,
          false
        )
      );
    insert conversations;

    return conversations;
  }

  // Whether the running user may read each conversation, in the order given.
  private static List<Boolean> canView(List<AIConversation__c> conversations) {
    List<Boolean> answers = new List<Boolean>();
    for (AIConversation__c conversation : conversations) {
      try {
        AIConversationVisibilityService.assertCanView(conversation.Id);
        answers.add(true);
      } catch (AIConversationVisibilityService.AIConversationVisibilityServiceException refusal) {
        Assert.areEqual(
          Label.AI_Error_Conversation_Not_Found,
          refusal.getMessage(),
          'The same answer as for a missing conversation.'
        );
        answers.add(false);
      }
    }

    return answers;
  }

  @IsTest
  static void testScenario1() {
    Test.startTest();
    String blank = AIConversationVisibilityService.getEffectiveScope(
      new AIUserSettings__c()
    );
    String missing = AIConversationVisibilityService.getEffectiveScope(null);
    String unknown = AIConversationVisibilityService.getEffectiveScope(
      new AIUserSettings__c(ConversationVisibilityScope__c = 'Everything')
    );
    String subordinates = AIConversationVisibilityService.getEffectiveScope(
      new AIUserSettings__c(
        ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES
      )
    );
    String all = AIConversationVisibilityService.getEffectiveScope(
      new AIUserSettings__c(
        ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL
      )
    );
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN,
      blank,
      'Blank is the narrowest.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN,
      missing,
      'No settings is the narrowest.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN,
      unknown,
      'An unrecognised value fails closed.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES,
      subordinates,
      'Kept.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL,
      all,
      'Kept.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c privateAgent = createAgent('Private');
    List<User> users = AIAssistTestDataFactory.createUsers(2, true);
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ users[0] },
      AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER
    );
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ users[1] },
      AIAssistApplicationConstants.PERMISSION_SET_USER
    );
    setScope(users[0].Id, AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL);
    List<AIConversation__c> conversations = createConversations(
      privateAgent.Id,
      new List<User>{ users[1] }
    );
    List<Boolean> starter;
    List<Boolean> viewAllViewer;

    Test.startTest();
    System.runAs(users[1]) {
      starter = canView(conversations);
    }
    System.runAs(users[0]) {
      viewAllViewer = canView(conversations);
    }
    Test.stopTest();

    Assert.isTrue(starter[0], 'The starter always reads their own.');
    Assert.isFalse(
      viewAllViewer[0],
      'A Private agent shows its conversations to the starter only.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c globalAgent = createAgent('Global');
    List<User> users = AIAssistTestDataFactory.createUsers(3, true);
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ users[0] },
      AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER
    );
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ users[1], users[2] },
      AIAssistApplicationConstants.PERMISSION_SET_USER
    );
    setScope(users[0].Id, AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL);
    setScope(users[1].Id, AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL);
    List<AIConversation__c> conversations = createConversations(
      globalAgent.Id,
      new List<User>{ users[2] }
    );
    List<Boolean> withViewAll;
    List<Boolean> withoutViewAll;
    Boolean isAllowedWithViewAll;
    Boolean isAllowedWithout;

    Test.startTest();
    System.runAs(users[0]) {
      isAllowedWithViewAll = AIConversationVisibilityService.isAllScopeAllowed();
      withViewAll = canView(conversations);
    }
    System.runAs(users[1]) {
      isAllowedWithout = AIConversationVisibilityService.isAllScopeAllowed();
      withoutViewAll = canView(conversations);
    }
    Test.stopTest();

    Assert.isTrue(isAllowedWithViewAll, 'View All honours the scope.');
    Assert.isTrue(withViewAll[0], 'All Conversations reaches everybody.');
    Assert.isFalse(
      isAllowedWithout,
      'Neither View All nor the custom permission.'
    );
    Assert.isFalse(
      withoutViewAll[0],
      'The scope alone never widens what sharing allows.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c globalAgent = createAgent('Global');
    List<User> users = createUsersInRoles();
    setScope(users[0].Id, AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL);
    List<AIConversation__c> conversations = createConversations(
      globalAgent.Id,
      new List<User>{ users[1], users[3] }
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      PermissionSet grantingSet = new PermissionSet(
        Name = 'AIAssistTestViewShared',
        Label = 'AI Assist Test View Shared'
      );
      insert grantingSet;
      insert new SetupEntityAccess(
        ParentId = grantingSet.Id,
        SetupEntityId = [
          SELECT Id
          FROM CustomPermission
          WHERE
            DeveloperName = :AIAssistApplicationConstants.PERMISSION_VIEW_SHARED_CONVERSATIONS
          LIMIT 1
        ]
        .Id
      );
      insert new PermissionSetAssignment(
        AssigneeId = users[0].Id,
        PermissionSetId = grantingSet.Id
      );
    }
    Boolean isAllowed;
    List<Boolean> answers;

    Test.startTest();
    System.runAs(users[0]) {
      isAllowed = AIConversationVisibilityService.isAllScopeAllowed();
      answers = canView(conversations);
    }
    Test.stopTest();

    Assert.isTrue(isAllowed, 'The custom permission honours the scope.');
    Assert.isTrue(answers[0], 'Sharing gives a manager a subordinate\'s.');
    Assert.isFalse(
      answers[1],
      'Sharing does not give a peer\'s, and the permission does not widen it.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIAgent__c globalAgent = createAgent('Global');
    List<User> users = createUsersInRoles();
    setScope(
      users[0].Id,
      AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES
    );
    setScope(
      users[2].Id,
      AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES
    );
    List<AIConversation__c> conversations = createConversations(
      globalAgent.Id,
      new List<User>{ users[1], users[2], users[3], users[4] }
    );
    Set<Id> roleIds;
    Set<Id> noRoleIds;
    List<Boolean> manager;
    List<Boolean> subordinate;

    Test.startTest();
    System.runAs(users[0]) {
      roleIds = AIConversationVisibilityService.getSubordinateRoleIds();
      manager = canView(conversations);
    }
    System.runAs(users[4]) {
      noRoleIds = AIConversationVisibilityService.getSubordinateRoleIds();
    }
    System.runAs(users[2]) {
      subordinate = canView(conversations);
    }
    Test.stopTest();

    Assert.areEqual(
      2,
      roleIds.size(),
      'The child and grandchild roles, not the peer.'
    );
    Assert.isTrue(noRoleIds.isEmpty(), 'No role, no subordinates.');
    Assert.isTrue(manager[0], 'A direct report.');
    Assert.isTrue(manager[1], 'A report two levels down.');
    Assert.isFalse(manager[2], 'A peer is not a subordinate.');
    Assert.isFalse(manager[3], 'A user without a role is not.');
    Assert.isFalse(
      subordinate[0],
      'Visibility follows the hierarchy downward only: a subordinate cannot read a manager.'
    );
  }

  @IsTest
  static void testScenario6() {
    AIAgent__c globalAgent = createAgent('Global');
    List<User> users = createUsersInRoles();
    setScope(users[0].Id, AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN);
    List<AIConversation__c> conversations = createConversations(
      globalAgent.Id,
      new List<User>{ users[1] }
    );
    List<Boolean> ownScope;
    List<Boolean> noSettings;
    List<String> messages = new List<String>();

    Test.startTest();
    System.runAs(users[0]) {
      ownScope = canView(conversations);
      for (Id badId : new List<Id>{ null, UserInfo.getUserId() }) {
        try {
          AIConversationVisibilityService.assertCanView(badId);
        } catch (AIConversationVisibilityService.AIConversationVisibilityServiceException refusal) {
          messages.add(refusal.getMessage());
        }
      }
    }
    delete [SELECT Id FROM AIUserSettings__c WHERE User__c = :users[0].Id];
    System.runAs(users[0]) {
      noSettings = canView(conversations);
    }
    Test.stopTest();

    Assert.isFalse(ownScope[0], 'My Conversations Only reaches nobody else.');
    Assert.isFalse(noSettings[0], 'No settings is the narrowest scope.');
    Assert.areEqual(
      new List<String>{
        Label.AI_Error_Conversation_Not_Found,
        Label.AI_Error_Conversation_Not_Found
      },
      messages,
      'No Id and a wrong-type Id are refused the same way.'
    );
  }

  @IsTest
  static void testScenario7() {
    AIAgent__c globalAgent = createAgent('Global');
    List<User> users = createUsersInRoles();
    setScope(
      users[0].Id,
      AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES
    );
    AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(
      globalAgent.Id,
      users[1].Id,
      1,
      false
    )[0];
    theirs.RelatedRecordId__c = 'not-a-record-id';
    insert theirs;
    List<Boolean> answers;

    Test.startTest();
    System.runAs(users[0]) {
      answers = canView(new List<AIConversation__c>{ theirs });
    }
    Test.stopTest();

    Assert.isFalse(answers[0], 'A value that cannot be checked is not shown.');
  }

  @IsTest
  static void testScenario8() {
    AIAgent__c globalAgent = createAgent('Global');
    AIAgent__c privateAgent = createAgent('Private');
    List<User> users = createUsersInRoles();
    User superUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ superUser },
      AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER
    );
    // The viewer's own, a child's, a grandchild's and a peer's on the Global agent.
    List<AIConversation__c> onGlobal = createConversations(
      globalAgent.Id,
      new List<User>{ users[0], users[1], users[2], users[3] }
    );
    createConversations(privateAgent.Id, new List<User>{ users[1] });
    Map<String, Object> binds = new Map<String, Object>();
    List<AIConversation__c> underOwn;
    List<AIConversation__c> underSubordinates;
    List<AIConversation__c> underAllWithoutViewAll;
    List<AIConversation__c> noRole;
    List<AIConversation__c> underAllWithViewAll;
    List<AIConversation__c> capped;

    Test.startTest();
    System.runAs(users[0]) {
      underOwn = AIConversationVisibilityService.getSharedConversations(
        AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN,
        'Id',
        binds,
        10
      );
      underSubordinates = AIConversationVisibilityService.getSharedConversations(
        AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES,
        'Id',
        binds,
        10
      );
      underAllWithoutViewAll = AIConversationVisibilityService.getSharedConversations(
        AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL,
        'Id',
        binds,
        10
      );
    }
    System.runAs(users[4]) {
      noRole = AIConversationVisibilityService.getSharedConversations(
        AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES,
        'Id',
        binds,
        10
      );
    }
    System.runAs(superUser) {
      underAllWithViewAll = AIConversationVisibilityService.getSharedConversations(
        AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL,
        'Id',
        binds,
        10
      );
      capped = AIConversationVisibilityService.getSharedConversations(
        AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL,
        'Id',
        binds,
        1
      );
    }
    Test.stopTest();

    Assert.isTrue(underOwn.isEmpty(), 'The default scope lists nothing.');
    Assert.areEqual(
      new Set<Id>{ onGlobal[1].Id, onGlobal[2].Id },
      new Map<Id, AIConversation__c>(underSubordinates).keySet(),
      'Only subordinates on a Global agent; never the viewer\'s own or a Private agent\'s.'
    );
    Assert.isTrue(
      underAllWithoutViewAll.isEmpty(),
      'All Conversations lists nothing without View All or the permission.'
    );
    Assert.isTrue(
      noRole.isEmpty(),
      'A viewer with no role has no subordinates.'
    );
    Assert.areEqual(
      new Map<Id, AIConversation__c>(onGlobal).keySet(),
      new Map<Id, AIConversation__c>(underAllWithViewAll).keySet(),
      'Everybody on a Global agent, and nothing from a Private one.'
    );
    Assert.areEqual(1, capped.size(), 'The row cap holds.');
  }
}
