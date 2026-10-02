/*
Class Name: AIAssistApplicationConstantsTest

=================================================================
=================================================================

Description: Testing utility for AIAssistApplicationConstants: every value the code compares against must still exist in the object model.

=================================================================
=================================================================
Applicable Classes:

AIAssistApplicationConstants

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAssistApplicationConstantsTest {
  // testScenario1: Every picklist constant exists as a value of the picklist it is named for, so a renamed or removed picklist value fails here rather than for a user.
  // testScenario2: Every user-allowed channel is a value of both the conversation channel and the user-settings allow-list, which share one global value set.
  // testScenario3: The error codes are non-blank and unique, so the UI can tell any two refusals apart, and the guard rails are positive and consistent with each other.

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
    Map<Schema.SObjectField, List<String>> constantsByPicklist = new Map<Schema.SObjectField, List<String>>{
      AIConversation__c.Status__c => new List<String>{
        AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
        AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED
      },
      AIConversation__c.ConversationCloseReason__c => new List<String>{
        AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_IDLE_TIMEOUT,
        AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED,
        AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_MESSAGE_LIMIT_REACHED,
        AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_TOKEN_LIMIT_REACHED,
        AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_SYSTEM_OVERRIDE
      },
      AIConversation__c.Channel__c => new List<String>{
        AIAssistApplicationConstants.CHANNEL_MOBILE,
        AIAssistApplicationConstants.CHANNEL_UTILITY_BAR,
        AIAssistApplicationConstants.CHANNEL_RECORD_PAGE_CHAT
      },
      AIConversationMessage__c.Sender__c => new List<String>{
        AIAssistApplicationConstants.SENDER_USER,
        AIAssistApplicationConstants.SENDER_AI_AGENT,
        AIAssistApplicationConstants.SENDER_SYSTEM
      },
      AIConversationMessage__c.ProcessingStatus__c => new List<String>{
        AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED,
        AIAssistApplicationConstants.PROCESSING_STATUS_PROCESSING,
        AIAssistApplicationConstants.PROCESSING_STATUS_COMPLETE,
        AIAssistApplicationConstants.PROCESSING_STATUS_FAILED
      },
      AIConversationMessage__c.FailureReason__c => new List<String>{
        AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR,
        AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT,
        AIAssistApplicationConstants.FAILURE_REASON_LIMIT_REACHED,
        AIAssistApplicationConstants.FAILURE_REASON_REQUEST_BLOCKED,
        AIAssistApplicationConstants.FAILURE_REASON_PII_MASKING_FAILED,
        AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR,
        AIAssistApplicationConstants.FAILURE_REASON_OTHER
      },
      AIExecutionStep__c.StepType__c => new List<String>{
        AIAssistApplicationConstants.STEP_TYPE_PROMPT_ASSEMBLY,
        AIAssistApplicationConstants.STEP_TYPE_DATA_SOURCE,
        AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL,
        AIAssistApplicationConstants.STEP_TYPE_WORKFLOW_ACTION,
        AIAssistApplicationConstants.STEP_TYPE_PII_MASKING,
        AIAssistApplicationConstants.STEP_TYPE_OTHER
      },
      AIExecutionStep__c.Status__c => new List<String>{
        AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS,
        AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED,
        AIAssistApplicationConstants.EXECUTION_STEP_STATUS_BLOCKED,
        AIAssistApplicationConstants.EXECUTION_STEP_STATUS_CANCELLED
      },
      AIPIIMaskingRecord__c.Outcome__c => new List<String>{
        AIAssistApplicationConstants.MASKING_OUTCOME_MASKED,
        AIAssistApplicationConstants.MASKING_OUTCOME_FAILED,
        AIAssistApplicationConstants.MASKING_OUTCOME_SKIPPED
      },
      AIAgent__c.RetentionTrigger__c => new List<String>{
        AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE,
        AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE,
        AIAssistApplicationConstants.RETENTION_TRIGGER_LAST_MESSAGE_DATE
      },
      AIAgent__c.AccessMode__c => new List<String>{
        AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY,
        AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS
      },
      AIAgent__c.TokenTrackingMethod__c => new List<String>{
        AIAssistApplicationConstants.TRACKING_METHOD_ESTIMATE,
        AIAssistApplicationConstants.TRACKING_METHOD_TRACK,
        AIAssistApplicationConstants.TRACKING_METHOD_PRE_REQUEST_CHECK
      },
      AIAgentAssignment__c.AssigneeType__c => new List<String>{
        AIAssistApplicationConstants.ASSIGNEE_TYPE_USER,
        AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET
      },
      AIUserSettings__c.UsageLimitReachedBehavior__c => new List<String>{
        AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY,
        AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES,
        AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY
      },
      AIDataSource__c.SourceType__c => new List<String>{
        AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX,
        AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL
      },
      AIDataSource__c.BindingType__c => new List<String>{
        AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND,
        AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND
      },
      AIWorkflowAction__c.ActionType__c => new List<String>{
        AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX,
        AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW
      },
      AIWorkflowAction__c.ExecutionType__c => new List<String>{
        AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY,
        AIAssistApplicationConstants.WORKFLOW_EXECUTION_WRITE
      },
      AIModelConfiguration__c.AIProvider__c => new List<String>{
        AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC,
        AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI
      },
      AIPlatformLog__c.Severity__c => new List<String>{
        AIAssistApplicationConstants.LOG_SEVERITY_ERROR,
        AIAssistApplicationConstants.LOG_SEVERITY_WARNING,
        AIAssistApplicationConstants.LOG_SEVERITY_INFO
      },
      AIPiiDataMaskingRule__mdt.Strategy__c => new List<String>{
        AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST,
        AIAssistApplicationConstants.PII_MASKING_STRATEGY_RANDOMIZE_BY_PATTERN
      },
      AIPiiFieldType__mdt.MatchField__c => new List<String>{
        AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS,
        AIAssistApplicationConstants.PII_MATCH_FIELD_API_NAME_EXACT,
        AIAssistApplicationConstants.PII_MATCH_FIELD_DATA_TYPE_CONTAINS
      }
    };

    Test.startTest();
    Map<String, Set<String>> missingByPicklist = new Map<String, Set<String>>();

    for (Schema.SObjectField picklist : constantsByPicklist.keySet()) {
      Set<String> offered = new Set<String>();
      for (
        Schema.PicklistEntry entry : picklist.getDescribe().getPicklistValues()
      )
        offered.add(entry.getValue());

      for (String constantValue : constantsByPicklist.get(picklist)) {
        if (!offered.contains(constantValue)) {
          String key = picklist.getDescribe().getSObjectType() + '.' + picklist;
          if (!missingByPicklist.containsKey(key))
            missingByPicklist.put(key, new Set<String>());
          missingByPicklist.get(key).add(constantValue);
        }
      }
    }
    Test.stopTest();

    Assert.isTrue(
      missingByPicklist.isEmpty(),
      'Every constant must match a value of its picklist. Missing: ' +
      missingByPicklist
    );
  }

  @IsTest
  static void testScenario2() {
    Test.startTest();
    Set<String> conversationChannels = new Set<String>();
    for (
      Schema.PicklistEntry entry : AIConversation__c.Channel__c.getDescribe()
        .getPicklistValues()
    )
      conversationChannels.add(entry.getValue());

    Set<String> allowedChannels = new Set<String>();
    for (
      Schema.PicklistEntry entry : AIUserSettings__c.AllowedChannels__c.getDescribe()
        .getPicklistValues()
    )
      allowedChannels.add(entry.getValue());
    Test.stopTest();

    Assert.areEqual(
      conversationChannels,
      allowedChannels,
      'A channel a user is allowed must be a channel a conversation can use, and the reverse.'
    );
    Assert.isTrue(
      conversationChannels.contains(
        AIAssistApplicationConstants.CHANNEL_MOBILE
      ),
      'Mobile must be a conversation channel, or a mobile conversation could not be saved.'
    );
  }

  @IsTest
  static void testScenario3() {
    Test.startTest();
    List<String> errorCodes = new List<String>{
      AIAssistApplicationConstants.ERROR_GENERIC,
      AIAssistApplicationConstants.ERROR_APPLICATION_DISABLED,
      AIAssistApplicationConstants.ERROR_MAINTENANCE_MODE,
      AIAssistApplicationConstants.ERROR_NEW_CONVERSATIONS_PAUSED,
      AIAssistApplicationConstants.ERROR_MESSAGE_EMPTY,
      AIAssistApplicationConstants.ERROR_MESSAGE_TOO_LONG,
      AIAssistApplicationConstants.ERROR_AGENT_NOT_FOUND,
      AIAssistApplicationConstants.ERROR_AGENT_INACTIVE,
      AIAssistApplicationConstants.ERROR_AGENT_NOT_ASSIGNED,
      AIAssistApplicationConstants.ERROR_AGENT_NOT_AVAILABLE,
      AIAssistApplicationConstants.ERROR_TERMS_NOT_ACKNOWLEDGED,
      AIAssistApplicationConstants.ERROR_TERMS_VERSION_CHANGED,
      AIAssistApplicationConstants.ERROR_CHANNEL_NOT_ALLOWED,
      AIAssistApplicationConstants.ERROR_RECORD_ACCESS_DENIED,
      AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
      AIAssistApplicationConstants.ERROR_CONVERSATION_CLOSED,
      AIAssistApplicationConstants.ERROR_CONVERSATION_BUSY,
      AIAssistApplicationConstants.ERROR_CONCURRENT_LIMIT,
      AIAssistApplicationConstants.ERROR_CONVERSATION_LIMIT_DAILY,
      AIAssistApplicationConstants.ERROR_DAILY_USAGE_LIMIT,
      AIAssistApplicationConstants.ERROR_PLAN_LIMIT_MESSAGES,
      AIAssistApplicationConstants.ERROR_PLAN_LIMIT_USAGE,
      AIAssistApplicationConstants.ERROR_SERVICE_BUSY
    };
    Set<String> distinctCodes = new Set<String>(errorCodes);
    Test.stopTest();

    Assert.areEqual(
      errorCodes.size(),
      distinctCodes.size(),
      'Two refusals must never share a code.'
    );
    Assert.isFalse(
      distinctCodes.contains(null) || distinctCodes.contains(''),
      'Every code must have a value.'
    );
    Assert.isTrue(
      AIAssistApplicationConstants.MAX_USER_MESSAGE_CHARACTERS > 0 &&
        AIAssistApplicationConstants.MAX_HISTORY_MESSAGES > 0 &&
        AIAssistApplicationConstants.MAX_TOOLS_PER_KIND > 0,
      'The guard rails must be positive.'
    );
    Assert.isTrue(
      AIAssistApplicationConstants.MAX_HISTORY_CHARACTERS >=
      AIAssistApplicationConstants.MAX_USER_MESSAGE_CHARACTERS,
      'A history budget smaller than one message could not hold the question being answered.'
    );
    Assert.isTrue(
      AIAssistApplicationConstants.MAX_USER_MESSAGE_CHARACTERS <= 131072,
      'A user message must fit the message body field.'
    );
  }
}
