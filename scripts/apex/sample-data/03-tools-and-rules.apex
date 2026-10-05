/*
Script Name: 03-tools-and-rules.apex

=================================================================
=================================================================

Description: Data sources, workflow actions and violation rules, each linked to the sample agents, and PII
registries with the fields found in them. Run 02-agents.apex first.

Skipped when a data source named "Sample - ..." already exists.

Workflow actions and the Apex data source are created only when the options name a class or Flow
that exists in the org: the package refuses one that does not. Anything the plan does not include
(active workflow actions, an active Apex data source, active AI evaluated rules) is saved inactive.

Part of the sample data set: run scripts/load-sample-data.sh <org alias> to load all five parts in
order, or this part alone with sf apex run --file.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public class SampleDataLoader {
  // =============================================================
  // Options
  // =============================================================

  Boolean isProductionAllowed = false; // The script refuses to run outside a sandbox or scratch org unless this is set.
  String workflowActionApexClass = ''; // A class in this org that implements IAIWorkflowActionExecutor.
  String workflowActionFlowName = ''; // An active autolaunched Flow in this org that the package may run.
  String dataSourceApexClass = ''; // A class in this org that implements IAIDataSourceExecutor.

  // =============================================================

  final String PREFIX = 'Sample - ';
  List<String> summary = new List<String>();
  List<String> problems = new List<String>();
  Id runningUserId = UserInfo.getUserId();

  public void run() {
    if (
      !isProductionAllowed &&
      ![SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox
    )
      problems.add('Not a sandbox or scratch org. Nothing was loaded.');
    else
      load();

    System.debug(
      LoggingLevel.ERROR,
      'SAMPLE DATA: 03-tools-and-rules.apex\n  ' +
        String.join(summary, '\n  ') +
        (problems.isEmpty()
          ? '\nNo problems.'
          : '\nPROBLEMS (' +
            problems.size() +
            ')\n  ' +
            String.join(problems, '\n  '))
    );
  }

  void load() {
    if (
      [SELECT COUNT() FROM AIDataSource__c WHERE SourceName__c LIKE 'Sample - %'] >
      0
    ) {
      summary.add('Skipped: the sample data sources already exist');
      return;
    }

    // ---------- The agents made by 02-agents.apex, in the order it made them. One that is missing has no Id and gets nothing.
    Map<String, AIAgent__c> agentByName = new Map<String, AIAgent__c>();
    for (AIAgent__c agent : [
      SELECT Id, Name
      FROM AIAgent__c
      WHERE Name LIKE 'Sample - %'
    ])
      agentByName.put(agent.Name, agent);
    List<AIAgent__c> agents = new List<AIAgent__c>();
    List<AIAgent__c> chatAgents = new List<AIAgent__c>();
    for (
      String agentName : new List<String>{
        'Sales Assistant',
        'Service Assistant',
        'Policy Helper',
        'Draft Agent'
      }
    ) {
      AIAgent__c agent = agentByName.get(PREFIX + agentName);
      agents.add(agent == null ? new AIAgent__c() : agent);
      if (agent != null && agentName != 'Draft Agent')
        chatAgents.add(agent);
    }
    if (agentByName.isEmpty())
      problems.add('No sample agents: run 02-agents.apex first.');

    // ---------- Data sources.
    List<AIDataSource__c> dataSources = new List<AIDataSource__c>{
      new AIDataSource__c(
        SourceName__c = PREFIX + 'Account Overview',
        Description__c = 'The account the user is looking at.',
        SourceType__c = 'SOQL',
        BindingType__c = 'Bound',
        TargetObject__c = 'Account',
        SOQLTemplate__c = 'SELECT Id, Name, Industry, Type, AnnualRevenue, Phone, Website FROM Account WHERE Id = :recordId',
        OutputDescription__c = 'One account with its headline fields.',
        MaxRows__c = 1,
        IsActive__c = true
      ),
      new AIDataSource__c(
        SourceName__c = PREFIX + 'Account Contacts',
        Description__c = 'The contacts of the account the user is looking at.',
        SourceType__c = 'SOQL',
        BindingType__c = 'Bound',
        TargetObject__c = 'Account',
        SOQLTemplate__c = 'SELECT Id, Name, Title, Email, Phone FROM Contact WHERE AccountId = :recordId ORDER BY LastModifiedDate DESC',
        OutputDescription__c = 'Contacts, most recently changed first.',
        MaxRows__c = 25,
        IsActive__c = true
      ),
      new AIDataSource__c(
        SourceName__c = PREFIX + 'Open Opportunities',
        Description__c = 'Open opportunities of the account the user is looking at.',
        SourceType__c = 'SOQL',
        BindingType__c = 'Bound',
        TargetObject__c = 'Account',
        SOQLTemplate__c = 'SELECT Id, Name, StageName, Amount, CloseDate, NextStep FROM Opportunity WHERE AccountId = :recordId AND IsClosed = FALSE ORDER BY CloseDate',
        OutputDescription__c = 'Open opportunities, soonest close date first.',
        MaxRows__c = 20,
        IsActive__c = true
      ),
      new AIDataSource__c(
        SourceName__c = PREFIX + 'Open Cases',
        Description__c = 'Open cases of the account the user is looking at.',
        SourceType__c = 'SOQL',
        BindingType__c = 'Bound',
        TargetObject__c = 'Account',
        SOQLTemplate__c = 'SELECT Id, CaseNumber, Subject, Status, Priority, CreatedDate FROM Case WHERE AccountId = :recordId AND IsClosed = FALSE ORDER BY CreatedDate',
        OutputDescription__c = 'Open cases, oldest first.',
        MaxRows__c = 20,
        IsActive__c = true
      ),
      new AIDataSource__c(
        SourceName__c = PREFIX + 'Find Accounts By Name',
        Description__c = 'Searches accounts by name. Not tied to a record.',
        SourceType__c = 'SOQL',
        BindingType__c = 'Unbound',
        SOQLTemplate__c = 'SELECT Id, Name, Industry, BillingCity FROM Account WHERE Name LIKE :searchTerm ORDER BY Name',
        InputSchema__c = '{"type":"object","properties":{"searchTerm":{"type":"string","description":"The account name to look for. Use % as a wildcard."}},"required":["searchTerm"]}',
        OutputDescription__c = 'Matching accounts.',
        MaxRows__c = 10,
        IsActive__c = true
      ),
      new AIDataSource__c(
        SourceName__c = PREFIX + 'Open Tasks',
        Description__c = 'Open tasks the user can see.',
        SourceType__c = 'SOQL',
        BindingType__c = 'Unbound',
        SOQLTemplate__c = 'SELECT Id, Subject, ActivityDate, Status, Priority FROM Task WHERE IsClosed = FALSE ORDER BY ActivityDate',
        OutputDescription__c = 'Open tasks, soonest due first.',
        MaxRows__c = 20,
        IsActive__c = true
      ),
      new AIDataSource__c(
        SourceName__c = PREFIX + 'Closed Won History',
        Description__c = 'Not released yet: switched off.',
        SourceType__c = 'SOQL',
        BindingType__c = 'Bound',
        TargetObject__c = 'Account',
        SOQLTemplate__c = 'SELECT Id, Name, Amount, CloseDate FROM Opportunity WHERE AccountId = :recordId AND IsWon = TRUE ORDER BY CloseDate DESC',
        MaxRows__c = 50
      )
    };
    if (String.isNotBlank(dataSourceApexClass))
      dataSources.add(
        new AIDataSource__c(
          SourceName__c = PREFIX + 'Apex Source',
          Description__c = 'Rows built by an Apex class.',
          SourceType__c = 'Apex',
          BindingType__c = 'Bound',
          ApexClassName__c = dataSourceApexClass,
          OutputDescription__c = 'Whatever the class returns.',
          MaxRows__c = 20,
          IsActive__c = AIFeatureService.isFeatureEnabled('Apex')
        )
      );
    else
      summary.add(
        'Apex data source: skipped, the dataSourceApexClass option is blank'
      );
    save('AIDataSource__c', dataSources, false);

    // Sales gets the account sources, Service gets contacts, cases and tasks, Policy Helper gets the search.
    Map<Integer, List<Integer>> sourceIndexesByAgent = new Map<Integer, List<Integer>>{
      0 => new List<Integer>{ 0, 1, 2, 4, 6 },
      1 => new List<Integer>{ 0, 1, 3, 5 },
      2 => new List<Integer>{ 4 }
    };
    if (dataSources.size() > 7)
      sourceIndexesByAgent.get(0).add(7);
    List<AIAgentDataSource__c> agentDataSources = new List<AIAgentDataSource__c>();
    Map<Id, Id> dataSourceIdByAgentId = new Map<Id, Id>();
    for (Integer agentIndex : sourceIndexesByAgent.keySet()) {
      for (Integer sourceIndex : sourceIndexesByAgent.get(agentIndex)) {
        if (
          agents[agentIndex].Id == null ||
          dataSources[sourceIndex].Id == null
        )
          continue;
        agentDataSources.add(
          new AIAgentDataSource__c(
            AIAgent__c = agents[agentIndex].Id,
            AIDataSource__c = dataSources[sourceIndex].Id,
            IsActive__c = dataSources[sourceIndex].IsActive__c
          )
        );
        if (!dataSourceIdByAgentId.containsKey(agents[agentIndex].Id))
          dataSourceIdByAgentId.put(
            agents[agentIndex].Id,
            dataSources[sourceIndex].Id
          );
      }
    }
    save('AIAgentDataSource__c', agentDataSources, false);

    // ---------- Workflow actions: only for a class or Flow that exists in this org.
    Boolean isActionActive = AIFeatureService.isFeatureEnabled(
      'WorkflowActions'
    );
    List<AIWorkflowAction__c> actions = new List<AIWorkflowAction__c>();
    if (String.isNotBlank(workflowActionApexClass)) {
      actions.add(
        new AIWorkflowAction__c(
          ActionName__c = PREFIX + 'Create Follow-up Task',
          Description__c = 'Creates a follow-up task on the record.',
          ActionType__c = 'Apex',
          ApexClassName__c = workflowActionApexClass,
          ExecutionType__c = 'Write',
          RequiresConfirmation__c = true,
          ConfirmationMessage__c = 'Create this follow-up task?',
          TargetObject__c = 'Task',
          InputSchema__c = '{"type":"object","properties":{"subject":{"type":"string","description":"What the task is about."},"dueDate":{"type":"string","description":"Due date, as YYYY-MM-DD."}},"required":["subject"]}',
          OutputDescription__c = 'A sentence saying what was created.',
          IsActive__c = isActionActive
        )
      );
      actions.add(
        new AIWorkflowAction__c(
          ActionName__c = PREFIX + 'Check Record Health',
          Description__c = 'Reads the record and reports what is missing.',
          ActionType__c = 'Apex',
          ApexClassName__c = workflowActionApexClass,
          ExecutionType__c = 'Read Only',
          RequiresConfirmation__c = false,
          OutputDescription__c = 'A short list of gaps.',
          IsActive__c = isActionActive
        )
      );
    }
    if (String.isNotBlank(workflowActionFlowName))
      actions.add(
        new AIWorkflowAction__c(
          ActionName__c = PREFIX + 'Escalate To Manager',
          Description__c = 'Runs a Flow that escalates the record.',
          ActionType__c = 'Flow',
          FlowAPIName__c = workflowActionFlowName,
          ExecutionType__c = 'Write',
          RequiresConfirmation__c = true,
          ConfirmationMessage__c = 'Escalate this record to your manager?',
          OutputDescription__c = 'A sentence saying who was told.',
          IsActive__c = isActionActive
        )
      );
    if (actions.isEmpty())
      summary.add(
        'AIWorkflowAction__c, AIAgentWorkflowAction__c: skipped, the workflowActionApexClass and workflowActionFlowName options are blank'
      );
    save('AIWorkflowAction__c', actions, false);

    List<AIAgentWorkflowAction__c> agentActions = new List<AIAgentWorkflowAction__c>();
    Id firstActionId = null;
    for (AIWorkflowAction__c action : actions) {
      if (action.Id == null)
        continue;
      if (firstActionId == null)
        firstActionId = action.Id;
      for (AIAgent__c agent : chatAgents)
        agentActions.add(
          new AIAgentWorkflowAction__c(
            AIAgent__c = agent.Id,
            AIWorkflowAction__c = action.Id,
            IsActive__c = action.IsActive__c
          )
        );
    }
    save('AIAgentWorkflowAction__c', agentActions, false);

    // ---------- Violation rules. AI evaluated rules are active only when the plan includes them.
    Boolean isAiRuleActive = AIFeatureService.isFeatureEnabled(
      'AIEvaluatedRules'
    );
    List<AIViolationRule__c> rules = new List<AIViolationRule__c>{
      new AIViolationRule__c(
        Name = PREFIX + 'Unauthorised Data Access',
        RuleName__c = 'Unauthorised data access',
        DetectionMethod__c = 'DeterministicApex',
        ViolationTypeProduced__c = 'UnauthorizedDataAccess',
        AppliesToAllAgents__c = true,
        BlockRequest__c = true
      ),
      new AIViolationRule__c(
        Name = PREFIX + 'Unauthorised Workflow Action',
        RuleName__c = 'Unauthorised workflow action',
        DetectionMethod__c = 'DeterministicApex',
        ViolationTypeProduced__c = 'UnauthorizedWorkflowAction',
        AppliesToAllAgents__c = true,
        BlockRequest__c = true
      ),
      new AIViolationRule__c(
        Name = PREFIX + 'Usage Limit Exceeded',
        RuleName__c = 'Usage limit exceeded',
        DetectionMethod__c = 'DeterministicApex',
        ViolationTypeProduced__c = 'UsageLimitExceeded',
        AppliesToAllAgents__c = true
      ),
      new AIViolationRule__c(
        Name = PREFIX + 'PII Masking Failure',
        RuleName__c = 'PII masking failure',
        DetectionMethod__c = 'DeterministicApex',
        ViolationTypeProduced__c = 'PIIMaskingFailure',
        AppliesToAllAgents__c = true,
        BlockRequest__c = true
      ),
      new AIViolationRule__c(
        Name = PREFIX + 'Bulk Export Request',
        RuleName__c = 'Bulk export request',
        DetectionMethod__c = 'AIEvaluated',
        ViolationTypeProduced__c = 'AIFlaggedIntent',
        SignalTag__c = 'BULK_EXPORT',
        AIDetectionInstruction__c = 'The user asks for a bulk export, a full list or a download of customer records.',
        IsActive__c = isAiRuleActive
      ),
      new AIViolationRule__c(
        Name = PREFIX + 'Competitor Disparagement',
        RuleName__c = 'Competitor disparagement',
        DetectionMethod__c = 'AIEvaluated',
        ViolationTypeProduced__c = 'AIFlaggedIntent',
        SignalTag__c = 'COMPETITOR_TALK',
        AIDetectionInstruction__c = 'The user asks for wording that disparages a named competitor.',
        BlockRequest__c = true,
        IsActive__c = isAiRuleActive
      ),
      new AIViolationRule__c(
        Name = PREFIX + 'Retired Configuration Rule',
        RuleName__c = 'Retired configuration rule',
        DetectionMethod__c = 'DeterministicApex',
        ViolationTypeProduced__c = 'ConfigurationViolation',
        IsActive__c = false
      )
    };
    save('AIViolationRule__c', rules, false);

    List<AIAgentViolationRule__c> agentRules = new List<AIAgentViolationRule__c>();
    for (Integer ruleIndex = 4; ruleIndex < rules.size(); ruleIndex++) {
      if (rules[ruleIndex].Id == null)
        continue;
      for (AIAgent__c agent : chatAgents)
        agentRules.add(
          new AIAgentViolationRule__c(
            AIAgent__c = agent.Id,
            AIViolationRule__c = rules[ruleIndex].Id,
            IsActive__c = rules[ruleIndex].IsActive__c
          )
        );
    }
    save('AIAgentViolationRule__c', agentRules, false);

    // ---------- PII registries and the fields found in them.
    List<AIPIIRegistry__c> registries = new List<AIPIIRegistry__c>{
      new AIPIIRegistry__c(
        Name = PREFIX + 'Contact',
        ObjectAPIName__c = 'Contact',
        Description__c = 'Personal data held on contacts.',
        SyncStatus__c = 'Synced',
        LastSynced__c = Datetime.now(),
        MaxFieldsToQuery__c = 100
      ),
      new AIPIIRegistry__c(
        Name = PREFIX + 'Account',
        ObjectAPIName__c = 'Account',
        Description__c = 'Personal data held on accounts.',
        SyncStatus__c = 'Synced',
        LastSynced__c = Datetime.now(),
        MaxFieldsToQuery__c = 100
      ),
      new AIPIIRegistry__c(
        Name = PREFIX + 'Lead',
        ObjectAPIName__c = 'Lead',
        Description__c = 'Waiting for its first sync.',
        SyncStatus__c = 'Not Synced'
      ),
      new AIPIIRegistry__c(
        Name = PREFIX + 'Case',
        ObjectAPIName__c = 'Case',
        Description__c = 'Switched off.',
        SyncStatus__c = 'Failed',
        IsActive__c = false
      )
    };
    save('AIPIIRegistry__c', registries, false);

    // Object index, field, label, data type, PII field type (null = not PII), compliance group.
    List<List<String>> fieldRows = new List<List<String>>{
      new List<String>{ '0', 'FirstName', 'First Name', 'STRING', 'Name', 'PII' },
      new List<String>{ '0', 'LastName', 'Last Name', 'STRING', 'Name', 'PII' },
      new List<String>{ '0', 'Email', 'Email', 'EMAIL', 'Email', 'PII;GDPR' },
      new List<String>{ '0', 'Phone', 'Business Phone', 'PHONE', 'Phone', 'PII' },
      new List<String>{ '0', 'MobilePhone', 'Mobile Phone', 'PHONE', 'Phone', 'PII' },
      new List<String>{ '0', 'Birthdate', 'Birthdate', 'DATE', 'Date of Birth', 'PII;GDPR' },
      new List<String>{ '0', 'MailingStreet', 'Mailing Street', 'TEXTAREA', 'Address', 'PII' },
      new List<String>{ '0', 'Title', 'Title', 'STRING', null, null },
      new List<String>{ '0', 'Department', 'Department', 'STRING', null, null },
      new List<String>{ '1', 'Name', 'Account Name', 'STRING', null, null },
      new List<String>{ '1', 'Phone', 'Account Phone', 'PHONE', 'Phone', 'PII' },
      new List<String>{ '1', 'BillingStreet', 'Billing Street', 'TEXTAREA', 'Address', 'PII' },
      new List<String>{ '1', 'Industry', 'Industry', 'PICKLIST', null, null },
      new List<String>{ '1', 'AccountNumber', 'Account Number', 'STRING', 'Bank Account', 'PCI' }
    };
    List<AIPIIFieldMetadata__c> fieldMetadata = new List<AIPIIFieldMetadata__c>();
    for (List<String> fieldRow : fieldRows) {
      AIPIIRegistry__c registry = registries[Integer.valueOf(fieldRow[0])];
      if (registry.Id == null)
        continue;
      fieldMetadata.add(
        new AIPIIFieldMetadata__c(
          Name = registry.ObjectAPIName__c + '.' + fieldRow[1],
          PIIRegistry__c = registry.Id,
          FieldKey__c = registry.ObjectAPIName__c + '.' + fieldRow[1],
          FieldAPIName__c = fieldRow[1],
          FieldLabel__c = fieldRow[2],
          DataType__c = fieldRow[3],
          IsPII__c = fieldRow[4] != null,
          PIIFieldType__c = fieldRow[4],
          ComplianceGroup__c = fieldRow[5],
          LastSynced__c = Datetime.now()
        )
      );
    }
    save('AIPIIFieldMetadata__c', fieldMetadata, true);
  }

  // Inserts what it can and records the rest. asPackage writes in system mode, as the package does, for the objects and fields a user may not write (the assistant's messages, evidence, usage).
  void save(String label, List<SObject> records, Boolean asPackage) {
    if (records.isEmpty())
      return;

    if (asPackage) {
      try {
        AIMessagingDataService.insertAsPackage(records);
      } catch (Exception caughtException) {
        problems.add(label + ': ' + caughtException.getMessage());
      }
    } else {
      List<Database.SaveResult> saveResults = Database.insert(records, false);
      for (Integer rowIndex = 0; rowIndex < saveResults.size(); rowIndex++) {
        if (!saveResults[rowIndex].isSuccess())
          problems.add(
            label +
              ' [' +
              rowIndex +
              ']: ' +
              saveResults[rowIndex].getErrors()[0].getMessage()
          );
      }
    }

    Integer savedCount = 0;
    for (SObject record : records) {
      if (record.Id != null)
        savedCount++;
    }
    summary.add(label + ': ' + savedCount + ' of ' + records.size());
  }
}

new SampleDataLoader().run();
