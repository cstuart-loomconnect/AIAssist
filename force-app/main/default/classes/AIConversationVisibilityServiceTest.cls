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
*/

@IsTest
private class AIConversationVisibilityServiceTest {
  // testScenario1: A blank, missing or unrecognised scope is the narrowest one; the two wider scopes are kept.
  // testScenario2: The starter always reads their conversation; a Private agent shows it to nobody else, whatever the viewer's scope.
  // testScenario3: With a Global agent, My Conversations Only reaches nobody and All Conversations reaches everybody.
  // testScenario4: My Subordinates Conversations reaches users in a role below the viewer's, at any depth, and not a peer, a manager or a user without a role.
  // testScenario5: A conversation about a value that is not a record Id is not shown to another user.
  // testScenario6: assertCanView answers "not found" for a conversation the viewer may not read, and returns one they may.
  // testScenario7: getSharedConversations lists only other users' Global-agent conversations within the viewer's scope.

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

  // Parent role above child role, child above grandchild, and an unrelated role; users are given the roles in the order of the list.
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

      users[0].UserRoleId = parentRole.Id; // The viewer.
      users[1].UserRoleId = childRole.Id;
      users[2].UserRoleId = grandchildRole.Id;
      users[3].UserRoleId = peerRole.Id;
      // users[4] has no role.
      update users;
    }

    return users;
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
    User other = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIConversation__c mine = AIAssistTestDataFactory.createAIConversations(
      privateAgent.Id,
      UserInfo.getUserId(),
      1,
      true
    )[0];
    AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(
      privateAgent.Id,
      other.Id,
      1,
      true
    )[0];
    mine = [
      SELECT OwnerId, RelatedRecordId__c, AIAgent__r.ConversationVisibility__c
      FROM AIConversation__c
      WHERE Id = :mine.Id
    ];
    theirs = [
      SELECT OwnerId, RelatedRecordId__c, AIAgent__r.ConversationVisibility__c
      FROM AIConversation__c
      WHERE Id = :theirs.Id
    ];

    Test.startTest();
    Boolean ownersOwn = AIConversationVisibilityService.canView(
      mine,
      UserInfo.getUserId(),
      AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN
    );
    Boolean privateToAll = AIConversationVisibilityService.canView(
      theirs,
      UserInfo.getUserId(),
      AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL
    );
    Boolean noViewer = AIConversationVisibilityService.canView(
      theirs,
      null,
      AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL
    );
    Boolean noConversation = AIConversationVisibilityService.canView(
      null,
      UserInfo.getUserId(),
      AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL
    );
    Test.stopTest();

    Assert.isTrue(ownersOwn, 'The starter always reads their own.');
    Assert.isFalse(
      privateToAll,
      'A Private agent shows its conversations to the starter only.'
    );
    Assert.isFalse(noViewer, 'No viewer, no access.');
    Assert.isFalse(noConversation, 'No conversation, no access.');
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c globalAgent = createAgent('Global');
    User other = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(
      globalAgent.Id,
      other.Id,
      1,
      true
    )[0];
    theirs = [
      SELECT OwnerId, RelatedRecordId__c, AIAgent__r.ConversationVisibility__c
      FROM AIConversation__c
      WHERE Id = :theirs.Id
    ];

    Test.startTest();
    Boolean ownScope = AIConversationVisibilityService.canView(
      theirs,
      UserInfo.getUserId(),
      AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN
    );
    Boolean allScope = AIConversationVisibilityService.canView(
      theirs,
      UserInfo.getUserId(),
      AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL
    );
    Boolean unknownScope = AIConversationVisibilityService.canView(
      theirs,
      UserInfo.getUserId(),
      'Everything'
    );
    Test.stopTest();

    Assert.isFalse(ownScope, 'My Conversations Only reaches nobody else.');
    Assert.isTrue(allScope, 'All Conversations reaches everybody.');
    Assert.isFalse(unknownScope, 'An unrecognised scope fails closed.');
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c globalAgent = createAgent('Global');
    List<User> users = createUsersInRoles();
    List<AIConversation__c> conversations = new List<AIConversation__c>();
    for (Integer index = 1; index < users.size(); index++)
      conversations.addAll(
        AIAssistTestDataFactory.createAIConversations(
          globalAgent.Id,
          users[index].Id,
          1,
          false
        )
      );
    insert conversations;
    Map<Id, AIConversation__c> byOwner = new Map<Id, AIConversation__c>();
    for (AIConversation__c conversation : [
      SELECT OwnerId, RelatedRecordId__c, AIAgent__r.ConversationVisibility__c
      FROM AIConversation__c
      WHERE Id IN :conversations
    ])
      byOwner.put(conversation.OwnerId, conversation);

    Test.startTest();
    Set<Id> roleIds = AIConversationVisibilityService.getSubordinateRoleIds(
      users[0].Id
    );
    Set<Id> noRoleIds = AIConversationVisibilityService.getSubordinateRoleIds(
      users[4].Id
    );
    Set<Id> noUserIds = AIConversationVisibilityService.getSubordinateRoleIds(
      null
    );
    Map<String, Boolean> canView = new Map<String, Boolean>();
    for (Integer index = 1; index < users.size(); index++)
      canView.put(
        'user' + index,
        AIConversationVisibilityService.canView(
          byOwner.get(users[index].Id),
          users[0].Id,
          AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES
        )
      );
    Boolean managerSeesSubordinate = AIConversationVisibilityService.canView(
      byOwner.get(users[1].Id),
      users[2].Id,
      AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      roleIds.size(),
      'The child and grandchild roles, not the peer.'
    );
    Assert.isTrue(noRoleIds.isEmpty(), 'No role, no subordinates.');
    Assert.isTrue(noUserIds.isEmpty(), 'No user, no subordinates.');
    Assert.isTrue(canView.get('user1'), 'A direct report.');
    Assert.isTrue(canView.get('user2'), 'A report two levels down.');
    Assert.isFalse(canView.get('user3'), 'A peer is not a subordinate.');
    Assert.isFalse(canView.get('user4'), 'A user without a role is not.');
    Assert.isFalse(
      managerSeesSubordinate,
      'Visibility follows the hierarchy downward only: a subordinate cannot read a manager.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIAgent__c globalAgent = createAgent('Global');
    User other = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(
      globalAgent.Id,
      other.Id,
      1,
      false
    )[0];
    theirs.RelatedRecordId__c = 'not-a-record-id';
    insert theirs;
    theirs = [
      SELECT OwnerId, RelatedRecordId__c, AIAgent__r.ConversationVisibility__c
      FROM AIConversation__c
      WHERE Id = :theirs.Id
    ];

    Test.startTest();
    Boolean canView = AIConversationVisibilityService.canView(
      theirs,
      UserInfo.getUserId(),
      AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL
    );
    Test.stopTest();

    Assert.isFalse(canView, 'A value that cannot be checked is not shown.');
  }

  @IsTest
  static void testScenario6() {
    AIAgent__c globalAgent = createAgent('Global');
    User viewer = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ viewer },
      'AIAssistUser'
    );
    User starter = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(
      globalAgent.Id,
      starter.Id,
      1,
      true
    )[0];
    AIUserSettings__c viewerSettings = AIAssistTestDataFactory.createAIUserSettings(
      viewer.Id,
      false
    )[0];
    viewerSettings.ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL;
    insert viewerSettings;
    List<String> codes = new List<String>();
    AIConversation__c allowed;

    Test.startTest();
    System.runAs(viewer) {
      allowed = AIConversationVisibilityService.assertCanView(theirs.Id);
      for (Id badId : new List<Id>{ null, UserInfo.getUserId() }) {
        try {
          AIConversationVisibilityService.assertCanView(badId);
        } catch (AIMessagingException refusal) {
          codes.add(refusal.code);
        }
      }
    }
    delete viewerSettings;
    System.runAs(viewer) {
      try {
        AIConversationVisibilityService.assertCanView(theirs.Id);
      } catch (AIMessagingException refusal) {
        codes.add(refusal.code);
      }
    }
    Test.stopTest();

    Assert.areEqual(theirs.Id, allowed.Id, 'Readable under All Conversations.');
    Assert.areEqual(
      3,
      codes.size(),
      'No Id, a wrong-type Id and a viewer without the scope are all refused.'
    );
    for (String code : codes)
      Assert.areEqual(
        AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
        code,
        'The same answer as for a missing conversation.'
      );
  }

  @IsTest
  static void testScenario7() {
    AIAgent__c globalAgent = createAgent('Global');
    AIAgent__c privateAgent = createAgent('Private');
    List<User> users = createUsersInRoles();
    AIConversation__c mine = AIAssistTestDataFactory.createAIConversations(
      globalAgent.Id,
      users[0].Id,
      1,
      true
    )[0];
    AIConversation__c child = AIAssistTestDataFactory.createAIConversations(
      globalAgent.Id,
      users[1].Id,
      1,
      true
    )[0];
    AIConversation__c peer = AIAssistTestDataFactory.createAIConversations(
      globalAgent.Id,
      users[3].Id,
      1,
      true
    )[0];
    AIConversation__c hidden = AIAssistTestDataFactory.createAIConversations(
      privateAgent.Id,
      users[1].Id,
      1,
      true
    )[0];
    Map<String, Object> binds = new Map<String, Object>();

    Test.startTest();
    List<AIConversation__c> underOwn = AIConversationVisibilityService.getSharedConversations(
      users[0].Id,
      AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN,
      'Id',
      binds,
      10
    );
    List<AIConversation__c> underSubordinates = AIConversationVisibilityService.getSharedConversations(
      users[0].Id,
      AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES,
      'Id',
      binds,
      10
    );
    List<AIConversation__c> underAll = AIConversationVisibilityService.getSharedConversations(
      users[0].Id,
      AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL,
      'Id',
      binds,
      10
    );
    List<AIConversation__c> noRole = AIConversationVisibilityService.getSharedConversations(
      users[4].Id,
      AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES,
      'Id',
      binds,
      10
    );
    List<AIConversation__c> capped = AIConversationVisibilityService.getSharedConversations(
      users[0].Id,
      AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL,
      'Id',
      binds,
      1
    );
    Test.stopTest();

    Assert.isTrue(underOwn.isEmpty(), 'The default scope lists nothing.');
    Assert.areEqual(
      new Set<Id>{ child.Id },
      new Map<Id, AIConversation__c>(underSubordinates).keySet(),
      'Only the subordinate on a Global agent.'
    );
    Assert.areEqual(
      new Set<Id>{ child.Id, peer.Id },
      new Map<Id, AIConversation__c>(underAll).keySet(),
      'Everybody else on a Global agent; never the viewer\'s own or a Private agent\'s.'
    );
    Assert.isTrue(
      noRole.isEmpty(),
      'A viewer with no role has no subordinates.'
    );
    Assert.areEqual(1, capped.size(), 'The row cap holds.');
    Assert.isNotNull(mine.Id);
    Assert.isNotNull(hidden.Id);
  }
}
