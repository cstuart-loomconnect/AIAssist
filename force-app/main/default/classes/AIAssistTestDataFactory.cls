/*
Class Name: AIAssistTestDataFactory

=================================================================
=================================================================

Description: The one place the test suite builds records. Every create method returns the records
it built and inserts them only when asked, so a test can adjust them first:

    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(1, false);
    agents[0].IsActive__c = true;
    insert agents;

Records are valid against the object model's validation rules (an active model configuration has
its connection details, an active prompt template has a prompt, and so on). Names are made unique
with a counter, because the unique Developer Name stamped by the triggers is derived from them.

Custom metadata cannot be inserted, so the PII masking rule is built in memory and handed to
AIPiiPseudonymizationService through its test seam.

Tests that need an end user build one with createUsers and assignPermissionSet, so a test run as
that user proves the security model rather than the code alone.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Rebuilt for the object model: users without AIAssistUserType__c, usage, assignment, terms and execution step builders, active agents and models that satisfy the validation rules.
3.0          Chandler Stuart          Violation rules are assigned to an agent through AIAgentViolationRule__c; builders for agent objects, usage policies and their assignments.
*/

@IsTest
public class AIAssistTestDataFactory {
  private static Integer sequence = 0;
  private static Id standardProfileId;

  // A name unique within the test run, for fields whose value is derived into a unique Developer Name.
  private static String uniqueName(String prefix) {
    sequence++;
    return prefix +
      ' ' +
      sequence +
      ' ' +
      System.Uuid.randomUUID().toString().left(8);
  }

  // =============================================================
  // Users
  // =============================================================

  // Standard users. They hold no AI Assist permission set until assignPermissionSet gives them one.
  public static List<User> createUsers(
    Integer numberOfUsers,
    Boolean shouldDoInsert
  ) {
    if (standardProfileId == null)
      standardProfileId = [
        SELECT Id
        FROM Profile
        WHERE Name IN ('Standard User', 'Minimum Access - Salesforce')
        ORDER BY Name DESC
        LIMIT 1
      ]
      .Id;

    List<User> users = new List<User>();

    for (Integer itemIndex = 0; itemIndex < numberOfUsers; itemIndex++) {
      String uniqueSuffix = uniqueName('u').remove(' ');

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
          ProfileId = standardProfileId
        )
      );
    }

    // User is a setup object, so it is inserted in its own context apart from the test's other records.
    if (shouldDoInsert && !users.isEmpty()) {
      System.runAs(new User(Id = UserInfo.getUserId())) {
        insert users;
      }
    }

    return users;
  }

  // Gives each user a permission set by API name (for example AIAssistUser). The users must already be inserted.
  public static void assignPermissionSet(
    List<User> users,
    String permissionSetName
  ) {
    Id permissionSetId = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :permissionSetName
      LIMIT 1
    ]
    .Id;

    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (User assignedUser : users)
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = assignedUser.Id,
          PermissionSetId = permissionSetId
        )
      );

    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert assignments;
    }
  }

  // Gives each user a permission set group (created here, containing the named permission set), so they hold that permission set only through the group and have no assignment row for it. The users must already be inserted.
  public static void assignPermissionSetGroup(
    List<User> users,
    String groupDeveloperName,
    String memberPermissionSetName
  ) {
    Id memberId = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :memberPermissionSetName
      LIMIT 1
    ]
    .Id;

    System.runAs(new User(Id = UserInfo.getUserId())) {
      PermissionSetGroup permissionSetGroup = new PermissionSetGroup(
        DeveloperName = groupDeveloperName,
        MasterLabel = groupDeveloperName
      );
      insert permissionSetGroup;
      insert new PermissionSetGroupComponent(
        PermissionSetGroupId = permissionSetGroup.Id,
        PermissionSetId = memberId
      );
      Test.calculatePermissionSetGroup(permissionSetGroup.Id);

      List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
      for (User assignedUser : users)
        assignments.add(
          new PermissionSetAssignment(
            AssigneeId = assignedUser.Id,
            PermissionSetGroupId = permissionSetGroup.Id
          )
        );
      insert assignments;
    }
  }

  public static List<Account> createAccounts(
    Integer numberOfAccounts,
    Boolean shouldDoInsert
  ) {
    List<Account> accounts = new List<Account>();
    for (Integer itemIndex = 0; itemIndex < numberOfAccounts; itemIndex++)
      accounts.add(new Account(Name = uniqueName('AI Assist Test Account')));

    if (shouldDoInsert && !accounts.isEmpty())
      insert accounts;

    return accounts;
  }

  // =============================================================
  // Configuration
  // =============================================================

  // Active, with the connection details the object model requires before a configuration can be active.
  public static List<AIModelConfiguration__c> createAIModelConfigurations(
    Integer numberOfConfigurations,
    Boolean shouldDoInsert
  ) {
    List<AIModelConfiguration__c> configurations = new List<AIModelConfiguration__c>();

    for (
      Integer itemIndex = 0; itemIndex < numberOfConfigurations; itemIndex++
    ) {
      configurations.add(
        new AIModelConfiguration__c(
          Name = uniqueName('AI Assist Test Model'),
          AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC,
          ModelIdentifier__c = 'test-model',
          NamedCredential__c = 'Test_Credential',
          ApiPath__c = '/v1/messages',
          IsActive__c = true,
          RetryAttempts__c = 2
        )
      );
    }

    if (shouldDoInsert && !configurations.isEmpty())
      insert configurations;

    return configurations;
  }

  // Inactive, with no model: the state of a new agent. Use the overload for one that can chat.
  public static List<AIAgent__c> createAIAgents(
    Integer numberOfAgents,
    Boolean shouldDoInsert
  ) {
    List<AIAgent__c> agents = new List<AIAgent__c>();
    for (Integer itemIndex = 0; itemIndex < numberOfAgents; itemIndex++)
      agents.add(new AIAgent__c(Name = uniqueName('AI Assist Test Agent')));

    if (shouldDoInsert && !agents.isEmpty())
      insert agents;

    return agents;
  }

  // Active agents open to all users, on the given model configuration, tracking the provider's own token counts.
  public static List<AIAgent__c> createAIAgents(
    Integer numberOfAgents,
    Id modelConfigurationId,
    Boolean shouldDoInsert
  ) {
    List<AIAgent__c> agents = createAIAgents(numberOfAgents, false);

    for (AIAgent__c agent : agents) {
      agent.AIModelConfiguration__c = modelConfigurationId;
      agent.IsActive__c = true;
      agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
      agent.TokenTrackingMethod__c = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;
    }

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
    List<AIPromptTemplate__c> templates = new List<AIPromptTemplate__c>();

    for (Integer itemIndex = 0; itemIndex < numberOfTemplates; itemIndex++) {
      templates.add(
        new AIPromptTemplate__c(
          Name = uniqueName('AI Assist Test Prompt Template'),
          AIAgent__c = agentId,
          IsActive__c = true,
          AIPrompt__c = 'Answer briefly.'
        )
      );
    }

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
    List<AIDataSource__c> dataSources = new List<AIDataSource__c>();

    for (Integer itemIndex = 0; itemIndex < numberOfDataSources; itemIndex++) {
      AIDataSource__c dataSource = new AIDataSource__c(
        SourceName__c = uniqueName('AI Assist Test Source'),
        SourceType__c = sourceType,
        IsActive__c = true
      );

      if (sourceType == AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX)
        dataSource.ApexClassName__c = sourceValue;
      else
        dataSource.SOQLTemplate__c = sourceValue;

      dataSources.add(dataSource);
    }

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
    List<AIWorkflowAction__c> actions = new List<AIWorkflowAction__c>();

    // Flow versions cannot be created in a test, so the Flow is declared to run in the default mode.
    if (
      actionType == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW &&
      String.isNotBlank(sourceValue)
    )
      AIFlowRunModeService.setRunModeForTest(sourceValue, null);

    for (Integer itemIndex = 0; itemIndex < numberOfActions; itemIndex++) {
      AIWorkflowAction__c workflowAction = new AIWorkflowAction__c(
        ActionName__c = uniqueName('Action').left(50),
        ActionType__c = actionType,
        ExecutionType__c = AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY,
        RequiresConfirmation__c = false,
        IsActive__c = true
      );

      if (actionType == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX)
        workflowAction.ApexClassName__c = sourceValue;
      else
        workflowAction.FlowAPIName__c = sourceValue;

      actions.add(workflowAction);
    }

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
    List<AIAgentDataSource__c> links = new List<AIAgentDataSource__c>();
    for (AIDataSource__c dataSource : dataSources)
      links.add(
        new AIAgentDataSource__c(
          AIAgent__c = agentId,
          AIDataSource__c = dataSource.Id,
          IsActive__c = true
        )
      );

    if (shouldDoInsert && !links.isEmpty())
      insert links;

    return links;
  }

  public static List<AIAgentWorkflowAction__c> createAIAgentWorkflowActions(
    Id agentId,
    List<AIWorkflowAction__c> actions,
    Boolean shouldDoInsert
  ) {
    List<AIAgentWorkflowAction__c> links = new List<AIAgentWorkflowAction__c>();
    for (AIWorkflowAction__c action : actions)
      links.add(
        new AIAgentWorkflowAction__c(
          AIAgent__c = agentId,
          AIWorkflowAction__c = action.Id,
          IsActive__c = true
        )
      );

    if (shouldDoInsert && !links.isEmpty())
      insert links;

    return links;
  }

  // One active assignment per user.
  public static List<AIAgentAssignment__c> createAIAgentAssignments(
    Id agentId,
    List<User> users,
    Boolean shouldDoInsert
  ) {
    List<AIAgentAssignment__c> assignments = new List<AIAgentAssignment__c>();

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

    if (shouldDoInsert && !assignments.isEmpty())
      insert assignments;

    return assignments;
  }

  // One active assignment to a permission set, by API name.
  public static List<AIAgentAssignment__c> createAIAgentAssignments(
    Id agentId,
    String permissionSetName,
    Boolean shouldDoInsert
  ) {
    List<AIAgentAssignment__c> assignments = new List<AIAgentAssignment__c>{
      new AIAgentAssignment__c(
        AIAgent__c = agentId,
        AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET,
        PermissionSetName__c = permissionSetName,
        IsActive__c = true
      )
    };

    if (shouldDoInsert)
      insert assignments;

    return assignments;
  }

  // =============================================================
  // Conversations
  // =============================================================

  // Active conversations owned by the running user.
  public static List<AIConversation__c> createAIConversations(
    Id agentId,
    Integer numberOfConversations,
    Boolean shouldDoInsert
  ) {
    return createAIConversations(
      agentId,
      null,
      numberOfConversations,
      shouldDoInsert
    );
  }

  public static List<AIConversation__c> createAIConversations(
    Id agentId,
    Id ownerId,
    Integer numberOfConversations,
    Boolean shouldDoInsert
  ) {
    List<AIConversation__c> conversations = new List<AIConversation__c>();

    for (
      Integer itemIndex = 0; itemIndex < numberOfConversations; itemIndex++
    ) {
      AIConversation__c conversation = new AIConversation__c(
        AIAgent__c = agentId,
        Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
        Channel__c = AIAssistApplicationConstants.CHANNEL_UTILITY_BAR
      );
      if (ownerId != null)
        conversation.OwnerId = ownerId;
      conversations.add(conversation);
    }

    if (shouldDoInsert && !conversations.isEmpty())
      insert conversations;

    return conversations;
  }

  // User messages.
  public static List<AIConversationMessage__c> createAIConversationMessages(
    Id conversationId,
    Decimal tokenCount,
    Integer numberOfMessages,
    Boolean shouldDoInsert
  ) {
    return createAIConversationMessages(
      conversationId,
      AIAssistApplicationConstants.SENDER_USER,
      tokenCount,
      numberOfMessages,
      shouldDoInsert
    );
  }

  // Only the package may write a message from the AI Agent or the System, so those are inserted through AIMessagingDataService, as the package does.
  public static List<AIConversationMessage__c> createAIConversationMessages(
    Id conversationId,
    String sender,
    Decimal tokenCount,
    Integer numberOfMessages,
    Boolean shouldDoInsert
  ) {
    List<AIConversationMessage__c> messages = new List<AIConversationMessage__c>();

    for (Integer itemIndex = 0; itemIndex < numberOfMessages; itemIndex++) {
      AIConversationMessage__c conversationMessage = new AIConversationMessage__c(
        AIConversation__c = conversationId,
        Sender__c = sender,
        MessageBody__c = 'Test message ' + itemIndex
      );
      // Left unset when null: the token count is system-managed, so a user cannot write it, even as null.
      if (tokenCount != null)
        conversationMessage.TokenCount__c = tokenCount;
      messages.add(conversationMessage);
    }

    if (shouldDoInsert && !messages.isEmpty()) {
      if (sender == AIAssistApplicationConstants.SENDER_USER)
        insert messages;
      else
        AIMessagingDataService.insertAsPackage(messages);
    }

    return messages;
  }

  // Steps of type Other, successful: neither a provider call (which needs a provider and model) nor a workflow action (which needs evidence of who confirmed it).
  public static List<AIExecutionStep__c> createAIExecutionSteps(
    Id messageId,
    Integer numberOfSteps,
    Boolean shouldDoInsert
  ) {
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

    if (shouldDoInsert && !steps.isEmpty())
      insert steps;

    return steps;
  }

  // =============================================================
  // Who may chat, and usage
  // =============================================================

  public static List<AIUserSettings__c> createAIUserSettings(
    Id userId,
    Boolean shouldDoInsert
  ) {
    List<AIUserSettings__c> userSettingsRows = new List<AIUserSettings__c>{
      new AIUserSettings__c(User__c = userId, IsActive__c = true)
    };

    if (shouldDoInsert)
      insert userSettingsRows;

    return userSettingsRows;
  }

  // Acknowledgments must be inserted by the user they are for; the object model refuses anyone else, so insert them inside System.runAs(user).
  public static List<AITermsAcknowledgment__c> createAITermsAcknowledgments(
    Id userId,
    String termsVersion,
    Integer numberOfAcknowledgments,
    Boolean shouldDoInsert
  ) {
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

    if (shouldDoInsert && !acknowledgments.isEmpty())
      insert acknowledgments;

    return acknowledgments;
  }

  // One row per day, counting back from today, each with the key the package would give it.
  public static List<AIUsageDaily__c> createAIUsageDailies(
    Id userId,
    Id agentId,
    Id modelConfigurationId,
    Integer numberOfDays,
    Boolean shouldDoInsert
  ) {
    List<AIUsageDaily__c> usageRows = new List<AIUsageDaily__c>();

    for (Integer itemIndex = 0; itemIndex < numberOfDays; itemIndex++) {
      Date usageDate = AIAssistGlobalUtility.getOrgToday().addDays(-itemIndex);

      usageRows.add(
        new AIUsageDaily__c(
          User__c = userId,
          AIAgent__c = agentId,
          AIModelConfiguration__c = modelConfigurationId,
          UsageDate__c = usageDate,
          UsageKey__c = userId +
            '|' +
            agentId +
            '|' +
            modelConfigurationId +
            '|' +
            Datetime.newInstanceGmt(
                usageDate.year(),
                usageDate.month(),
                usageDate.day()
              )
              .formatGmt('yyyyMMdd'),
          MessageCount__c = 0,
          ConversationCount__c = 0,
          FailedTurnCount__c = 0,
          InputTokens__c = 0,
          OutputTokens__c = 0,
          ViolationCount__c = 0
        )
      );
    }

    if (shouldDoInsert && !usageRows.isEmpty())
      insert usageRows;

    return usageRows;
  }

  // =============================================================
  // PII
  // =============================================================

  public static List<AIPIIRegistry__c> createAIPIIRegistries(
    Integer numberOfRegistries,
    String objectApiName,
    Boolean shouldDoInsert
  ) {
    List<AIPIIRegistry__c> registries = new List<AIPIIRegistry__c>();

    for (Integer itemIndex = 0; itemIndex < numberOfRegistries; itemIndex++)
      registries.add(
        new AIPIIRegistry__c(
          Name = uniqueName('AI Assist Test PII Registry'),
          ObjectAPIName__c = objectApiName
        )
      );

    if (shouldDoInsert && !registries.isEmpty())
      insert registries;

    return registries;
  }

  public static List<AIPIIFieldMetadata__c> createAIPIIFieldMetadata(
    Id registryId,
    String objectApiName,
    String fieldApiName,
    String piiFieldType,
    Boolean shouldDoInsert
  ) {
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

    if (shouldDoInsert)
      insert fieldMetadataRecords;

    return fieldMetadataRecords;
  }

  public static List<AIPIIMapping__c> createAIPIIMappings(
    Id conversationId,
    Map<String, String> originalToFakeValues,
    Boolean shouldDoInsert
  ) {
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

    // No permission set is granted AIPIIMapping__c (it holds real values next to fake ones), so even a test writes it in system mode.
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
    return new AIPiiDataMaskingRule__mdt(
      Strategy__c = strategy,
      SubstituteValues__c = substituteValues,
      IsActive__c = isActive
    );
  }

  // =============================================================
  // Violations, feedback and data deletion
  // =============================================================

  public static List<AIViolationRule__c> createAIViolationRules(
    Id agentId,
    Integer numberOfRules,
    String detectionMethod,
    Boolean shouldDoInsert
  ) {
    List<AIViolationRule__c> rules = new List<AIViolationRule__c>();

    for (Integer itemIndex = 0; itemIndex < numberOfRules; itemIndex++) {
      AIViolationRule__c violationRule = new AIViolationRule__c(
        Name = uniqueName('AI Assist Test Violation Rule').left(80),
        IsActive__c = true,
        DetectionMethod__c = detectionMethod,
        ViolationTypeProduced__c = AIAssistApplicationConstants.VIOLATION_TYPE_AI_FLAGGED_INTENT,
        SignalTag__c = 'TAG_' +
          String.valueOf(Math.abs(Crypto.getRandomLong())).left(30)
      );

      if (
        detectionMethod ==
        AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED
      )
        violationRule.AIDetectionInstruction__c = 'The user asks for a bulk export of records.';

      rules.add(violationRule);
    }

    if (shouldDoInsert && !rules.isEmpty()) {
      insert rules;
      if (agentId != null)
        createAIAgentViolationRules(agentId, rules, true);
    }

    return rules;
  }

  // Assigns existing rules to an agent, so the agent applies them.
  public static List<AIAgentViolationRule__c> createAIAgentViolationRules(
    Id agentId,
    List<AIViolationRule__c> rules,
    Boolean shouldDoInsert
  ) {
    List<AIAgentViolationRule__c> links = new List<AIAgentViolationRule__c>();
    for (AIViolationRule__c rule : rules)
      links.add(
        new AIAgentViolationRule__c(
          AIAgent__c = agentId,
          AIViolationRule__c = rule.Id,
          IsActive__c = true
        )
      );

    if (shouldDoInsert && !links.isEmpty())
      insert links;

    return links;
  }

  // Adds objects to an agent, one record per object API name.
  public static List<AIAgentObject__c> createAIAgentObjects(
    Id agentId,
    List<String> objectApiNames,
    Boolean shouldDoInsert
  ) {
    List<AIAgentObject__c> agentObjects = new List<AIAgentObject__c>();
    for (String objectApiName : objectApiNames)
      agentObjects.add(
        new AIAgentObject__c(
          AIAgent__c = agentId,
          ObjectApiName__c = objectApiName,
          IsActive__c = true
        )
      );

    if (shouldDoInsert && !agentObjects.isEmpty())
      insert agentObjects;

    return agentObjects;
  }

  public static List<AIUsagePolicy__c> createAIUsagePolicies(
    Integer numberOfPolicies,
    Boolean shouldDoInsert
  ) {
    List<AIUsagePolicy__c> policies = new List<AIUsagePolicy__c>();
    for (Integer itemIndex = 0; itemIndex < numberOfPolicies; itemIndex++)
      policies.add(
        new AIUsagePolicy__c(
          Name = uniqueName('AI Assist Test Usage Policy').left(80),
          IsActive__c = true
        )
      );

    if (shouldDoInsert && !policies.isEmpty())
      insert policies;

    return policies;
  }

  // Assigns a policy to users (one record each), or to a permission set by name when the user list is null.
  public static List<AIUsagePolicyAssignment__c> createAIUsagePolicyAssignments(
    Id policyId,
    List<User> users,
    String permissionSetName,
    Boolean shouldDoInsert
  ) {
    List<AIUsagePolicyAssignment__c> assignments = new List<AIUsagePolicyAssignment__c>();
    if (users != null) {
      for (User assignedUser : users)
        assignments.add(
          new AIUsagePolicyAssignment__c(
            AIUsagePolicy__c = policyId,
            AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_USER,
            User__c = assignedUser.Id,
            IsActive__c = true
          )
        );
    } else {
      assignments.add(
        new AIUsagePolicyAssignment__c(
          AIUsagePolicy__c = policyId,
          AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET,
          PermissionSetName__c = permissionSetName,
          IsActive__c = true
        )
      );
    }

    if (shouldDoInsert && !assignments.isEmpty())
      insert assignments;

    return assignments;
  }

  // Violations are written by the package, so they are inserted in system mode.
  public static List<AIViolation__c> createAIViolations(
    Id ruleId,
    Id userId,
    Id conversationId,
    Integer numberOfViolations,
    Boolean shouldDoInsert
  ) {
    List<AIViolation__c> violations = new List<AIViolation__c>();

    for (Integer itemIndex = 0; itemIndex < numberOfViolations; itemIndex++) {
      violations.add(
        new AIViolation__c(
          AIViolationRule__c = ruleId,
          User__c = userId,
          AIConversation__c = conversationId,
          ViolationType__c = AIAssistApplicationConstants.VIOLATION_TYPE_AI_FLAGGED_INTENT,
          Severity__c = AIAssistApplicationConstants.SEVERITY_MEDIUM,
          ReviewStatus__c = AIAssistApplicationConstants.REVIEW_STATUS_NEW,
          Detail__c = 'Test violation ' + itemIndex
        )
      );
    }

    if (shouldDoInsert && !violations.isEmpty())
      Database.insert(violations, true, AccessLevel.SYSTEM_MODE);

    return violations;
  }

  public static List<AIFeedback__c> createAIFeedback(
    Id conversationId,
    Id messageId,
    Integer numberOfFeedback,
    Boolean shouldDoInsert
  ) {
    List<AIFeedback__c> feedback = new List<AIFeedback__c>();

    for (Integer itemIndex = 0; itemIndex < numberOfFeedback; itemIndex++)
      feedback.add(
        new AIFeedback__c(
          AIConversation__c = conversationId,
          AIConversationMessage__c = messageId,
          Rating__c = 'Helpful'
        )
      );

    if (shouldDoInsert && !feedback.isEmpty())
      insert feedback;

    return feedback;
  }

  // A request about one user, or about one record when subjectRecordId is given.
  public static List<AIDataDeletionRequest__c> createAIDataDeletionRequests(
    Id subjectUserId,
    String subjectRecordId,
    Integer numberOfRequests,
    Boolean shouldDoInsert
  ) {
    List<AIDataDeletionRequest__c> requests = new List<AIDataDeletionRequest__c>();

    for (Integer itemIndex = 0; itemIndex < numberOfRequests; itemIndex++) {
      requests.add(
        new AIDataDeletionRequest__c(
          ReceivedDate__c = Datetime.now().dateGmt(),
          RequestReference__c = uniqueName('Request').left(80),
          Scope__c = subjectRecordId == null
            ? AIAssistApplicationConstants.DELETION_SCOPE_USER
            : AIAssistApplicationConstants.DELETION_SCOPE_RELATED_RECORD,
          SubjectUser__c = subjectRecordId == null ? subjectUserId : null,
          SubjectRecordId__c = subjectRecordId
        )
      );
    }

    if (shouldDoInsert && !requests.isEmpty())
      insert requests;

    return requests;
  }
}
