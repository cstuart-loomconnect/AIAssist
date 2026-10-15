/*
Script Name: screen-flow-demo-account.apex

=================================================================
=================================================================

Description: Builds a fresh Account to test a Screen Flow suggested action from the chat window.

Step 1: Create a new Account with a timestamp in its name, so every run gives you a clean one
Step 2: Create (or update) the "Screen Flow - Update Account" action, which runs the AIChat_Demo_Update_Account flow
Step 3: Assign the action to the Account agent, so the chat offers it on an Account record
Step 4: Simulate the conversation, because no AI connection is needed: an Active conversation on the
        Account with a user question and an AI Agent reply that already suggests the action
Step 5: Print the Account's record Id so you can open it and see the suggested action card

Needs: the flow AIChat_Demo_Update_Account deployed, and an active Account agent (the demo
loader's "demo_account_assistant" is used when it exists).

Run:  sf apex run --file scripts/apex/screen-flow-demo-account.apex --target-org <alias>
Safe to run again: the action is updated, never duplicated; the Account is always new.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public class ScreenFlowDemoLoader {
  // =============================================================
  // Options
  // =============================================================

  Boolean isProductionAllowed = false; // The script refuses to run outside a sandbox or scratch org unless this is set.
  String flowApiName = 'AIChat_Demo_Update_Account';
  String agentDeveloperName = 'demo_account_assistant'; // Blank, or not found: the first active agent that covers Account is used.
  String actionDeveloperName = 'Demo_Screen_Flow_Update_Account';

  // =============================================================

  public void run() {
    if (
      !isProductionAllowed &&
      ![SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox
    ) {
      System.debug(LoggingLevel.ERROR, 'Not a sandbox or scratch org. Nothing was created.');
      return;
    }

    // [1] Find the agent first, so nothing is created when there is nobody to offer the action
    AIAgent__c agent = findAccountAgent();

    if (agent == null) {
      System.debug(LoggingLevel.ERROR, 'No active agent covers Account. Run conversation-demo-data.apex first. Nothing was created.');
      return;
    }

    // [2] A fresh Account every run
    String stamp = Datetime.now().format('yyyy-MM-dd HH:mm:ss');
    Account account = new Account(
      Name = 'Screen Flow Test - ' + stamp,
      Phone = '020 7946 0000',
      Description = 'Created by screen-flow-demo-account.apex to test the Screen Flow action. Change the phone and description in the flow, then check this record.'
    );
    insert account;

    // [3] The action: created once, then updated
    AIWorkflowAction__c action = buildAction();
    upsert action DeveloperName__c;

    // [4] Assign the action to the agent when it is not assigned yet
    Integer assigned = [SELECT COUNT() FROM AIAgentWorkflowAction__c WHERE AIAgent__c = :agent.Id AND AIWorkflowAction__c = :action.Id];

    if (assigned == 0)
      insert new AIAgentWorkflowAction__c(AIAgent__c = agent.Id, AIWorkflowAction__c = action.Id, IsActive__c = true);

    // [5] Simulate the conversation: the reply is written by hand and already carries the suggested action
    AIConversation__c conversation = new AIConversation__c(
      AIAgent__c = agent.Id,
      Channel__c = 'Record Page Chat',
      Status__c = 'Active',
      RelatedObjectAPIName__c = 'Account',
      RelatedRecordId__c = account.Id,
      OwnerId = UserInfo.getUserId()
    );
    insert conversation;

    AIConversationMessage__c userMessage = new AIConversationMessage__c(
      AIConversation__c = conversation.Id,
      Sender__c = 'User',
      MessageBody__c = 'Can you update the phone number on this account?',
      ProcessingStatus__c = 'Complete'
    );
    insert userMessage;

    AIConversationMessage__c reply = new AIConversationMessage__c(
      AIConversation__c = conversation.Id,
      InReplyTo__c = userMessage.Id,
      Sender__c = 'AI Agent',
      MessageBody__c = 'Yes. Use the action below to open a form where you can change the phone number and description.',
      ProcessingStatus__c = 'Complete',
      SuggestedWorkflowAction__c = action.Id
    );
    insert reply;

    // [6] Tell the tester where to go
    System.debug(LoggingLevel.ERROR, 'Account: ' + account.Id + ' (' + account.Name + ')');
    System.debug(LoggingLevel.ERROR, 'Agent: ' + agent.Name + '. Action: ' + action.ActionName__c);
    System.debug(LoggingLevel.ERROR, 'Open the Account and the chat window: the reply already shows the suggested action.');
  }

  AIAgent__c findAccountAgent() {
    List<AIAgent__c> agents = [
      SELECT Id, Name
      FROM AIAgent__c
      WHERE IsActive__c = TRUE AND DeveloperName__c = :agentDeveloperName
      LIMIT 1
    ];

    if (agents.isEmpty())
      agents = [
        SELECT Id, Name
        FROM AIAgent__c
        WHERE IsActive__c = TRUE AND ObjectApiNames__c LIKE '%Account%'
        LIMIT 1
      ];

    return agents.isEmpty() ? null : agents[0];
  }

  AIWorkflowAction__c buildAction() {
    return new AIWorkflowAction__c(
      ActionName__c = 'Update Account Details',
      DeveloperName__c = actionDeveloperName,
      Description__c = 'Opens a form where the user can change the Account phone number and description. Use when the user wants to update the account contact details.',
      ActionType__c = 'Screen Flow',
      FlowAPIName__c = flowApiName,
      ExecutionType__c = 'Write',
      RequiresConfirmation__c = true,
      ConfirmationMessage__c = 'Open the form to update this account?',
      TargetObject__c = 'Account',
      InputSchema__c = '{"type":"object","properties":{}}',
      OutputDescription__c = 'The user saves the form; nothing is returned to the chat.',
      IsActive__c = true
    );
  }
}

new ScreenFlowDemoLoader().run();
