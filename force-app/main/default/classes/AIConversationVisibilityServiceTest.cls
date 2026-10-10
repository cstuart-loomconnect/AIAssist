/*
Class Name: AIConversationVisibilityServiceTest

=================================================================
=================================================================

Description: Testing utility for AIConversationVisibilityService: who may read a conversation they did not start.

=================================================================
=================================================================
Applicable Classes:

AIConversationVisibilityService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIConversationVisibilityServiceTest {
  // testScenario1: Get the scope for a blank, missing, unrecognised, subordinates and all setting -> the first three are the narrowest scope and the two wider scopes are kept.
  // testScenario2: Read a Private agent's conversation as the starter and as a viewer with View All and the All Conversations scope -> the starter reads it and the other viewer does not.
  // testScenario3: Read another user's Global-agent conversation under All Conversations with and without View All -> it is readable with View All and not without it.
  // testScenario4: Read conversations under All Conversations with the custom permission and no View All -> a subordinate's is readable and a peer's is not.
  // testScenario5: Read conversations under My Subordinates Conversations -> a child and a grandchild are readable, a peer and a user without a role are not, and a subordinate cannot read a manager.
  // testScenario6: Read under My Conversations Only, with no settings, and with a null or wrong-type Id -> all are "not found".
  // testScenario7: Read a conversation about a value that is not a record Id as another user -> it is not shown.
  // testScenario8: List shared conversations for each scope and for a row cap -> only other users' Global-agent conversations within the viewer's scope and sharing are listed, within the cap.

  private static final String AGENT_VISIBILITY_PRIVATE = 'Private';
  private static final String AGENT_VISIBILITY_GLOBAL = 'Global';

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
    // [1] Declare the scopes to read back
    String blank;
    String missing;
    String unknown;
    String subordinates;
    String all;

    // [2] Get the effective scope for each kind of setting
    Test.startTest();
    blank = AIConversationVisibilityService.getEffectiveScope(
      new AIUserSettings__c()
    );
    missing = AIConversationVisibilityService.getEffectiveScope(null);
    unknown = AIConversationVisibilityService.getEffectiveScope(
      new AIUserSettings__c(ConversationVisibilityScope__c = 'Everything')
    );
    subordinates = AIConversationVisibilityService.getEffectiveScope(
      new AIUserSettings__c(
        ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES
      )
    );
    all = AIConversationVisibilityService.getEffectiveScope(
      new AIUserSettings__c(
        ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL
      )
    );
    Test.stopTest();

    // [3] Check the first three are the narrowest scope and the two wider scopes are kept
    Assert.areEqual(
      AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN,
      blank,
      'A blank scope should be the narrowest.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN,
      missing,
      'No settings should be the narrowest scope.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN,
      unknown,
      'An unrecognised scope should fail closed.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES,
      subordinates,
      'The subordinates scope should be kept.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL,
      all,
      'The all scope should be kept.'
    );
  }

  @IsTest
  static void testScenario2() {
    // [1] Create a Private agent, two users and a conversation started by the second user
    AIAgent__c privateAgent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    privateAgent.ConversationVisibility__c = AGENT_VISIBILITY_PRIVATE;
    insert privateAgent;

    List<User> users = AIAssistTestDataFactory.createUsers(2, true);
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ users[0] },
      AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER
    );
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ users[1] },
      AIAssistApplicationConstants.PERMISSION_SET_USER
    );

    AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(
      users[0].Id,
      false
    )[0];
    userSettings.ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL;
    insert userSettings;

    List<AIConversation__c> conversations = new List<AIConversation__c>();
    conversations.addAll(
      AIAssistTestDataFactory.createAIConversations(
        privateAgent.Id,
        users[1].Id,
        1,
        false
      )
    );
    insert conversations;

    List<Boolean> starter = new List<Boolean>();
    List<Boolean> viewAllViewer = new List<Boolean>();

    // [2] Try to read the conversation as the starter and as the View All viewer
    Test.startTest();
    System.runAs(users[1]) {
      for (AIConversation__c conversation : conversations) {
        try {
          AIConversationVisibilityService.getViewableConversation(
            conversation.Id
          );
          starter.add(true);
        } catch (AIConversationVisibilityService.AIConversationVisibilityServiceException ex) {
          Assert.areEqual(
            Label.AI_Error_Conversation_Not_Found,
            ex.getMessage(),
            'A refusal should give the same answer as for a missing conversation.'
          );
          starter.add(false);
        }
      }
    }
    System.runAs(users[0]) {
      for (AIConversation__c conversation : conversations) {
        try {
          AIConversationVisibilityService.getViewableConversation(
            conversation.Id
          );
          viewAllViewer.add(true);
        } catch (AIConversationVisibilityService.AIConversationVisibilityServiceException ex) {
          Assert.areEqual(
            Label.AI_Error_Conversation_Not_Found,
            ex.getMessage(),
            'A refusal should give the same answer as for a missing conversation.'
          );
          viewAllViewer.add(false);
        }
      }
    }
    Test.stopTest();

    // [3] Check only the starter can read it
    Assert.isTrue(
      starter[0],
      'The starter should always read their own conversation.'
    );
    Assert.isFalse(
      viewAllViewer[0],
      'A Private agent should show its conversations to the starter only.'
    );
  }

  @IsTest
  static void testScenario3() {
    // [1] Create a Global agent, three users and a conversation started by the third user
    AIAgent__c globalAgent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    globalAgent.ConversationVisibility__c = AGENT_VISIBILITY_GLOBAL;
    insert globalAgent;

    List<User> users = AIAssistTestDataFactory.createUsers(3, true);
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ users[0] },
      AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER
    );
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ users[1], users[2] },
      AIAssistApplicationConstants.PERMISSION_SET_USER
    );

    AIUserSettings__c firstSettings = AIAssistTestDataFactory.createAIUserSettings(
      users[0].Id,
      false
    )[0];
    firstSettings.ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL;
    insert firstSettings;

    AIUserSettings__c secondSettings = AIAssistTestDataFactory.createAIUserSettings(
      users[1].Id,
      false
    )[0];
    secondSettings.ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL;
    insert secondSettings;

    List<AIConversation__c> conversations = new List<AIConversation__c>();
    conversations.addAll(
      AIAssistTestDataFactory.createAIConversations(
        globalAgent.Id,
        users[2].Id,
        1,
        false
      )
    );
    insert conversations;

    List<Boolean> withViewAll = new List<Boolean>();
    List<Boolean> withoutViewAll = new List<Boolean>();
    Boolean isAllowedWithViewAll;
    Boolean isAllowedWithout;

    // [2] Check the All scope and read the conversation as a user with View All and one without
    Test.startTest();
    System.runAs(users[0]) {
      isAllowedWithViewAll = AIConversationVisibilityService.isAllScopeAllowed();
      for (AIConversation__c conversation : conversations) {
        try {
          AIConversationVisibilityService.getViewableConversation(
            conversation.Id
          );
          withViewAll.add(true);
        } catch (AIConversationVisibilityService.AIConversationVisibilityServiceException ex) {
          Assert.areEqual(
            Label.AI_Error_Conversation_Not_Found,
            ex.getMessage(),
            'A refusal should give the same answer as for a missing conversation.'
          );
          withViewAll.add(false);
        }
      }
    }
    System.runAs(users[1]) {
      isAllowedWithout = AIConversationVisibilityService.isAllScopeAllowed();
      for (AIConversation__c conversation : conversations) {
        try {
          AIConversationVisibilityService.getViewableConversation(
            conversation.Id
          );
          withoutViewAll.add(true);
        } catch (AIConversationVisibilityService.AIConversationVisibilityServiceException ex) {
          Assert.areEqual(
            Label.AI_Error_Conversation_Not_Found,
            ex.getMessage(),
            'A refusal should give the same answer as for a missing conversation.'
          );
          withoutViewAll.add(false);
        }
      }
    }
    Test.stopTest();

    // [3] Check View All reaches it and the scope alone does not
    Assert.isTrue(isAllowedWithViewAll, 'View All should honour the scope.');
    Assert.isTrue(
      withViewAll[0],
      'All Conversations should reach everybody with View All.'
    );
    Assert.isFalse(
      isAllowedWithout,
      'Neither View All nor the custom permission should not honour the scope.'
    );
    Assert.isFalse(
      withoutViewAll[0],
      'The scope alone should never widen what sharing allows.'
    );
  }

  @IsTest
  static void testScenario4() {
    // [1] Create a Global agent and five users in a role hierarchy, the first with the All scope
    AIAgent__c globalAgent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    globalAgent.ConversationVisibility__c = AGENT_VISIBILITY_GLOBAL;
    insert globalAgent;

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

    AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(
      users[0].Id,
      false
    )[0];
    userSettings.ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL;
    insert userSettings;

    // [2] Create a conversation for a subordinate and one for a peer
    List<AIConversation__c> conversations = new List<AIConversation__c>();
    conversations.addAll(
      AIAssistTestDataFactory.createAIConversations(
        globalAgent.Id,
        users[1].Id,
        1,
        false
      )
    );
    conversations.addAll(
      AIAssistTestDataFactory.createAIConversations(
        globalAgent.Id,
        users[3].Id,
        1,
        false
      )
    );
    insert conversations;

    // [3] Give the first user the View Shared Conversations custom permission
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
    List<Boolean> answers = new List<Boolean>();

    // [4] Check the All scope and read both conversations as the first user
    Test.startTest();
    System.runAs(users[0]) {
      isAllowed = AIConversationVisibilityService.isAllScopeAllowed();
      for (AIConversation__c conversation : conversations) {
        try {
          AIConversationVisibilityService.getViewableConversation(
            conversation.Id
          );
          answers.add(true);
        } catch (AIConversationVisibilityService.AIConversationVisibilityServiceException ex) {
          Assert.areEqual(
            Label.AI_Error_Conversation_Not_Found,
            ex.getMessage(),
            'A refusal should give the same answer as for a missing conversation.'
          );
          answers.add(false);
        }
      }
    }
    Test.stopTest();

    // [5] Check the subordinate's conversation is readable and the peer's is not
    Assert.isTrue(isAllowed, 'The custom permission should honour the scope.');
    Assert.isTrue(
      answers[0],
      'Sharing should give a manager a subordinate\'s conversation.'
    );
    Assert.isFalse(
      answers[1],
      'Sharing should not give a peer\'s conversation, and the permission should not widen it.'
    );
  }

  @IsTest
  static void testScenario5() {
    // [1] Create a Global agent and five users in a role hierarchy, the first and third with the Subordinates scope
    AIAgent__c globalAgent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    globalAgent.ConversationVisibility__c = AGENT_VISIBILITY_GLOBAL;
    insert globalAgent;

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

    AIUserSettings__c managerSettings = AIAssistTestDataFactory.createAIUserSettings(
      users[0].Id,
      false
    )[0];
    managerSettings.ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES;
    insert managerSettings;

    AIUserSettings__c grandchildSettings = AIAssistTestDataFactory.createAIUserSettings(
      users[2].Id,
      false
    )[0];
    grandchildSettings.ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES;
    insert grandchildSettings;

    // [2] Create a conversation for a child, a grandchild, a peer and a user without a role
    List<AIConversation__c> conversations = new List<AIConversation__c>();
    conversations.addAll(
      AIAssistTestDataFactory.createAIConversations(
        globalAgent.Id,
        users[1].Id,
        1,
        false
      )
    );
    conversations.addAll(
      AIAssistTestDataFactory.createAIConversations(
        globalAgent.Id,
        users[2].Id,
        1,
        false
      )
    );
    conversations.addAll(
      AIAssistTestDataFactory.createAIConversations(
        globalAgent.Id,
        users[3].Id,
        1,
        false
      )
    );
    conversations.addAll(
      AIAssistTestDataFactory.createAIConversations(
        globalAgent.Id,
        users[4].Id,
        1,
        false
      )
    );
    insert conversations;

    Set<Id> roleIds;
    Set<Id> noRoleIds;
    List<Boolean> manager = new List<Boolean>();
    List<Boolean> subordinate = new List<Boolean>();

    // [3] Find the subordinate roles and read the conversations as the manager, the user with no role and the grandchild
    Test.startTest();
    System.runAs(users[0]) {
      roleIds = AIConversationVisibilityService.getSubordinateRoleIds();
      for (AIConversation__c conversation : conversations) {
        try {
          AIConversationVisibilityService.getViewableConversation(
            conversation.Id
          );
          manager.add(true);
        } catch (AIConversationVisibilityService.AIConversationVisibilityServiceException ex) {
          Assert.areEqual(
            Label.AI_Error_Conversation_Not_Found,
            ex.getMessage(),
            'A refusal should give the same answer as for a missing conversation.'
          );
          manager.add(false);
        }
      }
    }
    System.runAs(users[4]) {
      noRoleIds = AIConversationVisibilityService.getSubordinateRoleIds();
    }
    System.runAs(users[2]) {
      for (AIConversation__c conversation : conversations) {
        try {
          AIConversationVisibilityService.getViewableConversation(
            conversation.Id
          );
          subordinate.add(true);
        } catch (AIConversationVisibilityService.AIConversationVisibilityServiceException ex) {
          Assert.areEqual(
            Label.AI_Error_Conversation_Not_Found,
            ex.getMessage(),
            'A refusal should give the same answer as for a missing conversation.'
          );
          subordinate.add(false);
        }
      }
    }
    Test.stopTest();

    // [4] Check the hierarchy is followed downward only
    Assert.areEqual(
      2,
      roleIds.size(),
      'The child and grandchild roles should be found, not the peer.'
    );
    Assert.isTrue(
      noRoleIds.isEmpty(),
      'A user with no role should have no subordinates.'
    );

    Assert.isTrue(manager[0], 'A direct report should be readable.');
    Assert.isTrue(manager[1], 'A report two levels down should be readable.');
    Assert.isFalse(manager[2], 'A peer should not be a subordinate.');
    Assert.isFalse(
      manager[3],
      'A user without a role should not be a subordinate.'
    );
    Assert.isFalse(
      subordinate[0],
      'Visibility should follow the hierarchy downward only: a subordinate cannot read a manager.'
    );
  }

  @IsTest
  static void testScenario6() {
    // [1] Create a Global agent and five users in a role hierarchy, the first with the Own scope
    AIAgent__c globalAgent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    globalAgent.ConversationVisibility__c = AGENT_VISIBILITY_GLOBAL;
    insert globalAgent;

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

    AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(
      users[0].Id,
      false
    )[0];
    userSettings.ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN;
    insert userSettings;

    // [2] Create a conversation for a subordinate
    List<AIConversation__c> conversations = new List<AIConversation__c>();
    conversations.addAll(
      AIAssistTestDataFactory.createAIConversations(
        globalAgent.Id,
        users[1].Id,
        1,
        false
      )
    );
    insert conversations;

    List<Boolean> ownScope = new List<Boolean>();
    List<Boolean> noSettings = new List<Boolean>();
    List<String> messages = new List<String>();

    // [3] Read the conversation and two bad Ids with the Own scope, then read it again with no settings
    Test.startTest();
    System.runAs(users[0]) {
      for (AIConversation__c conversation : conversations) {
        try {
          AIConversationVisibilityService.getViewableConversation(
            conversation.Id
          );
          ownScope.add(true);
        } catch (AIConversationVisibilityService.AIConversationVisibilityServiceException ex) {
          Assert.areEqual(
            Label.AI_Error_Conversation_Not_Found,
            ex.getMessage(),
            'A refusal should give the same answer as for a missing conversation.'
          );
          ownScope.add(false);
        }
      }

      for (Id badId : new List<Id>{ null, UserInfo.getUserId() }) {
        try {
          AIConversationVisibilityService.getViewableConversation(badId);
        } catch (AIConversationVisibilityService.AIConversationVisibilityServiceException ex) {
          messages.add(ex.getMessage());
        }
      }
    }
    delete [SELECT Id FROM AIUserSettings__c WHERE User__c = :users[0].Id];
    System.runAs(users[0]) {
      for (AIConversation__c conversation : conversations) {
        try {
          AIConversationVisibilityService.getViewableConversation(
            conversation.Id
          );
          noSettings.add(true);
        } catch (AIConversationVisibilityService.AIConversationVisibilityServiceException ex) {
          Assert.areEqual(
            Label.AI_Error_Conversation_Not_Found,
            ex.getMessage(),
            'A refusal should give the same answer as for a missing conversation.'
          );
          noSettings.add(false);
        }
      }
    }
    Test.stopTest();

    // [4] Check all are refused as not found
    Assert.isFalse(
      ownScope[0],
      'My Conversations Only should reach nobody else.'
    );
    Assert.isFalse(noSettings[0], 'No settings should be the narrowest scope.');
    Assert.areEqual(
      new List<String>{
        Label.AI_Error_Conversation_Not_Found,
        Label.AI_Error_Conversation_Not_Found
      },
      messages,
      'No Id and a wrong-type Id should be refused the same way.'
    );
  }

  @IsTest
  static void testScenario7() {
    // [1] Create a Global agent and five users in a role hierarchy, the first with the Subordinates scope
    AIAgent__c globalAgent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    globalAgent.ConversationVisibility__c = AGENT_VISIBILITY_GLOBAL;
    insert globalAgent;

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

    AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(
      users[0].Id,
      false
    )[0];
    userSettings.ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES;
    insert userSettings;

    // [2] Create a subordinate's conversation about a value that is not a record Id
    AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(
      globalAgent.Id,
      users[1].Id,
      1,
      false
    )[0];
    theirs.RelatedRecordId__c = 'not-a-record-id';
    insert theirs;

    List<Boolean> answers = new List<Boolean>();

    // [3] Try to read the conversation as the first user
    Test.startTest();
    System.runAs(users[0]) {
      for (
        AIConversation__c conversation : new List<AIConversation__c>{ theirs }
      ) {
        try {
          AIConversationVisibilityService.getViewableConversation(
            conversation.Id
          );
          answers.add(true);
        } catch (AIConversationVisibilityService.AIConversationVisibilityServiceException ex) {
          Assert.areEqual(
            Label.AI_Error_Conversation_Not_Found,
            ex.getMessage(),
            'A refusal should give the same answer as for a missing conversation.'
          );
          answers.add(false);
        }
      }
    }
    Test.stopTest();

    // [4] Check it is not shown
    Assert.isFalse(
      answers[0],
      'A value that cannot be checked should not be shown.'
    );
  }

  @IsTest
  static void testScenario8() {
    // [1] Create a Global agent, a Private agent and five users in a role hierarchy, plus a user with View All
    AIAgent__c globalAgent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    globalAgent.ConversationVisibility__c = AGENT_VISIBILITY_GLOBAL;
    insert globalAgent;

    AIAgent__c privateAgent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    privateAgent.ConversationVisibility__c = AGENT_VISIBILITY_PRIVATE;
    insert privateAgent;

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

    User superUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ superUser },
      AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER
    );

    // [2] Create conversations on the Global agent for the viewer, a child, a grandchild and a peer, and one on the Private agent
    List<AIConversation__c> onGlobal = new List<AIConversation__c>();
    onGlobal.addAll(
      AIAssistTestDataFactory.createAIConversations(
        globalAgent.Id,
        users[0].Id,
        1,
        false
      )
    );
    onGlobal.addAll(
      AIAssistTestDataFactory.createAIConversations(
        globalAgent.Id,
        users[1].Id,
        1,
        false
      )
    );
    onGlobal.addAll(
      AIAssistTestDataFactory.createAIConversations(
        globalAgent.Id,
        users[2].Id,
        1,
        false
      )
    );
    onGlobal.addAll(
      AIAssistTestDataFactory.createAIConversations(
        globalAgent.Id,
        users[3].Id,
        1,
        false
      )
    );
    insert onGlobal;

    List<AIConversation__c> onPrivate = new List<AIConversation__c>();
    onPrivate.addAll(
      AIAssistTestDataFactory.createAIConversations(
        privateAgent.Id,
        users[1].Id,
        1,
        false
      )
    );
    insert onPrivate;

    Map<String, Object> binds = new Map<String, Object>();
    List<AIConversation__c> underOwn;
    List<AIConversation__c> underSubordinates;
    List<AIConversation__c> underAllWithoutViewAll;
    List<AIConversation__c> noRole;
    List<AIConversation__c> underAllWithViewAll;
    List<AIConversation__c> capped;

    // [3] List the shared conversations for each scope, viewer and row cap
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

    // [4] Check only other users' Global-agent conversations within scope and the cap are listed
    Assert.isTrue(underOwn.isEmpty(), 'The default scope should list nothing.');
    Assert.areEqual(
      new Set<Id>{ onGlobal[1].Id, onGlobal[2].Id },
      new Map<Id, AIConversation__c>(underSubordinates).keySet(),
      'Only subordinates on a Global agent should be listed, never the viewer\'s own or a Private agent\'s.'
    );
    Assert.isTrue(
      underAllWithoutViewAll.isEmpty(),
      'All Conversations should list nothing without View All or the permission.'
    );
    Assert.isTrue(
      noRole.isEmpty(),
      'A viewer with no role should have no subordinates.'
    );
    Assert.areEqual(
      new Map<Id, AIConversation__c>(onGlobal).keySet(),
      new Map<Id, AIConversation__c>(underAllWithViewAll).keySet(),
      'Everybody on a Global agent should be listed, and nothing from a Private one.'
    );
    Assert.areEqual(1, capped.size(), 'The row cap should hold.');
  }
}
