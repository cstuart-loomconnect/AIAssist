/*
Class Name: AIAssistTestDataFactory

=================================================================
=================================================================

Description: Builds and optionally inserts the records that AI Assist tests need.

Step 1: A test asks for a number of records, and says whether to insert them
Step 2: Each method builds the records with the minimum valid values
Step 3: The records are inserted when asked, then returned

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
public class AIAssistTestDataFactory {
  // Standard users. They hold no AI Assist permission set until assignPermissionSet gives them one.
  public static List<User> createUsers(
    Integer numberOfUsers,
    Boolean shouldDoInsert
  ) {
    // [1] Find the profile the users will have
    List<User> users = new List<User>();
    Id profileId = [
      SELECT Id
      FROM Profile
      WHERE Name IN ('Standard User')
      ORDER BY Name DESC
      LIMIT 1
    ]
    .Id;

    // [2] Build each user with a unique name so they never clash
    for (Integer itemIndex = 0; itemIndex < numberOfUsers; itemIndex++) {
      String uniqueSuffix =
        'u' + System.Uuid.randomUUID().toString().remove('-').left(20);

      users.add(
        new User(
          FirstName = 'AI',
          LastName = 'Assist Tester',
          Email = uniqueSuffix + '@example.com',
          Username = uniqueSuffix + '@example.com.aiassisttest',
          Alias = uniqueSuffix.right(8),
          TimeZoneSidKey = 'GMT',
          LocaleSidKey = 'en_US',
          EmailEncodingKey = 'UTF-8',
          LanguageLocaleKey = 'en_US',
          ProfileId = profileId
        )
      );
    }

    // [3] Insert them when asked, and return them
    if (shouldDoInsert && !users.isEmpty())
      insertAsSetupUser(users);

    return users;
  }

  // Gives each user a permission set by API name (for example AIAssistUser). The users must already be inserted.
  public static void assignPermissionSet(
    List<User> users,
    String permissionSetName
  ) {
    // [1] Find the permission set
    Id permissionSetId = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :permissionSetName
      LIMIT 1
    ]
    .Id;
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();

    // [2] Build one assignment for each user
    for (User assignedUser : users) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = assignedUser.Id,
          PermissionSetId = permissionSetId
        )
      );
    }

    // [3] Insert the assignments
    insertAsSetupUser(assignments);
  }

  // Plain accounts with unique names.
  public static List<Account> createAccounts(
    Integer numberOfAccounts,
    Boolean shouldDoInsert
  ) {
    // [1] Build each account with a unique name
    List<Account> accounts = new List<Account>();

    for (Integer itemIndex = 0; itemIndex < numberOfAccounts; itemIndex++) {
      accounts.add(
        new Account(Name = 'AI Assist Test Account ' + uniqueSuffix())
      );
    }

    // [2] Insert them when asked, and return them
    if (shouldDoInsert && !accounts.isEmpty())
      insert accounts;

    return accounts;
  }

  // Active, with the connection details the object model requires before a configuration can be active.
  public static List<AIModelConfiguration__c> createAIModelConfigurations(
    Integer numberOfConfigurations,
    Boolean shouldDoInsert
  ) {
    // [1] Build each configuration with the connection details it needs to be active
    List<AIModelConfiguration__c> configurations = new List<AIModelConfiguration__c>();

    for (
      Integer itemIndex = 0; itemIndex < numberOfConfigurations; itemIndex++
    ) {
      configurations.add(
        new AIModelConfiguration__c(
          Name = 'AI Assist Test Model ' + uniqueSuffix(),
          AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC,
          ModelIdentifier__c = 'test-model',
          NamedCredential__c = 'Test_Credential',
          ApiPath__c = '/v1/messages',
          IsActive__c = true
        )
      );
    }

    // [2] Insert them when asked, and return them
    if (shouldDoInsert && !configurations.isEmpty())
      insert configurations;

    return configurations;
  }

  // With a model configuration: active, open to all users, tracking the provider's own token counts. Without one (null): inactive with no model, the state of a new agent.
  public static List<AIAgent__c> createAIAgents(
    Integer numberOfAgents,
    Id modelConfigurationId,
    Boolean shouldDoInsert
  ) {
    // [1] Build each agent with a unique name
    List<AIAgent__c> agents = new List<AIAgent__c>();

    for (Integer itemIndex = 0; itemIndex < numberOfAgents; itemIndex++) {
      AIAgent__c agent = new AIAgent__c(
        Name = 'AI Assist Test Agent ' + uniqueSuffix(),
        DeveloperName__c = 'Agent_' + uniqueSuffix()
      );

      // [2] Make the agent active only when it has a model configuration
      if (modelConfigurationId != null) {
        agent.AIModelConfiguration__c = modelConfigurationId;
        agent.IsActive__c = true;
        agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
        agent.TokenTrackingMethod__c = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;
      }

      agents.add(agent);
    }

    // [3] Insert them when asked, and return them
    if (shouldDoInsert && !agents.isEmpty())
      insert agents;

    return agents;
  }

  // Active, with the prompt the object model requires before a template can be active.
  public static List<AIPromptTemplate__c> createAIPromptTemplates(
    Id agentId,
    Integer numberOfTemplates,
    Boolean shouldDoInsert
  ) {
    // [1] Build each template with the prompt it needs to be active
    List<AIPromptTemplate__c> templates = new List<AIPromptTemplate__c>();

    for (Integer itemIndex = 0; itemIndex < numberOfTemplates; itemIndex++) {
      templates.add(
        new AIPromptTemplate__c(
          Name = 'AI Assist Test Prompt Template ' + uniqueSuffix(),
          AIAgent__c = agentId,
          IsActive__c = true,
          AIPrompt__c = 'Answer briefly.'
        )
      );
    }

    // [2] Insert them when asked, and return them
    if (shouldDoInsert && !templates.isEmpty())
      insert templates;

    return templates;
  }

  // sourceValue is the SOQL template when sourceType is SOQL, or the Apex class name when it is Apex.
  public static List<AIDataSource__c> createAIDataSources(
    Integer numberOfDataSources,
    String sourceType,
    String sourceValue,
    Boolean shouldDoInsert
  ) {
    // [1] Build each data source with a unique name
    List<AIDataSource__c> dataSources = new List<AIDataSource__c>();

    for (Integer itemIndex = 0; itemIndex < numberOfDataSources; itemIndex++) {
      AIDataSource__c dataSource = new AIDataSource__c(
        SourceName__c = 'AI Assist Test Source ' + uniqueSuffix(),
        DeveloperName__c = 'Source_' + uniqueSuffix(),
        SourceType__c = sourceType,
        IsActive__c = true
      );

      // [2] Put the source value in the field that matches the source type
      if (sourceType == AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX)
        dataSource.ApexClassName__c = sourceValue;
      else
        dataSource.SOQLTemplate__c = sourceValue;

      dataSources.add(dataSource);
    }

    // [3] Insert them when asked, and return them
    if (shouldDoInsert && !dataSources.isEmpty())
      insert dataSources;

    return dataSources;
  }

  // sourceValue is the Apex class name when actionType is Apex, or the Flow API name when it is Flow. Read only, so no confirmation is needed.
  public static List<AIWorkflowAction__c> createAIWorkflowActions(
    Integer numberOfActions,
    String actionType,
    String sourceValue,
    Boolean shouldDoInsert
  ) {
    // [1] Build each action as read only, with a unique name
    List<AIWorkflowAction__c> actions = new List<AIWorkflowAction__c>();

    for (Integer itemIndex = 0; itemIndex < numberOfActions; itemIndex++) {
      AIWorkflowAction__c workflowAction = new AIWorkflowAction__c(
        ActionName__c = 'Action ' + uniqueSuffix(),
        DeveloperName__c = 'Action_' + uniqueSuffix(),
        ActionType__c = actionType,
        ExecutionType__c = AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY,
        RequiresConfirmation__c = false,
        IsActive__c = true
      );

      // [2] Put the source value in the field that matches the action type
      if (actionType == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX)
        workflowAction.ApexClassName__c = sourceValue;
      else
        workflowAction.FlowAPIName__c = sourceValue;

      actions.add(workflowAction);
    }

    // [3] Insert them when asked, and return them
    if (shouldDoInsert && !actions.isEmpty())
      insert actions;

    return actions;
  }

  // Links the data sources to the agent, active.
  public static List<AIAgentDataSource__c> createAIAgentDataSources(
    Id agentId,
    List<AIDataSource__c> dataSources,
    Boolean shouldDoInsert
  ) {
    // [1] Build one active link for each data source
    List<AIAgentDataSource__c> links = new List<AIAgentDataSource__c>();

    for (AIDataSource__c dataSource : dataSources) {
      links.add(
        new AIAgentDataSource__c(
          AIAgent__c = agentId,
          AIDataSource__c = dataSource.Id,
          IsActive__c = true
        )
      );
    }

    // [2] Insert them when asked, and return them
    if (shouldDoInsert && !links.isEmpty())
      insert links;

    return links;
  }

  // Links the workflow actions to the agent, active.
  public static List<AIAgentWorkflowAction__c> createAIAgentWorkflowActions(
    Id agentId,
    List<AIWorkflowAction__c> actions,
    Boolean shouldDoInsert
  ) {
    // [1] Build one active link for each workflow action
    List<AIAgentWorkflowAction__c> links = new List<AIAgentWorkflowAction__c>();

    for (AIWorkflowAction__c action : actions) {
      links.add(
        new AIAgentWorkflowAction__c(
          AIAgent__c = agentId,
          AIWorkflowAction__c = action.Id,
          IsActive__c = true
        )
      );
    }

    // [2] Insert them when asked, and return them
    if (shouldDoInsert && !links.isEmpty())
      insert links;

    return links;
  }

  // One active assignment per user, plus one to the permission set (by API name) when given. Either may be null.
  public static List<AIAgentAssignment__c> createAIAgentAssignments(
    Id agentId,
    List<User> users,
    String permissionSetName,
    Boolean shouldDoInsert
  ) {
    List<AIAgentAssignment__c> assignments = new List<AIAgentAssignment__c>();

    // [1] Build one assignment for each user
    if (users != null) {
      for (User assignedUser : users) {
        assignments.add(
          new AIAgentAssignment__c(
            AIAgent__c = agentId,
            AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_USER,
            User__c = assignedUser.Id,
            IsActive__c = true
          )
        );
      }
    }

    // [2] Build one assignment for the permission set
    if (permissionSetName != null) {
      assignments.add(
        new AIAgentAssignment__c(
          AIAgent__c = agentId,
          AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET,
          PermissionSetName__c = permissionSetName,
          IsActive__c = true
        )
      );
    }

    // [3] Insert them when asked, and return them
    if (shouldDoInsert && !assignments.isEmpty())
      insert assignments;

    return assignments;
  }

  // Active conversations, owned by ownerId or by the running user when it is null.
  public static List<AIConversation__c> createAIConversations(
    Id agentId,
    Id ownerId,
    Integer numberOfConversations,
    Boolean shouldDoInsert
  ) {
    // [1] Build each conversation as active
    List<AIConversation__c> conversations = new List<AIConversation__c>();

    for (
      Integer itemIndex = 0; itemIndex < numberOfConversations; itemIndex++
    ) {
      AIConversation__c conversation = new AIConversation__c(
        AIAgent__c = agentId,
        Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
        Channel__c = AIAssistApplicationConstants.CHANNEL_UTILITY_BAR
      );

      // [2] Set the owner only when one is given
      if (ownerId != null)
        conversation.OwnerId = ownerId;

      conversations.add(conversation);
    }

    // [3] Insert them when asked, and return them
    if (shouldDoInsert && !conversations.isEmpty())
      insert conversations;

    return conversations;
  }

  // Only AIMessagingDataService may write a message from the AI Agent or the System, so those are inserted through it.
  public static List<AIConversationMessage__c> createAIConversationMessages(
    Id conversationId,
    String sender,
    Decimal tokenCount,
    Integer numberOfMessages,
    Boolean shouldDoInsert
  ) {
    // [1] Build each message
    List<AIConversationMessage__c> messages = new List<AIConversationMessage__c>();

    for (Integer itemIndex = 0; itemIndex < numberOfMessages; itemIndex++) {
      AIConversationMessage__c conversationMessage = new AIConversationMessage__c(
        AIConversation__c = conversationId,
        Sender__c = sender,
        MessageBody__c = 'Test message ' + itemIndex
      );

      // [2] Leave the token count unset when null: it is system-managed, so a user cannot write it, even as null
      if (tokenCount != null)
        conversationMessage.TokenCount__c = tokenCount;

      messages.add(conversationMessage);
    }

    // [3] Insert them when asked: user messages directly, the rest through the messaging service
    if (shouldDoInsert && !messages.isEmpty()) {
      if (sender == AIAssistApplicationConstants.SENDER_USER)
        insert messages;
      else
        AIMessagingDataService.insertOrThrow(messages);
    }

    return messages;
  }

  // Steps of type Other, successful: neither a provider call (which needs a provider and model) nor a workflow action (which needs evidence of who confirmed it).
  public static List<AIExecutionStep__c> createAIExecutionSteps(
    Id messageId,
    Integer numberOfSteps,
    Boolean shouldDoInsert
  ) {
    // [1] Build each step in order
    List<AIExecutionStep__c> steps = new List<AIExecutionStep__c>();

    for (Integer itemIndex = 0; itemIndex < numberOfSteps; itemIndex++) {
      steps.add(
        new AIExecutionStep__c(
          AIConversationMessage__c = messageId,
          StepType__c = AIAssistApplicationConstants.STEP_TYPE_OTHER,
          Status__c = AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS,
          StepOrder__c = itemIndex + 1
        )
      );
    }

    // [2] Insert them when asked, and return them
    if (shouldDoInsert && !steps.isEmpty())
      insert steps;

    return steps;
  }

  // One active settings row for the user.
  public static List<AIUserSettings__c> createAIUserSettings(
    Id userId,
    Boolean shouldDoInsert
  ) {
    // [1] Build the settings row
    List<AIUserSettings__c> userSettingsRows = new List<AIUserSettings__c>{
      new AIUserSettings__c(User__c = userId, IsActive__c = true)
    };

    // [2] Insert it when asked, and return it
    if (shouldDoInsert && !userSettingsRows.isEmpty())
      insert userSettingsRows;

    return userSettingsRows;
  }

  // The org-level UI settings that switch debug mode and Workflow Actions on or off for every user.
  public static AIAssistUISettings__c upsertUiSettings(
    Boolean isDebugModeEnabled,
    Boolean areWorkflowActionsEnabled
  ) {
    // [1] Set the two switches on the org defaults and save them
    AIAssistUISettings__c uiSettings = AIAssistUISettings__c.getOrgDefaults();
    uiSettings.IsDebugModeEnabled__c = isDebugModeEnabled;
    uiSettings.AreWorkflowActionsEnabled__c = areWorkflowActionsEnabled;
    upsert uiSettings;

    return uiSettings;
  }

  // Acknowledgments must be inserted by the user they are for; the object model refuses anyone else, so insert them inside System.runAs(user).
  public static List<AITermsAcknowledgment__c> createAITermsAcknowledgments(
    Id userId,
    String termsVersion,
    Integer numberOfAcknowledgments,
    Boolean shouldDoInsert
  ) {
    // [1] Build each acknowledgment
    List<AITermsAcknowledgment__c> acknowledgments = new List<AITermsAcknowledgment__c>();

    for (
      Integer itemIndex = 0; itemIndex < numberOfAcknowledgments; itemIndex++
    ) {
      acknowledgments.add(
        new AITermsAcknowledgment__c(
          User__c = userId,
          TermsVersion__c = termsVersion,
          SignatureText__c = 'AI Assist Tester'
        )
      );
    }

    // [2] Insert them when asked, and return them
    if (shouldDoInsert && !acknowledgments.isEmpty())
      insert acknowledgments;

    return acknowledgments;
  }

  // Registries for an object, with unique names.
  public static List<AIPIIRegistry__c> createAIPIIRegistries(
    Integer numberOfRegistries,
    String objectApiName,
    Boolean shouldDoInsert
  ) {
    // [1] Build each registry with a unique name
    List<AIPIIRegistry__c> registries = new List<AIPIIRegistry__c>();

    for (Integer itemIndex = 0; itemIndex < numberOfRegistries; itemIndex++) {
      registries.add(
        new AIPIIRegistry__c(
          Name = 'AI Assist Test PII Registry ' + uniqueSuffix(),
          ObjectAPIName__c = objectApiName
        )
      );
    }

    // [2] Insert them when asked, and return them
    if (shouldDoInsert && !registries.isEmpty())
      insert registries;

    return registries;
  }

  // One field record for the registry. It counts as PII only when a field type is given.
  public static List<AIPIIFieldMetadata__c> createAIPIIFieldMetadata(
    Id registryId,
    String objectApiName,
    String fieldApiName,
    String piiFieldType,
    Boolean shouldDoInsert
  ) {
    // [1] Build the field record
    List<AIPIIFieldMetadata__c> fieldMetadataRecords = new List<AIPIIFieldMetadata__c>{
      new AIPIIFieldMetadata__c(
        PIIRegistry__c = registryId,
        FieldKey__c = objectApiName + '.' + fieldApiName,
        FieldAPIName__c = fieldApiName,
        FieldLabel__c = fieldApiName,
        IsPII__c = piiFieldType != null,
        PIIFieldType__c = piiFieldType
      )
    };

    // [2] Insert it when asked, and return it
    if (shouldDoInsert && !fieldMetadataRecords.isEmpty())
      insert fieldMetadataRecords;

    return fieldMetadataRecords;
  }

  // One mapping of original values to fake values for the conversation.
  public static List<AIPIIMapping__c> createAIPIIMappings(
    Id conversationId,
    Map<String, String> originalToFakeValues,
    Boolean shouldDoInsert
  ) {
    // [1] Build the mapping, using an empty map when none is given
    List<AIPIIMapping__c> mappings = new List<AIPIIMapping__c>{
      new AIPIIMapping__c(
        AIConversation__c = conversationId,
        MappingJson__c = JSON.serialize(
          originalToFakeValues == null
            ? new Map<String, String>()
            : originalToFakeValues
        )
      )
    };

    // [2] Insert it in system mode when asked: no permission set is granted AIPIIMapping__c (it holds real values next to fake ones), so even a test writes it that way
    if (shouldDoInsert)
      Database.insert(mappings, true, AccessLevel.SYSTEM_MODE);

    return mappings;
  }

  // Custom metadata cannot be inserted, so the rule is built in memory for AIPiiPseudonymizationService's test seam.
  public static AIPiiDataMaskingRule__mdt createAIPiiMaskingRule(
    String strategy,
    String substituteValues,
    Boolean isActive
  ) {
    // [1] Build the rule in memory
    return new AIPiiDataMaskingRule__mdt(
      Strategy__c = strategy,
      SubstituteValues__c = substituteValues,
      IsActive__c = isActive
    );
  }

  // Helpful feedback on a message.
  public static List<AIFeedback__c> createAIFeedback(
    Id conversationId,
    Id messageId,
    Integer numberOfFeedback,
    Boolean shouldDoInsert
  ) {
    // [1] Build each feedback record as helpful
    List<AIFeedback__c> feedback = new List<AIFeedback__c>();

    for (Integer itemIndex = 0; itemIndex < numberOfFeedback; itemIndex++) {
      feedback.add(
        new AIFeedback__c(
          AIConversation__c = conversationId,
          AIConversationMessage__c = messageId,
          Rating__c = 'Helpful'
        )
      );
    }

    // [2] Insert them when asked, and return them
    if (shouldDoInsert && !feedback.isEmpty())
      insert feedback;

    return feedback;
  }

  // A short random text that keeps names unique.
  private static String uniqueSuffix() {
    // [1] Use the first part of a random id
    return System.Uuid.randomUUID().toString().left(8);
  }

  // User is a setup object, so it is inserted in its own context apart from the test's other records.
  private static void insertAsSetupUser(List<SObject> records) {
    // [1] Insert as the running user, in a separate context
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert records;
    }
  }
}
