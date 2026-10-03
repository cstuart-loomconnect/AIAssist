/*
Class Name: AIMessagingSelector

=================================================================
=================================================================

Description: Every query the messaging layer makes on data the end user is deliberately NOT
allowed to read: the configuration a turn runs on, who may use which agent, usage, and terms.
Queries only; nothing here changes a record (AIMessagingDataService does).

This is one of two `without sharing` classes in the messaging layer, and every statement is
explicit system mode, for the reasons in docs/SECURITY_MODEL.md sections 3 and 4:
- Model connection details, prompts, data source definitions, user settings, assignments and
  usage are readable only by Admin and Super User. The package reads them on the user's behalf;
  the user must never be given that access in order to chat.
- Some of the queries lock the rows they read (FOR UPDATE) so that a total is added to instead of
  overwritten.

Nothing here decides WHO may do something. The caller authorises first (AIMessageValidator,
or a user-mode read of the conversation) and only then asks. A user Id passed in is used as a
filter, never as a permission check.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, as the read half of AIMessagingRepository.
2.0          Chandler Stuart          Rules reach an agent through AIAgentViolationRule__c or AppliesToAllAgents__c; an agent can be offered on several objects (AIAgentObject__c); user settings are the user row over the usage policies that apply to them.
*/

public without sharing class AIMessagingSelector {
  public static final String TERMS_ACCEPTED = 'ACCEPTED';
  public static final String TERMS_OUTDATED = 'OUTDATED';
  public static final String TERMS_NONE = 'NONE';

  // Tokens and counts for one user or one organisation over a period.
  public class UsageTotals {
    public Decimal messages = 0;
    public Decimal conversations = 0;
    public Decimal tokens = 0;
  }

  // Organisation-wide totals for the current month and the current day, from one query.
  public class OrgUsage {
    public UsageTotals month = new UsageTotals();
    public UsageTotals today = new UsageTotals();
  }

  // =============================================================
  // What a turn runs on
  // =============================================================

  public static AIAgent__c getAgent(Id agentId) {
    if (agentId == null)
      return null;

    List<AIAgent__c> agents = [
      SELECT
        Id,
        Name,
        DeveloperName__c,
        IsActive__c,
        AccessMode__c,
        ObjectType__c,
        AIModelConfiguration__c,
        MaxMessagesPerConversation__c,
        MaxTokensPerConversation__c,
        MaxToolCallingIterations__c,
        SingleActiveConversationPerRecord__c,
        TokenTrackingMethod__c
      FROM AIAgent__c
      WHERE Id = :agentId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    return agents.isEmpty() ? null : agents[0];
  }

  public static AIModelConfiguration__c getModelConfiguration(
    Id modelConfigurationId
  ) {
    if (modelConfigurationId == null)
      return null;

    List<AIModelConfiguration__c> configurations = [
      SELECT
        Id,
        DeveloperName__c,
        AIProvider__c,
        ModelIdentifier__c,
        NamedCredential__c,
        ApiPath__c,
        ApiVersionHeaderName__c,
        ApiVersionHeaderValue__c,
        MaximumOutputTokens__c,
        Temperature__c,
        RetryAttempts__c
      FROM AIModelConfiguration__c
      WHERE Id = :modelConfigurationId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    return configurations.isEmpty() ? null : configurations[0];
  }

  // No active template is a valid state: the agent simply runs without a system prompt. With more than one active, the most recently edited wins, so the answer is stable.
  public static AIPromptTemplate__c getActivePromptTemplate(Id agentId) {
    if (agentId == null)
      return null;

    List<AIPromptTemplate__c> templates = [
      SELECT
        Id,
        DeveloperName__c,
        AISystemContext__c,
        AIPrompt__c,
        AITone__c,
        AIExclusionRules__c,
        MaxResponseLength__c,
        Version__c
      FROM AIPromptTemplate__c
      WHERE AIAgent__c = :agentId AND IsActive__c = TRUE
      WITH SYSTEM_MODE
      ORDER BY LastModifiedDate DESC
      LIMIT 1
    ];

    return templates.isEmpty() ? null : templates[0];
  }

  // One query through the junction, capped, so an agent with hundreds of links cannot bloat every request.
  public static List<AIDataSource__c> getAssignedDataSources(Id agentId) {
    if (agentId == null)
      return new List<AIDataSource__c>();

    return [
      SELECT
        Id,
        DeveloperName__c,
        Description__c,
        OutputDescription__c,
        InputSchema__c,
        MaxRows__c,
        TargetObject__c
      FROM AIDataSource__c
      WHERE
        IsActive__c = TRUE
        AND Id IN (
          SELECT AIDataSource__c
          FROM AIAgentDataSource__c
          WHERE AIAgent__c = :agentId AND IsActive__c = TRUE
        )
      WITH SYSTEM_MODE
      ORDER BY DeveloperName__c
      LIMIT :AIAssistApplicationConstants.MAX_TOOLS_PER_KIND
    ];
  }

  // The rules assigned to an agent through an active AI Agent Violation Rule. A rule that applies to every agent needs no assignment and is matched by its own flag.
  private static Set<Id> getAssignedRuleIds(Id agentId) {
    Set<Id> ruleIds = new Set<Id>();

    for (AIAgentViolationRule__c assignment : [
      SELECT AIViolationRule__c
      FROM AIAgentViolationRule__c
      WHERE AIAgent__c = :agentId AND IsActive__c = TRUE
      WITH SYSTEM_MODE
      LIMIT 2000
    ])
      ruleIds.add(assignment.AIViolationRule__c);

    return ruleIds;
  }

  // The active AI evaluated rules of an agent, capped so their instructions cannot bloat every request.
  public static List<AIViolationRule__c> getActiveAiEvaluatedRules(Id agentId) {
    if (agentId == null)
      return new List<AIViolationRule__c>();

    Set<Id> assignedRuleIds = getAssignedRuleIds(agentId);

    return [
      SELECT
        Id,
        Name,
        SignalTag__c,
        AIDetectionInstruction__c,
        BlockRequest__c,
        ViolationTypeProduced__c
      FROM AIViolationRule__c
      WHERE
        (AppliesToAllAgents__c = TRUE
        OR Id IN :assignedRuleIds)
        AND IsActive__c = TRUE
        AND DetectionMethod__c = :AIAssistApplicationConstants.DETECTION_METHOD_AI_EVALUATED
        AND SignalTag__c != NULL
      WITH SYSTEM_MODE
      ORDER BY Name
      LIMIT :AIAssistApplicationConstants.MAX_AI_RULES_PER_AGENT
    ];
  }

  // The active deterministic rules of an agent that produce one violation type.
  public static List<AIViolationRule__c> getActiveRulesForViolationType(
    Id agentId,
    String violationType
  ) {
    if (agentId == null || violationType == null)
      return new List<AIViolationRule__c>();

    Set<Id> assignedRuleIds = getAssignedRuleIds(agentId);

    return [
      SELECT Id, Name, BlockRequest__c, ViolationTypeProduced__c
      FROM AIViolationRule__c
      WHERE
        (AppliesToAllAgents__c = TRUE
        OR Id IN :assignedRuleIds)
        AND IsActive__c = TRUE
        AND DetectionMethod__c = :AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC
        AND ViolationTypeProduced__c = :violationType
      WITH SYSTEM_MODE
      ORDER BY Name
      LIMIT :AIAssistApplicationConstants.MAX_AI_RULES_PER_AGENT
    ];
  }

  // One action the agent may offer: active, and linked to the agent through an active assignment. Null when it is neither.
  public static AIWorkflowAction__c getAssignedAction(Id actionId, Id agentId) {
    if (actionId == null || agentId == null)
      return null;

    List<AIWorkflowAction__c> actions = [
      SELECT
        Id,
        DeveloperName__c,
        ActionName__c,
        ActionType__c,
        ExecutionType__c,
        ApexClassName__c,
        FlowAPIName__c,
        TargetObject__c,
        RequiresConfirmation__c
      FROM AIWorkflowAction__c
      WHERE
        Id = :actionId
        AND IsActive__c = TRUE
        AND Id IN (
          SELECT AIWorkflowAction__c
          FROM AIAgentWorkflowAction__c
          WHERE AIAgent__c = :agentId AND IsActive__c = TRUE
        )
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    return actions.isEmpty() ? null : actions[0];
  }

  public static List<AIWorkflowAction__c> getAssignedActions(Id agentId) {
    if (agentId == null)
      return new List<AIWorkflowAction__c>();

    return [
      SELECT
        Id,
        DeveloperName__c,
        Description__c,
        OutputDescription__c,
        InputSchema__c
      FROM AIWorkflowAction__c
      WHERE
        IsActive__c = TRUE
        AND Id IN (
          SELECT AIWorkflowAction__c
          FROM AIAgentWorkflowAction__c
          WHERE AIAgent__c = :agentId AND IsActive__c = TRUE
        )
      WITH SYSTEM_MODE
      ORDER BY DeveloperName__c
      LIMIT :AIAssistApplicationConstants.MAX_TOOLS_PER_KIND
    ];
  }

  // =============================================================
  // Who may chat
  // =============================================================

  // What this user is allowed: their own settings row as an override, over the usage policies that apply to them (see AIUsagePolicyResolver). Null when they have neither, which callers treat as "no personal limits".
  public static AIUserSettings__c getUserSettings(Id userId) {
    if (userId == null)
      return null;

    List<AIUserSettings__c> userSettingsRows = [
      SELECT
        Id,
        User__c,
        IsActive__c,
        AllowedChannels__c,
        MaxConcurrentConversations__c,
        MaxConversationsPer24Hours__c,
        MaxTokensPer24Hours__c,
        UsageLimitReachedBehavior__c,
        DebugModeEnabled__c,
        WorkflowActionsEnabled__c,
        ConversationExportEnabled__c,
        ConversationVisibilityScope__c
      FROM AIUserSettings__c
      WHERE User__c = :userId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    return AIUsagePolicyResolver.resolve(
      userSettingsRows.isEmpty() ? null : userSettingsRows[0],
      getUsagePoliciesForUser(userId)
    );
  }

  // The active policies that apply to a user: those assigned to them or to a permission set they hold, or, when there are none, the default policies.
  public static List<AIUsagePolicy__c> getUsagePoliciesForUser(Id userId) {
    if (userId == null)
      return new List<AIUsagePolicy__c>();

    Set<String> heldPermissionSets = new Set<String>();
    for (PermissionSetAssignment heldAssignment : [
      SELECT PermissionSet.Name
      FROM PermissionSetAssignment
      WHERE AssigneeId = :userId
      WITH SYSTEM_MODE
    ])
      heldPermissionSets.add(heldAssignment.PermissionSet.Name);

    Set<Id> policyIds = new Set<Id>();
    for (AIUsagePolicyAssignment__c assignment : [
      SELECT AIUsagePolicy__c
      FROM AIUsagePolicyAssignment__c
      WHERE
        IsActive__c = TRUE
        AND AIUsagePolicy__r.IsActive__c = TRUE
        AND ((AssigneeType__c = :AIAssistApplicationConstants.ASSIGNEE_TYPE_USER
        AND User__c = :userId)
        OR (AssigneeType__c = :AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET
        AND PermissionSetName__c IN :heldPermissionSets))
      WITH SYSTEM_MODE
      LIMIT 200
    ])
      policyIds.add(assignment.AIUsagePolicy__c);

    // Nothing assigned: the default policies cover the user instead.
    if (policyIds.isEmpty()) {
      return [
        SELECT
          Id,
          AllowedChannels__c,
          ConversationExportEnabled__c,
          ConversationVisibilityScope__c,
          DebugModeEnabled__c,
          MaxConcurrentConversations__c,
          MaxConversationsPer24Hours__c,
          MaxTokensPer24Hours__c,
          UsageLimitReachedBehavior__c,
          WorkflowActionsEnabled__c
        FROM AIUsagePolicy__c
        WHERE IsActive__c = TRUE AND IsDefault__c = TRUE
        WITH SYSTEM_MODE
        LIMIT 200
      ];
    }

    return [
      SELECT
        Id,
        AllowedChannels__c,
        ConversationExportEnabled__c,
        ConversationVisibilityScope__c,
        DebugModeEnabled__c,
        MaxConcurrentConversations__c,
        MaxConversationsPer24Hours__c,
        MaxTokensPer24Hours__c,
        UsageLimitReachedBehavior__c,
        WorkflowActionsEnabled__c
      FROM AIUsagePolicy__c
      WHERE IsActive__c = TRUE AND Id IN :policyIds
      WITH SYSTEM_MODE
      LIMIT 200
    ];
  }

  // True when an active assignment names the user, or names a permission set (or permission set group) the user holds.
  public static Boolean isUserAssignedToAgent(Id agentId, Id userId) {
    if (agentId == null || userId == null)
      return false;

    Integer directAssignments = [
      SELECT COUNT()
      FROM AIAgentAssignment__c
      WHERE
        AIAgent__c = :agentId
        AND IsActive__c = TRUE
        AND AssigneeType__c = :AIAssistApplicationConstants.ASSIGNEE_TYPE_USER
        AND User__c = :userId
      WITH SYSTEM_MODE
    ];

    if (directAssignments > 0)
      return true;

    Set<String> permissionSetNames = new Set<String>();

    for (AIAgentAssignment__c assignment : [
      SELECT PermissionSetName__c
      FROM AIAgentAssignment__c
      WHERE
        AIAgent__c = :agentId
        AND IsActive__c = TRUE
        AND AssigneeType__c = :AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET
      WITH SYSTEM_MODE
      LIMIT 200
    ]) {
      if (String.isNotBlank(assignment.PermissionSetName__c))
        permissionSetNames.add(assignment.PermissionSetName__c);
    }

    if (permissionSetNames.isEmpty())
      return false;

    return [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE AssigneeId = :userId AND PermissionSet.Name IN :permissionSetNames
        WITH SYSTEM_MODE
      ] > 0;
  }

  // Which of the agents are open to this user through an active assignment, by name or by a permission set they hold. One pass for many agents.
  public static Set<Id> getAgentIdsAssignedToUser(Id userId, Set<Id> agentIds) {
    Set<Id> assignedIds = new Set<Id>();

    if (userId == null || agentIds == null || agentIds.isEmpty())
      return assignedIds;

    Set<String> heldPermissionSets = new Set<String>();
    for (PermissionSetAssignment heldAssignment : [
      SELECT PermissionSet.Name
      FROM PermissionSetAssignment
      WHERE AssigneeId = :userId
      WITH SYSTEM_MODE
    ])
      heldPermissionSets.add(heldAssignment.PermissionSet.Name);

    for (AIAgentAssignment__c assignment : [
      SELECT AIAgent__c
      FROM AIAgentAssignment__c
      WHERE
        AIAgent__c IN :agentIds
        AND IsActive__c = TRUE
        AND ((AssigneeType__c = :AIAssistApplicationConstants.ASSIGNEE_TYPE_USER
        AND User__c = :userId)
        OR (AssigneeType__c = :AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET
        AND PermissionSetName__c IN :heldPermissionSets))
      WITH SYSTEM_MODE
    ]) {
      assignedIds.add(assignment.AIAgent__c);
    }

    return assignedIds;
  }

  // The objects each active agent has been added to through AI Agent Object records, by agent. Agents with none are not in the map.
  private static Map<Id, Set<String>> getExtraObjectsByAgent() {
    Map<Id, Set<String>> objectsByAgent = new Map<Id, Set<String>>();

    for (AIAgentObject__c agentObject : [
      SELECT AIAgent__c, ObjectApiName__c
      FROM AIAgentObject__c
      WHERE IsActive__c = TRUE AND AIAgent__r.IsActive__c = TRUE
      WITH SYSTEM_MODE
      LIMIT 5000
    ]) {
      if (!objectsByAgent.containsKey(agentObject.AIAgent__c))
        objectsByAgent.put(agentObject.AIAgent__c, new Set<String>());
      objectsByAgent.get(agentObject.AIAgent__c)
        .add(agentObject.ObjectApiName__c.toLowerCase());
    }

    return objectsByAgent;
  }

  // True when the agent is offered on the object: its own Object Type, any object added to it, or, for an agent with neither, every object.
  public static Boolean agentSupportsObject(
    Id agentId,
    String agentObjectType,
    String objectApiName,
    String objectLocalName
  ) {
    Set<String> extraObjects = new Set<String>();

    if (agentId != null) {
      for (AIAgentObject__c agentObject : [
        SELECT ObjectApiName__c
        FROM AIAgentObject__c
        WHERE AIAgent__c = :agentId AND IsActive__c = TRUE
        WITH SYSTEM_MODE
        LIMIT 200
      ])
        extraObjects.add(agentObject.ObjectApiName__c.toLowerCase());
    }

    if (String.isBlank(agentObjectType) && extraObjects.isEmpty())
      return true;

    return matchesObject(agentObjectType, objectApiName, objectLocalName) ||
      extraObjects.contains(String.valueOf(objectApiName).toLowerCase()) ||
      extraObjects.contains(String.valueOf(objectLocalName).toLowerCase());
  }

  private static Boolean matchesObject(
    String configuredObject,
    String objectApiName,
    String objectLocalName
  ) {
    return String.isNotBlank(configuredObject) &&
      (configuredObject.equalsIgnoreCase(objectApiName) ||
      configuredObject.equalsIgnoreCase(objectLocalName));
  }

  // The active agents this user can chat with for an object, agents for the object first. An agent is for the object through its Object Type or an AI Agent Object record; one with neither is general and comes last. An Assigned Users Only agent is included only when the user is assigned.
  public static List<AIAgent__c> getAgentsAvailableForChat(
    String objectApiName,
    Id userId
  ) {
    Map<Id, Set<String>> extraObjectsByAgent = getExtraObjectsByAgent();
    Set<Id> agentsAddedToObject = new Set<Id>();
    for (Id extraAgentId : extraObjectsByAgent.keySet()) {
      if (
        objectApiName != null &&
        extraObjectsByAgent.get(extraAgentId)
          .contains(objectApiName.toLowerCase())
      )
        agentsAddedToObject.add(extraAgentId);
    }

    List<AIAgent__c> candidates = [
      SELECT
        Id,
        Name,
        DeveloperName__c,
        Description__c,
        GreetingMessage__c,
        ObjectType__c,
        ConversationLoadTrigger__c,
        AllowConversationResume__c,
        AccessMode__c
      FROM AIAgent__c
      WHERE
        IsActive__c = TRUE
        AND (ObjectType__c = NULL
        OR ObjectType__c = :objectApiName
        OR Id IN :agentsAddedToObject)
      WITH SYSTEM_MODE
      ORDER BY Name
      LIMIT :AIAssistApplicationConstants.CHAT_MAX_AGENTS
    ];

    Set<Id> restrictedIds = new Set<Id>();
    for (AIAgent__c candidate : candidates) {
      if (
        candidate.AccessMode__c ==
        AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY
      )
        restrictedIds.add(candidate.Id);
    }

    Set<Id> assignedIds = getAgentIdsAssignedToUser(userId, restrictedIds);
    List<AIAgent__c> agentsForObject = new List<AIAgent__c>();
    List<AIAgent__c> generalAgents = new List<AIAgent__c>();

    for (AIAgent__c candidate : candidates) {
      if (
        restrictedIds.contains(candidate.Id) &&
        !assignedIds.contains(candidate.Id)
      )
        continue;

      Boolean isForObject =
        agentsAddedToObject.contains(candidate.Id) ||
        (String.isNotBlank(candidate.ObjectType__c) &&
        candidate.ObjectType__c.equalsIgnoreCase(objectApiName));

      if (isForObject)
        agentsForObject.add(candidate);
      else if (
        String.isBlank(candidate.ObjectType__c) &&
        !extraObjectsByAgent.containsKey(candidate.Id)
      )
        generalAgents.add(candidate); // Added to other objects only: not general.
    }

    agentsForObject.addAll(generalAgents);
    return agentsForObject;
  }

  // Admin, Super User or User, by the highest AI Assist permission set the user holds. Decides which slash commands they see.
  public static String getHighestPermissionLevel(Id userId) {
    Set<String> heldPermissionSetNames = new Set<String>();

    for (PermissionSetAssignment assignment : [
      SELECT PermissionSet.Name
      FROM PermissionSetAssignment
      WHERE
        AssigneeId = :userId
        AND PermissionSet.Name IN :new List<String>{
          AIAssistApplicationConstants.PERMISSION_SET_ADMIN_USER,
          AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER
        }
      WITH SYSTEM_MODE
    ]) {
      heldPermissionSetNames.add(assignment.PermissionSet.Name);
    }

    return heldPermissionSetNames.contains(
        AIAssistApplicationConstants.PERMISSION_SET_ADMIN_USER
      )
      ? AIAssistApplicationConstants.USER_LEVEL_ADMIN
      : heldPermissionSetNames.contains(
            AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER
          )
          ? AIAssistApplicationConstants.USER_LEVEL_SUPER_USER
          : AIAssistApplicationConstants.USER_LEVEL_USER;
  }

  // ACCEPTED when the user signed the current version, OUTDATED when they signed an earlier one, NONE when they never signed.
  public static String getTermsAcceptanceStatus(
    Id userId,
    String currentTermsVersion
  ) {
    if (String.isBlank(currentTermsVersion))
      return TERMS_ACCEPTED; // No terms configured, so nothing to accept.

    if (
      [
        SELECT COUNT()
        FROM AITermsAcknowledgment__c
        WHERE User__c = :userId AND TermsVersion__c = :currentTermsVersion
        WITH SYSTEM_MODE
        LIMIT 1
      ] > 0
    )
      return TERMS_ACCEPTED;

    return [
        SELECT COUNT()
        FROM AITermsAcknowledgment__c
        WHERE User__c = :userId
        WITH SYSTEM_MODE
        LIMIT 1
      ] > 0
      ? TERMS_OUTDATED
      : TERMS_NONE;
  }

  public static Integer countActiveConversations(Id userId) {
    return [
      SELECT COUNT()
      FROM AIConversation__c
      WHERE
        OwnerId = :userId
        AND Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE
      WITH SYSTEM_MODE
    ];
  }

  // =============================================================
  // Usage
  // =============================================================

  public static UsageTotals getUserDailyUsage(Id userId, Date usageDate) {
    UsageTotals totals = new UsageTotals();

    List<AggregateResult> usageRows = [
      SELECT
        SUM(ConversationCount__c) conversations,
        SUM(InputTokens__c) inputTokens,
        SUM(OutputTokens__c) outputTokens
      FROM AIUsageDaily__c
      WHERE User__c = :userId AND UsageDate__c = :usageDate
      WITH SYSTEM_MODE
    ];

    if (usageRows.isEmpty())
      return totals;

    totals.conversations = usageRows[0].get('conversations') == null
      ? 0
      : (Decimal) usageRows[0].get('conversations');
    totals.tokens =
      (usageRows[0].get('inputTokens') == null
        ? 0
        : (Decimal) usageRows[0].get('inputTokens')) +
      (usageRows[0].get('outputTokens') == null
        ? 0
        : (Decimal) usageRows[0].get('outputTokens'));

    return totals;
  }

  // One grouped query (at most 31 rows) gives the month and the day. CreatedDate is the indexed filter that keeps it selective as the table grows: a row is created on the first use of its day, so a month's rows are always created inside that month.
  public static OrgUsage getOrganisationUsage(Date today) {
    OrgUsage orgUsage = new OrgUsage();

    Date monthStart = Date.newInstance(today.year(), today.month(), 1);
    Datetime monthStartDatetime = Datetime.newInstanceGmt(
      monthStart.year(),
      monthStart.month(),
      monthStart.day()
    );

    for (AggregateResult dailyRow : [
      SELECT
        UsageDate__c usageDate,
        SUM(MessageCount__c) messages,
        SUM(InputTokens__c) inputTokens,
        SUM(OutputTokens__c) outputTokens
      FROM AIUsageDaily__c
      WHERE CreatedDate >= :monthStartDatetime AND UsageDate__c >= :monthStart
      WITH SYSTEM_MODE
      GROUP BY UsageDate__c
    ]) {
      Decimal rowMessages = dailyRow.get('messages') == null
        ? 0
        : (Decimal) dailyRow.get('messages');
      Decimal rowTokens =
        (dailyRow.get('inputTokens') == null
          ? 0
          : (Decimal) dailyRow.get('inputTokens')) +
        (dailyRow.get('outputTokens') == null
          ? 0
          : (Decimal) dailyRow.get('outputTokens'));

      orgUsage.month.messages += rowMessages;
      orgUsage.month.tokens += rowTokens;

      if ((Date) dailyRow.get('usageDate') == today) {
        orgUsage.today.messages += rowMessages;
        orgUsage.today.tokens += rowTokens;
      }
    }

    return orgUsage;
  }

  // The user's usage row for one key, locked so the caller can add to it. Null if there is no row yet.
  public static AIUsageDaily__c lockDailyUsageRow(String usageKey) {
    List<AIUsageDaily__c> usageDailyRows = [
      SELECT
        Id,
        MessageCount__c,
        ConversationCount__c,
        FailedTurnCount__c,
        ViolationCount__c,
        InputTokens__c,
        OutputTokens__c
      FROM AIUsageDaily__c
      WHERE UsageKey__c = :usageKey
      WITH SYSTEM_MODE
      LIMIT 1
      FOR UPDATE
    ];

    return usageDailyRows.isEmpty() ? null : usageDailyRows[0];
  }

  // Turns queued or running in this org right now. The asynchronous queue is shared with the subscriber, so the messaging layer refuses new work before it can crowd theirs out. Bounded to the last day because a job older than that is not pending.
  public static Integer countQueuedMessageJobs() {
    Datetime oneDayAgo = Datetime.now().addDays(-1);

    return [
      SELECT COUNT()
      FROM AsyncApexJob
      WHERE
        ApexClass.Name = 'AIMessageProcessingQueueable'
        AND JobType = 'Queueable'
        AND Status IN ('Queued', 'Preparing', 'Processing')
        AND CreatedDate >= :oneDayAgo
      WITH SYSTEM_MODE
    ];
  }

  // =============================================================
  // Trigger support
  // =============================================================

  public static Map<Id, AIAgent__c> getAgentRetentionSettings(
    Set<Id> agentIds
  ) {
    if (agentIds == null || agentIds.isEmpty())
      return new Map<Id, AIAgent__c>();

    return new Map<Id, AIAgent__c>(
      [
        SELECT Id, ConversationRetentionDays__c, RetentionTrigger__c
        FROM AIAgent__c
        WHERE Id IN :agentIds
        WITH SYSTEM_MODE
      ]
    );
  }

  // The conversations a batch of messages belongs to, locked while their totals change, so two transactions inserting into one conversation add to each other instead of overwriting.
  public static List<AIConversation__c> lockConversationsForRollup(
    Set<Id> conversationIds
  ) {
    if (conversationIds == null || conversationIds.isEmpty())
      return new List<AIConversation__c>();

    return [
      SELECT
        Id,
        ConversationTokenUsage__c,
        LastMessageTimestamp__c,
        RetentionExpiryDate__c,
        AIAgent__c
      FROM AIConversation__c
      WHERE Id IN :conversationIds
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
  }
}
