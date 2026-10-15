/*
Script Name: chat-feature-test-data.apex

=================================================================
=================================================================

Description: Creates one test Account for each chat window scenario (Jump to latest, Save to record, Share, Shared with me, Private agent), each with a ready-made conversation and messages, so the new features can be tested without the AI connector. Run chat-feature-test-users.apex first.

Step 1: Refuse to run outside a sandbox or scratch org, and find the agents, the Usage Policy and Dana Recipient
Step 2: Make sure Dana can open the chat window (Usage Policy assignment)
Step 3: Create a Global copy of the Account agent, because only a Global agent can be shared
Step 4: Create one Account and one conversation per scenario, with the messages written by hand
Step 5: Share the two conversations that need to be shared already
Step 6: Print the Account Ids

Run:  sf apex run --file scripts/apex/chat-feature-test-data.apex --target-org <alias>
Safe to run again: Accounts named "Chat Test n - ..." are skipped once they exist.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public class ChatFeatureTestLoader {

  AIAgent__c globalAgent;
  AIAgent__c privateAgent;
  User dana;
  Map<String, Id> idsByLabel = new Map<String, Id>();

  public void run() {

    // [1] Never run in production, and find what the scenarios need
    if (![SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox) {

      System.debug(LoggingLevel.ERROR, 'Not a sandbox or scratch org. Nothing was created.');
      return;
    }

    List<AIAgent__c> privateAgents = [SELECT Id, Name FROM AIAgent__c WHERE IsActive__c = TRUE AND ObjectApiNames__c = 'Account' AND ConversationVisibility__c != 'Global' AND AIModelConfiguration__c != NULL ORDER BY CreatedDate LIMIT 1];
    List<User> danas = [SELECT Id, Name FROM User WHERE Alias = 'drecip' AND IsActive = TRUE LIMIT 1];
    List<AIUsagePolicy__c> policies = [SELECT Id FROM AIUsagePolicy__c WHERE IsActive__c = TRUE LIMIT 1];

    if (privateAgents.isEmpty() || danas.isEmpty() || policies.isEmpty()) {

      System.debug(LoggingLevel.ERROR, 'Missing: an active Account agent (run conversation-demo-data.apex), Dana Recipient (run chat-feature-test-users.apex) or an active AI Usage Policy. Nothing was created.');
      return;
    }

    privateAgent = privateAgents[0];
    dana = danas[0];

    // [2] Dana needs a Usage Policy to open the window
    if ([SELECT COUNT() FROM AIUsagePolicyAssignment__c WHERE User__c = :dana.Id] == 0) insert new AIUsagePolicyAssignment__c(AssigneeType__c = 'User', User__c = dana.Id, AIUsagePolicy__c = policies[0].Id, IsActive__c = true);

    // [3] The Global agent
    globalAgent = findOrCreateGlobalAgent();

    // [4] One Account and conversation per scenario
    String owner = UserInfo.getUserId();

    createScenario('1 Jump to latest', globalAgent, owner, 'Chat Test 1 - Jump to latest', buildLongConversation());
    createScenario('2 Save to record', globalAgent, owner, 'Chat Test 2 - Save to record', buildSaveConversation());
    createScenario('3 Share (not shared yet)', globalAgent, owner, 'Chat Test 3 - Share', buildShortConversation());
    createScenario('4 Share (already shared with Dana)', globalAgent, owner, 'Chat Test 4 - Already shared with Dana', buildShortConversation());
    createScenario('5 Shared with me (owned by Dana)', globalAgent, dana.Id, 'Chat Test 5 - Shared with me', buildSharedConversation());
    createScenario('6 Private agent (no Share option)', privateAgent, owner, 'Chat Test 6 - Private agent', buildShortConversation());

    // [5] Share conversation 4 with Dana, and conversation 5 with the signed-in user
    List<AIConversation__Share> shares = new List<AIConversation__Share>();
    shares.add(new AIConversation__Share(ParentId = idsByLabel.get('4 Share (already shared with Dana)' + '|conversation'), UserOrGroupId = dana.Id, AccessLevel = 'Read', RowCause = Schema.AIConversation__Share.RowCause.DirectShare__c));
    shares.add(new AIConversation__Share(ParentId = idsByLabel.get('5 Shared with me (owned by Dana)' + '|conversation'), UserOrGroupId = owner, AccessLevel = 'Read', RowCause = Schema.AIConversation__Share.RowCause.DirectShare__c));
    insert shares;

    // [6] Print where to go
    for (String label : new List<String>{ '1 Jump to latest', '2 Save to record', '3 Share (not shared yet)', '4 Share (already shared with Dana)', '5 Shared with me (owned by Dana)', '6 Private agent (no Share option)' }) {

      System.debug(LoggingLevel.ERROR, label + ' -> Account ' + idsByLabel.get(label) + ', conversation ' + idsByLabel.get(label + '|conversation'));
    }

    System.debug(LoggingLevel.ERROR, 'Dana Recipient user: ' + dana.Id);
  }

  // The Global copy of the Account agent: the same settings, with Conversation Visibility set to Global.
  AIAgent__c findOrCreateGlobalAgent() {

    List<AIAgent__c> found = [SELECT Id, Name FROM AIAgent__c WHERE DeveloperName__c = 'Test_Global_Account_Assistant' LIMIT 1];

    if (!found.isEmpty()) return found[0];

    Map<String, Schema.SObjectField> fields = Schema.SObjectType.AIAgent__c.fields.getMap();
    List<String> creatable = new List<String>();

    for (String fieldName : fields.keySet()) {

      if (fields.get(fieldName).getDescribe().isCreateable()) creatable.add(fieldName);
    }

    AIAgent__c source = (AIAgent__c) Database.query('SELECT ' + String.join(creatable, ',') + ' FROM AIAgent__c WHERE Id = \'' + privateAgent.Id + '\'');
    AIAgent__c copy = source.clone(false, true, false, false);
    copy.Name = 'Test - Global Account Assistant';
    copy.DeveloperName__c = 'Test_Global_Account_Assistant';
    copy.ConversationVisibility__c = 'Global';
    copy.ExternalReference__c = null;
    insert copy;

    return copy;
  }

  // One Account, and an Active conversation about it with the messages in order.
  void createScenario(String label, AIAgent__c agent, Id conversationOwnerId, String accountName, List<String[]> messages) {

    List<Account> existing = [SELECT Id FROM Account WHERE Name = :accountName LIMIT 1];
    Account account = existing.isEmpty() ? new Account(Name = accountName, Phone = '020 7946 0100', Description = 'Made by chat-feature-test-data.apex for the scenario: ' + label) : existing[0];

    if (existing.isEmpty()) insert account;

    idsByLabel.put(label, account.Id);

    // The conversation and its messages are made once.
    List<AIConversation__c> conversations = [SELECT Id FROM AIConversation__c WHERE RelatedRecordId__c = :String.valueOf(account.Id) AND AIAgent__c = :agent.Id LIMIT 1];

    if (!conversations.isEmpty()) {

      idsByLabel.put(label + '|conversation', conversations[0].Id);
      return;
    }

    AIConversation__c conversation = new AIConversation__c(AIAgent__c = agent.Id, Channel__c = 'Record Page Chat', Status__c = 'Active', RelatedObjectAPIName__c = 'Account', RelatedRecordId__c = account.Id, OwnerId = conversationOwnerId);
    insert conversation;

    idsByLabel.put(label + '|conversation', conversation.Id);

    // One insert, in order, so the ids (and the order the window shows) follow the list.
    List<AIConversationMessage__c> rows = new List<AIConversationMessage__c>();

    for (String[] pair : messages) {

      rows.add(new AIConversationMessage__c(AIConversation__c = conversation.Id, Sender__c = pair[0], MessageBody__c = pair[1], ProcessingStatus__c = 'Complete'));
    }

    insert rows;
  }

  // 14 exchanges, long enough that the message list scrolls.
  List<String[]> buildLongConversation() {

    List<String[]> messages = new List<String[]>();
    List<String> questions = new List<String>{ 'Who owns this account?', 'When does the contract end?', 'What is the renewal value?', 'Are there any open cases?', 'Who is the main contact?', 'What did we discuss last time?', 'Is anything overdue?', 'Which products do they use?', 'What is the payment history?', 'Are they at risk of leaving?', 'What should I do next?', 'Draft a short summary for my manager.', 'Who else should be on the call?', 'What is the best time to call them?' };

    for (Integer i = 0; i < questions.size(); i++) {

      messages.add(new String[]{ 'User', questions.get(i) });
      messages.add(new String[]{ 'AI Agent', 'Answer ' + (i + 1) + ' of ' + questions.size() + '. This reply is written by hand so the list has enough height to scroll.\n\n- First point for the question "' + questions.get(i) + '"\n- Second point, with a little more detail so the reply takes several lines\n- Third point and a next step' });
    }

    return messages;
  }

  // Replies that read well as a note, a Chatter post and a task.
  List<String[]> buildSaveConversation() {

    return new List<String[]>{
      new String[]{ 'User', 'Summarise this account for me.' },
      new String[]{ 'AI Agent', 'Summary of the account:\n\n- Customer since 2021, mid-market, 2 active contracts\n- Renewal is due on 31 March 2027\n- One open billing query waiting on Finance' },
      new String[]{ 'User', 'What should I do next?' },
      new String[]{ 'AI Agent', 'Follow up with Finance on the billing query by Friday, then book a renewal call with the main contact before the end of the month.' }
    };
  }

  List<String[]> buildShortConversation() {

    return new List<String[]>{
      new String[]{ 'User', 'Give me a quick overview of this account.' },
      new String[]{ 'AI Agent', 'This is a mid-market customer with two active contracts and one open billing query.' },
      new String[]{ 'User', 'Is anything at risk?' },
      new String[]{ 'AI Agent', 'The billing query has been open for five days. Resolve it before the renewal conversation.' }
    };
  }

  // The conversation Dana started and shared with the signed-in user.
  List<String[]> buildSharedConversation() {

    return new List<String[]>{
      new String[]{ 'User', 'What should we say to this customer about the delay?' },
      new String[]{ 'AI Agent', 'Apologise for the delay, confirm the new date, and offer a named contact for any questions.' }
    };
  }
}

new ChatFeatureTestLoader().run();
