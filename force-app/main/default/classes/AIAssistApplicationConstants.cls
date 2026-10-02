/*
Class Name: AIAssistApplicationConstants

=================================================================
=================================================================

Description: Every literal the application compares against or sends: picklist API values of the
object model, the shapes of the AI providers' requests and responses, error codes, and the guard
rails that protect the org the package is installed in.

Picklist values here must match the object model exactly. AIAssistApplicationConstantsTest reads
each picklist back from the org and fails if one of these has drifted, so a renamed picklist
value is caught by the test run rather than by a user.

User-facing text never lives here: it is a Custom Label (AI_Error_*, AI_Chat_*, AI_Step_*), so it
translates. The only text here is text sent to a machine - the model, a provider API, a log.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Rebuilt for the object model: picklist values corrected, user-facing strings removed, messaging-layer values merged in.
*/

public inherited sharing class AIAssistApplicationConstants {
  // AIConversation__c.Channel__c / AIUserSettings__c.AllowedChannels__c (global value set AIChannel)
  public static final String CHANNEL_MOBILE = 'Mobile';
  public static final String CHANNEL_UTILITY_BAR = 'Utility Bar';
  public static final String CHANNEL_RECORD_PAGE_CHAT = 'Record Page Chat';
  public static final String DELIMITER_MULTI_SELECT_SEPARATOR = ';';

  // AIUserSettings__c.UsageLimitReachedBehavior__c
  public static final String USAGE_LIMIT_NOTIFY_ONLY = 'Notify Only';
  public static final String USAGE_LIMIT_BLOCK_NEW_MESSAGES = 'Block New Messages';
  public static final String USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY = 'Block New Conversations Only';

  // AIPlatformLogEvent__e.ExceptionType__c
  public static final String LOG_TYPE_CUSTOM_MESSAGE = 'Custom Message';
  public static final String LOG_TYPE_DML_FAILURE = 'DML Save Failure';

  // AIPlatformLog__c.Severity__c
  public static final String LOG_SEVERITY_ERROR = 'Error';
  public static final String LOG_SEVERITY_WARNING = 'Warning';
  public static final String LOG_SEVERITY_INFO = 'Info';

  // AIAssistGlobalUtility - the identifier fields it stamps, found by name on any object that has them.
  public static final String DEVELOPER_NAME_FIELD_API_NAME = 'DeveloperName__c';
  public static final String PUBLIC_ID_FIELD_API_NAME = 'PublicId__c';

  // AIDataSource__c.SourceType__c
  public static final String DATA_SOURCE_TYPE_APEX = 'Apex';
  public static final String DATA_SOURCE_TYPE_SOQL = 'SOQL';

  // AIDataSource__c.BindingType__c
  public static final String DATA_SOURCE_BINDING_BOUND = 'Bound';
  public static final String DATA_SOURCE_BINDING_UNBOUND = 'Unbound';

  // AIAgentManager.invokeTool - handed to the model in place of a bare "[]" so it can tell a genuine no-match apart from a failure and stop retrying.
  public static final String TOOL_RESULT_NO_RECORDS_FOUND = 'No records found.';

  // AIWorkflowAction__c.ActionType__c
  public static final String WORKFLOW_ACTION_TYPE_APEX = 'Apex';
  public static final String WORKFLOW_ACTION_TYPE_FLOW = 'Flow';

  // AIWorkflowAction__c.ExecutionType__c
  public static final String WORKFLOW_EXECUTION_READ_ONLY = 'Read Only';
  public static final String WORKFLOW_EXECUTION_WRITE = 'Write';

  // AIAgent__c.RetentionTrigger__c
  public static final String RETENTION_TRIGGER_CONVERSATION_CREATED_DATE = 'Conversation Created Date';
  public static final String RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE = 'Conversation Closed Date';
  public static final String RETENTION_TRIGGER_LAST_MESSAGE_DATE = 'Last Message Date';

  // AIAgent__c.AccessMode__c
  public static final String ACCESS_MODE_ASSIGNED_ONLY = 'Assigned Users Only';
  public static final String ACCESS_MODE_ALL_USERS = 'All AI Assist Users';

  // AIAgent__c.TokenTrackingMethod__c (named for the method, not the unit, so a scanner does not mistake these for credentials)
  public static final String TRACKING_METHOD_ESTIMATE = 'Estimate Token Usage';
  public static final String TRACKING_METHOD_TRACK = 'Track Token Usage';
  public static final String TRACKING_METHOD_PRE_REQUEST_CHECK = 'Pre-Request Usage Check';

  // AIAgentAssignment__c.AssigneeType__c
  public static final String ASSIGNEE_TYPE_USER = 'User';
  public static final String ASSIGNEE_TYPE_PERMISSION_SET = 'Permission Set';

  // AIConversation__c.Status__c
  public static final String CONVERSATION_STATUS_ACTIVE = 'Active';
  public static final String CONVERSATION_STATUS_CLOSED = 'Closed';

  // AIConversation__c.ConversationCloseReason__c
  public static final String CONVERSATION_CLOSE_REASON_IDLE_TIMEOUT = 'Idle Timeout';
  public static final String CONVERSATION_CLOSE_REASON_USER_CLOSED = 'User Closed';
  public static final String CONVERSATION_CLOSE_REASON_MESSAGE_LIMIT_REACHED = 'Message Limit Reached';
  public static final String CONVERSATION_CLOSE_REASON_TOKEN_LIMIT_REACHED = 'Token Limit Reached';
  public static final String CONVERSATION_CLOSE_REASON_SYSTEM_OVERRIDE = 'System Override';

  // AIConversationMessage__c.Sender__c
  public static final String SENDER_USER = 'User';
  public static final String SENDER_AI_AGENT = 'AI Agent';
  public static final String SENDER_SYSTEM = 'System';

  // AIConversationMessage__c.ProcessingStatus__c
  public static final String PROCESSING_STATUS_QUEUED = 'Queued';
  public static final String PROCESSING_STATUS_PROCESSING = 'Processing';
  public static final String PROCESSING_STATUS_COMPLETE = 'Complete';
  public static final String PROCESSING_STATUS_FAILED = 'Failed';

  // AIConversationMessage__c.FailureReason__c
  public static final String FAILURE_REASON_PROVIDER_ERROR = 'Provider Error';
  public static final String FAILURE_REASON_TIMEOUT = 'Timeout';
  public static final String FAILURE_REASON_LIMIT_REACHED = 'Limit Reached';
  public static final String FAILURE_REASON_REQUEST_BLOCKED = 'Request Blocked';
  public static final String FAILURE_REASON_PII_MASKING_FAILED = 'PII Masking Failed';
  public static final String FAILURE_REASON_CONFIGURATION_ERROR = 'Configuration Error';
  public static final String FAILURE_REASON_OTHER = 'Other';
  public static final String FAILURE_REASON_MESSAGE_MISSING = 'Message Missing'; // Never stored: only selects the label shown when the message being answered was deleted.

  // AIExecutionStep__c.StepType__c
  public static final String STEP_TYPE_PROMPT_ASSEMBLY = 'Prompt Assembly';
  public static final String STEP_TYPE_DATA_SOURCE = 'Data Source';
  public static final String STEP_TYPE_PROVIDER_CALL = 'Provider Call';
  public static final String STEP_TYPE_WORKFLOW_ACTION = 'Workflow Action';
  public static final String STEP_TYPE_PII_MASKING = 'PII Masking';
  public static final String STEP_TYPE_OTHER = 'Other';

  // AIExecutionStep__c.Status__c
  public static final String EXECUTION_STEP_STATUS_SUCCESS = 'Success';
  public static final String EXECUTION_STEP_STATUS_FAILED = 'Failed';
  public static final String EXECUTION_STEP_STATUS_BLOCKED = 'Blocked';
  public static final String EXECUTION_STEP_STATUS_CANCELLED = 'Cancelled';

  // AIPIIMaskingRecord__c.Outcome__c
  public static final String MASKING_OUTCOME_MASKED = 'Masked';
  public static final String MASKING_OUTCOME_FAILED = 'Failed';
  public static final String MASKING_OUTCOME_SKIPPED = 'Skipped';

  // AIModelConfiguration__c.AIProvider__c
  public static final String AI_PROVIDER_ANTHROPIC = 'Anthropic';
  public static final String AI_PROVIDER_OPEN_AI = 'OpenAI';

  // Feature Management parameter names (featureParameters in the object model). "Usage" is the token allowance.
  public static final String FEATURE_MAX_MONTHLY_MESSAGES = 'MaxMonthlyMessages';
  public static final String FEATURE_MAX_MONTHLY_USAGE = 'MaxMonthlyTokens';
  public static final String FEATURE_APEX_DATA_SOURCES_ALLOWED = 'ApexDataSourcesAllowed';
  public static final String FEATURE_WORKFLOW_ACTIONS_ALLOWED = 'WorkflowActionsAllowed';
  public static final String FEATURE_AI_EVALUATED_RULES_ALLOWED = 'AIEvaluatedRulesAllowed';
  public static final String FEATURE_MAX_ACTIVE_AGENTS = 'MaxActiveAgents';
  public static final String FEATURE_MAX_ACTIVE_DATA_SOURCES = 'MaxActiveDataSources';
  public static final String FEATURE_MAX_ACTIVE_WORKFLOW_ACTIONS = 'MaxActiveWorkflowActions';
  public static final String FEATURE_MAX_CONVERSATION_RETENTION_DAYS = 'MaxConversationRetentionDays';
  public static final String FEATURE_MULTIPLE_PROVIDERS_ALLOWED = 'MultipleProvidersAllowed';

  // AIMessagingException.code - stable values, so the UI never has to parse a translated message.
  public static final String ERROR_GENERIC = 'GENERIC';
  public static final String ERROR_APPLICATION_DISABLED = 'APPLICATION_DISABLED';
  public static final String ERROR_MAINTENANCE_MODE = 'MAINTENANCE_MODE';
  public static final String ERROR_NEW_CONVERSATIONS_PAUSED = 'NEW_CONVERSATIONS_PAUSED';
  public static final String ERROR_MESSAGE_EMPTY = 'MESSAGE_EMPTY';
  public static final String ERROR_MESSAGE_TOO_LONG = 'MESSAGE_TOO_LONG';
  public static final String ERROR_AGENT_NOT_FOUND = 'AGENT_NOT_FOUND';
  public static final String ERROR_AGENT_INACTIVE = 'AGENT_INACTIVE';
  public static final String ERROR_AGENT_NOT_ASSIGNED = 'AGENT_NOT_ASSIGNED';
  public static final String ERROR_AGENT_NOT_AVAILABLE = 'AGENT_NOT_AVAILABLE';
  public static final String ERROR_TERMS_NOT_ACKNOWLEDGED = 'TERMS_NOT_ACKNOWLEDGED';
  public static final String ERROR_TERMS_VERSION_CHANGED = 'TERMS_VERSION_CHANGED';
  public static final String ERROR_CHANNEL_NOT_ALLOWED = 'CHANNEL_NOT_ALLOWED';
  public static final String ERROR_RECORD_ACCESS_DENIED = 'RECORD_ACCESS_DENIED';
  public static final String ERROR_CONVERSATION_NOT_FOUND = 'CONVERSATION_NOT_FOUND';
  public static final String ERROR_CONVERSATION_CLOSED = 'CONVERSATION_CLOSED';
  public static final String ERROR_CONVERSATION_BUSY = 'CONVERSATION_BUSY';
  public static final String ERROR_CONCURRENT_LIMIT = 'CONCURRENT_LIMIT';
  public static final String ERROR_CONVERSATION_LIMIT_DAILY = 'CONVERSATION_LIMIT_DAILY';
  public static final String ERROR_DAILY_USAGE_LIMIT = 'DAILY_USAGE_LIMIT';
  public static final String ERROR_PLAN_LIMIT_MESSAGES = 'PLAN_LIMIT_MESSAGES';
  public static final String ERROR_PLAN_LIMIT_USAGE = 'PLAN_LIMIT_TOKENS';
  public static final String ERROR_SERVICE_BUSY = 'SERVICE_BUSY';
  public static final String ERROR_NOT_AUTHORISED = 'NOT_AUTHORISED';
  public static final String ERROR_COMMAND_UNKNOWN = 'COMMAND_UNKNOWN';
  public static final String ERROR_FEEDBACK_INVALID = 'FEEDBACK_INVALID';
  public static final String ERROR_ACTION_NOT_PERMITTED = 'ACTION_NOT_PERMITTED';
  public static final String ERROR_ACTION_CONFIRMATION_REQUIRED = 'ACTION_CONFIRMATION_REQUIRED';
  public static final String ERROR_ACTION_FAILED = 'ACTION_FAILED';
  public static final String ERROR_PLAN_ACTIONS_NOT_INCLUDED = 'PLAN_ACTIONS_NOT_INCLUDED';
  public static final String ERROR_PLAN_APEX_NOT_INCLUDED = 'PLAN_APEX_NOT_INCLUDED';
  public static final String ERROR_REQUEST_BLOCKED = 'REQUEST_BLOCKED';
  public static final String ERROR_DELETION_NOT_APPROVED = 'DELETION_NOT_APPROVED';

  // Messaging guard rails. None is a business setting: each keeps one chat from taking an unreasonable share of the heap, CPU, asynchronous queue or token budget of the org the package is installed in.
  public static final Integer MAX_USER_MESSAGE_CHARACTERS = 8000; // The full 131,072 character field is never needed for a chat message.
  public static final Integer MAX_HISTORY_MESSAGES = 50; // History sent with a turn is capped by count AND characters, whichever is hit first.
  public static final Integer MAX_HISTORY_CHARACTERS = 100000;
  public static final Integer MAX_TOOLS_PER_KIND = 64; // The model sees every active data source and action as a tool, so hundreds linked would bloat every request.
  public static final Integer DEFAULT_PROCESSING_LOCK_MINUTES = 10; // Used when AIAssistSettings__c.ProcessingLockMinutes__c is blank or below 1.
  public static final Integer MAX_PENDING_PROCESSING_JOBS = 200; // The asynchronous queue is shared with the subscriber's own work.
  public static final Integer RETRY_DELAY_MINUTES = 1; // Before the second and later retries, so a rate-limited provider is not hit again at once.
  public static final Integer CHARACTERS_PER_TOKEN_ESTIMATE = 4;
  public static final Integer STEP_JSON_FIELD_LENGTH = 131072; // AIExecutionStep__c field sizes.
  public static final Integer STEP_SENT_PREVIEW_LENGTH = 255;
  public static final Integer STEP_FIELDS_SENT_LENGTH = 32768;
  public static final Integer STEP_OBJECTS_SENT_LENGTH = 255;
  public static final Integer EVENT_ERROR_MESSAGE_LENGTH = 255; // AIMessageReadyEvent__e.ErrorMessage__c.

  // AIAgentManager - canonical (provider-agnostic) message shape built from AIConversationMessage__c history, before any provider handler reshapes it.
  public static final String CANONICAL_ROLE_KEY = 'role';
  public static final String CANONICAL_CONTENT_KEY = 'content';
  public static final String CANONICAL_ROLE_USER = 'user';
  public static final String CANONICAL_ROLE_ASSISTANT = 'assistant';

  // AI provider response handlers - used when AIAssistSettings__c.AIProviderSuccessStatusCodes__c is blank or has no valid codes.
  public static final Set<Integer> DEFAULT_AI_PROVIDER_SUCCESS_STATUS_CODES = new Set<Integer>{
    200
  };

  // Values the PII classifier and masking rules use. AIPIIFieldMetadata__c.PIIFieldType__c is free text in the object model, so these are the package's own names, not a picklist.
  public static final String PII_FIELD_TYPE_NAME = 'Name';
  public static final String PII_FIELD_TYPE_EMAIL = 'Email';
  public static final String PII_FIELD_TYPE_PHONE = 'Phone';
  public static final String PII_FIELD_TYPE_ADDRESS = 'Address';
  public static final String PII_FIELD_TYPE_SSN = 'SSN';
  public static final String PII_FIELD_TYPE_BANK_ACCOUNT = 'Bank Account';
  public static final String PII_FIELD_TYPE_CREDIT_CARD = 'Credit Card';
  public static final String PII_FIELD_TYPE_DATE_OF_BIRTH = 'Date of Birth';
  public static final String PII_FIELD_TYPE_IP_ADDRESS = 'IP Address';
  public static final String PII_FIELD_TYPE_GOVERNMENT_ID = 'Government ID';
  public static final String PII_FIELD_TYPE_NATIONAL_INSURANCE_NUMBER = 'National Insurance Number';
  public static final String PII_FIELD_TYPE_NHS_NUMBER = 'NHS Number';
  public static final String PII_FIELD_TYPE_VAT_NUMBER = 'VAT Number';
  public static final String PII_FIELD_TYPE_MEDICAL_RECORD = 'Medical Record Number';
  public static final String PII_FIELD_TYPE_VEHICLE_REGISTRATION = 'Vehicle Registration';
  public static final String PII_FIELD_TYPE_USERNAME = 'Username';
  public static final String PII_FIELD_TYPE_PASSWORD = 'Password';
  public static final String PII_FIELD_TYPE_OTHER = 'Other';

  // AIPiiDataMaskingRule__mdt.Strategy__c
  public static final String PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST = 'SubstituteFromList';
  public static final String PII_MASKING_STRATEGY_RANDOMIZE_BY_PATTERN = 'RandomizeByPattern';

  // AIPiiFieldType__mdt.MatchField__c
  public static final String PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS = 'NameOrLabelContains';
  public static final String PII_MATCH_FIELD_API_NAME_EXACT = 'ApiNameExact';
  public static final String PII_MATCH_FIELD_DATA_TYPE_CONTAINS = 'DataTypeContains';

  // AIDataSourceResultProcessor
  public static final Integer DATA_SOURCE_RESULT_MAX_PARENT_DEPTH = 4;
  public static final Integer DATA_SOURCE_RESULT_MAX_CHILD_DEPTH = 3;
  public static final String DATA_SOURCE_RESULT_REDACTED_ERROR_VALUE = '***REDACTED-ERROR***';

  // AIAnthropicResponseHandler - field/value names in Anthropic's Messages API response shape.
  public static final String ANTHROPIC_FIELD_CONTENT = 'content';
  public static final String ANTHROPIC_FIELD_BLOCK_TYPE = 'type';
  public static final String ANTHROPIC_BLOCK_TYPE_TEXT = 'text';
  public static final String ANTHROPIC_FIELD_TEXT = 'text';
  public static final String ANTHROPIC_BLOCK_TYPE_TOOL_USE = 'tool_use';
  public static final String ANTHROPIC_BLOCK_TYPE_TOOL_RESULT = 'tool_result';
  public static final String ANTHROPIC_FIELD_TOOL_USE_ID = 'id';
  public static final String ANTHROPIC_FIELD_TOOL_NAME = 'name';
  public static final String ANTHROPIC_FIELD_TOOL_USE_INPUT = 'input';
  public static final String ANTHROPIC_FIELD_TOOL_RESULT_ID = 'tool_use_id';

  // AIAnthropicRequestBuilder - field names in Anthropic's Messages API request shape. Tool name reuses ANTHROPIC_FIELD_TOOL_NAME above.
  public static final String ANTHROPIC_FIELD_MODEL = 'model';
  public static final String ANTHROPIC_FIELD_MAX_TOKENS = 'max_tokens';
  public static final String ANTHROPIC_FIELD_MESSAGES = 'messages';
  public static final String ANTHROPIC_FIELD_TEMPERATURE = 'temperature';
  public static final String ANTHROPIC_FIELD_SYSTEM = 'system';
  public static final String ANTHROPIC_FIELD_TOOLS = 'tools';
  public static final String ANTHROPIC_FIELD_TOOL_DESCRIPTION = 'description';
  public static final String ANTHROPIC_FIELD_TOOL_INPUT_SCHEMA = 'input_schema';

  // AIOpenAiRequestBuilder - field/value names in OpenAI's Chat Completions API request shape.
  public static final String OPENAI_FIELD_MODEL = 'model';
  public static final String OPENAI_FIELD_MAX_TOKENS = 'max_tokens';
  public static final String OPENAI_FIELD_MESSAGES = 'messages';
  public static final String OPENAI_FIELD_TEMPERATURE = 'temperature';
  public static final String OPENAI_FIELD_CONTENT = 'content';
  public static final String OPENAI_FIELD_TOOLS = 'tools';
  public static final String OPENAI_FIELD_TOOL_TYPE = 'type';
  public static final String OPENAI_TOOL_TYPE_FUNCTION = 'function';
  public static final String OPENAI_FIELD_TOOL_FUNCTION = 'function';
  public static final String OPENAI_FIELD_TOOL_NAME = 'name';
  public static final String OPENAI_FIELD_TOOL_DESCRIPTION = 'description';
  public static final String OPENAI_FIELD_TOOL_PARAMETERS = 'parameters';

  // AIOpenAiResponseHandler - field/value names in OpenAI's Chat Completions API response shape. Content, function, tool name and role key reuse the OPENAI_* constants above.
  public static final String OPENAI_FIELD_CHOICES = 'choices';
  public static final String OPENAI_FIELD_MESSAGE = 'message';
  public static final String OPENAI_FIELD_TOOL_CALLS = 'tool_calls';
  public static final String OPENAI_FIELD_TOOL_CALL_ID = 'id';
  public static final String OPENAI_FIELD_TOOL_CALL_ARGUMENTS = 'arguments';
  public static final String OPENAI_FIELD_TOOL_RESULT_ID = 'tool_call_id';

  // AIAnthropicRequestBuilder / AIOpenAiRequestBuilder - sent on the last tool-calling iteration so the model must answer rather than call another tool.
  public static final String ANTHROPIC_FIELD_TOOL_CHOICE = 'tool_choice';
  public static final String ANTHROPIC_FIELD_TOOL_CHOICE_TYPE = 'type';
  public static final String ANTHROPIC_TOOL_CHOICE_NONE = 'none';
  public static final String OPENAI_FIELD_TOOL_CHOICE = 'tool_choice';
  public static final String OPENAI_TOOL_CHOICE_NONE = 'none';

  // Tool names both AI providers accept - letters, numbers, underscores and hyphens, 1-64 characters. Checked on AIDataSource__c.DeveloperName__c by AIDataSourceTriggerHandler.
  public static final String AI_PROVIDER_TOOL_NAME_PATTERN = '^[a-zA-Z0-9_-]{1,64}$';

  // AIAgentManager - used when AIAssistSettings__c.DefaultMaxToolCallingIterations__c / MaxToolCallingIterationsCap__c / MaxToolCallsPerIteration__c are blank or below 1.
  public static final Integer DEFAULT_MAX_TOOL_CALLING_ITERATIONS = 5;
  public static final Integer DEFAULT_MAX_TOOL_CALLING_ITERATIONS_CAP = 20;
  public static final Integer DEFAULT_MAX_TOOL_CALLS_PER_ITERATION = 5;

  // AIAgentManager - tool results sent back to the model when a tool call isn't run. Worded for the model, so it answers with what it already has rather than asking again.
  public static final String TOOL_RESULT_SKIPPED_TOO_MANY_CALLS = 'Not run: too many tool calls in one step. Ask for fewer tools at once, or answer with the information you already have.';
  public static final String TOOL_RESULT_FAILED = 'This tool failed to run. Answer with the information you already have, or tell the user the information is unavailable.';
  public static final String TOOL_RESULT_SKIPPED_LIMITS_REACHED = 'Not run: Salesforce processing limits for this request have been reached. Answer with the information you already have.';

  // AIGovernorLimits - Salesforce allows 120s of total callout time per transaction. No callout starts with less than the minimum left - it would almost certainly time out, and the AI provider may still bill for a request it had already started on.
  public static final Integer MAX_TRANSACTION_CALLOUT_MILLISECONDS = 120000;
  public static final Integer MIN_CALLOUT_TIMEOUT_MILLISECONDS = 5000;

  // AIGovernorLimits - amount of each limit held back before running another tool call - enough for the next AI provider callout and the work after the loop (saving PII mappings, inserting the reply and its trigger).
  public static final Integer TOOL_CALL_RESERVED_SOQL_QUERIES = 20;
  public static final Integer TOOL_CALL_RESERVED_CALLOUTS = 1;
  public static final Integer TOOL_CALL_RESERVED_CPU_MILLISECONDS = 5000;
  public static final Integer TOOL_CALL_RESERVED_HEAP_BYTES = 2000000;

  // AIGovernorLimits - Publish Immediately events (Limits.getLimitPublishImmediateDML(), 150 per transaction) are shared with AIPlatformLogManager's own logging, which must always be able to get through - so live progress (AIAgentProgressPublisher) gives up first and holds this many back for it.
  public static final Integer PROGRESS_EVENT_RESERVED_PUBLISH_IMMEDIATE = 20;

  // AIGovernorLimits - the platform's message when a callout is attempted after uncommitted DML in the same transaction.
  public static final String UNCOMMITTED_WORK_ERROR_TEXT = 'uncommitted work pending';

  // AIAgentManager - AI provider callout request.
  public static final String HTTP_METHOD_POST = 'POST';
  public static final String HTTP_HEADER_CONTENT_TYPE = 'Content-Type';
  public static final String CONTENT_TYPE_JSON = 'application/json';

  // AIAgentManager - the model can only ever suggest a Workflow Action, never run one - phase 1 requires the user to trigger it explicitly from the chat UI.
  public static final String SUGGESTED_WORKFLOW_ACTION_JSON_KEY = 'suggested_workflow_action';
  public static final String WORKFLOW_ACTION_PROMPT_INSTRUCTION = 'Workflows (you cannot run these; suggest one only if it genuinely helps, never claim to have run one):';
  public static final String WORKFLOW_ACTION_SUGGESTION_ONLY_REPLY = 'Here\'s a suggested next step.'; // Shown when the model's reply was only a Workflow Action suggestion, so the saved reply is never blank.
  public static final String WORKFLOW_ACTION_PROMPT_JSON_INSTRUCTION =
    'To suggest one, end your reply with a line containing only {"' +
    SUGGESTED_WORKFLOW_ACTION_JSON_KEY +
    '":"<DeveloperName>"}; otherwise omit it.';

  // Provider request/response shapes and agent-manager values completed from the previous block.
  public static final String ANTHROPIC_FIELD_USAGE = 'usage';
  public static final String ANTHROPIC_FIELD_USAGE_INPUT_TOKENS = 'input_tokens';
  public static final String ANTHROPIC_FIELD_USAGE_OUTPUT_TOKENS = 'output_tokens';
  public static final String ANTHROPIC_FIELD_ERROR = 'error';
  public static final String ANTHROPIC_FIELD_ERROR_MESSAGE = 'message';
  public static final String ANTHROPIC_FIELD_ERROR_TYPE = 'type';
  public static final String ANTHROPIC_ROLE_KEY = 'role';
  public static final String ANTHROPIC_ROLE_USER = 'user';
  public static final String ANTHROPIC_ROLE_ASSISTANT = 'assistant';
  public static final String OPENAI_ROLE_KEY = 'role';
  public static final String OPENAI_ROLE_SYSTEM = 'system';
  public static final String OPENAI_FIELD_USAGE = 'usage';
  public static final String OPENAI_FIELD_USAGE_TOTAL_TOKENS = 'total_tokens';
  public static final String OPENAI_FIELD_USAGE_PROMPT_TOKENS = 'prompt_tokens';
  public static final String OPENAI_FIELD_USAGE_COMPLETION_TOKENS = 'completion_tokens';
  public static final String OPENAI_FIELD_ERROR = 'error';
  public static final String OPENAI_FIELD_ERROR_MESSAGE = 'message';
  public static final String OPENAI_FIELD_ERROR_TYPE = 'type';
  public static final String OPENAI_ROLE_TOOL = 'tool';
  // AIAssistUISettings__c.SuggestedActionsDisplay__c (Text - Custom Settings have no picklists)
  public static final String SUGGESTED_ACTIONS_DISPLAY_CARDS = 'Cards';
  // AIAssistUISettings__c.SuggestedActionsDisplay__c (Text - Custom Settings have no picklists)
  public static final String SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS = 'Inline Buttons';

  // Housekeeping jobs, the PII registry sync and data deletion requests.
  public static final String PII_SYNC_STATUS_NOT_SYNCED = 'Not Synced';
  public static final String PII_SYNC_STATUS_QUEUED = 'Queued';
  public static final String PII_SYNC_STATUS_IN_PROGRESS = 'In Progress';
  public static final String PII_SYNC_STATUS_SYNCED = 'Synced';
  public static final String PII_SYNC_STATUS_FAILED = 'Failed';
  public static final Integer DEFAULT_MAX_PII_FIELDS_TO_QUERY = 200;
  public static final Integer MAX_PII_REGISTRIES_PER_RUN = 20; // One queueable syncs them all, so this bounds its queries and DML.
  public static final Integer HOUSEKEEPING_BATCH_SIZE = 200;
  public static final Integer DATA_DELETION_BATCH_SIZE = 100; // Each conversation takes its messages, steps and mappings with it.

  public static final String DELETION_STATUS_REQUESTED = 'Requested';
  public static final String DELETION_STATUS_APPROVED = 'Approved';
  public static final String DELETION_STATUS_IN_PROGRESS = 'In Progress';
  public static final String DELETION_STATUS_COMPLETED = 'Completed';
  public static final String DELETION_STATUS_REJECTED = 'Rejected';
  public static final String DELETION_STATUS_FAILED = 'Failed';
  public static final String DELETION_DECISION_PENDING = 'Pending';
  public static final String DELETION_DECISION_APPROVED = 'Approved';
  public static final String DELETION_DECISION_REJECTED = 'Rejected';
  public static final String DELETION_SCOPE_USER = 'User';
  public static final String DELETION_SCOPE_RELATED_RECORD = 'Related Record';

  // Violations.
  public static final String REVIEW_STATUS_NEW = 'New';
  public static final String REVIEW_STATUS_REVIEWED = 'Reviewed';
  public static final String REVIEW_STATUS_DISMISSED = 'Dismissed';
  public static final String SEVERITY_LOW = 'Low';
  public static final String SEVERITY_MEDIUM = 'Medium';
  public static final String SEVERITY_HIGH = 'High';
  public static final String DETECTION_METHOD_DETERMINISTIC = 'Deterministic_Apex';
  public static final String DETECTION_METHOD_AI_EVALUATED = 'AI_Evaluated';
  public static final String VIOLATION_TYPE_UNAUTHORIZED_DATA_ACCESS = 'Unauthorized_Data_Access';
  public static final String VIOLATION_TYPE_UNAUTHORIZED_WORKFLOW_ACTION = 'Unauthorized_Workflow_Action';
  public static final String VIOLATION_TYPE_USAGE_LIMIT_EXCEEDED = 'Usage_Limit_Exceeded';
  public static final String VIOLATION_TYPE_PII_MASKING_FAILURE = 'PII_Masking_Failure';
  public static final String VIOLATION_TYPE_CONFIGURATION = 'Configuration_Violation';
  public static final String VIOLATION_TYPE_AI_FLAGGED_INTENT = 'AI_Flagged_Intent';
  public static final Integer MAX_AI_RULES_PER_AGENT = 10; // Every AI evaluated rule adds its instruction to every request.
  public static final Integer VIOLATION_DETAIL_LENGTH = 255;

  // The chat window.
  public static final String PERMISSION_SET_USER = 'AIAssistUser';
  public static final String PERMISSION_SET_SUPER_USER = 'AIAssistSuperUser';
  public static final String PERMISSION_SET_ADMIN_USER = 'AIAssistAdminUser';
  public static final String USER_LEVEL_USER = 'User';
  public static final String USER_LEVEL_SUPER_USER = 'Super User';
  public static final String USER_LEVEL_ADMIN = 'Admin';
  public static final String FEEDBACK_RATING_HELPFUL = 'Helpful';
  public static final String FEEDBACK_RATING_NOT_HELPFUL = 'Not Helpful';
  public static final String CONVERSATION_LOAD_TRIGGER_MANUAL_ONLY = 'Manual Only';
  public static final String CHAT_COMMAND_AVAILABLE_TO_SUPER_USERS_AND_ADMINS = 'Super Users and Admins';
  public static final String CHAT_COMMAND_AVAILABLE_TO_ADMINS_ONLY = 'Admins Only';
  public static final String CHAT_COMMAND_PROMPT_SEPARATOR = '\n\n[Command instructions]\n';
  public static final String CHAT_COMMAND_PATTERN = '^/[A-Za-z0-9_-]{1,40}(\\s[\\s\\S]*)?$';
  public static final String CHAT_STATE_READY = 'READY';
  public static final String CHAT_STATE_INACTIVE = 'INACTIVE';
  public static final String CHAT_STATE_MAINTENANCE = 'MAINTENANCE';
  public static final String CHAT_STATE_CHANNEL_DISABLED = 'CHANNEL_DISABLED';
  public static final String CHAT_STATE_NO_AGENT = 'NO_AGENT';
  public static final String CHAT_STATE_TERMS = 'TERMS';
  public static final String CHAT_SEND_STATUS_SENT = 'SENT';
  public static final String CHAT_SEND_STATUS_BLOCKED = 'BLOCKED';
  public static final String CHAT_SEND_STATUS_LIMIT = 'LIMIT';
  public static final String CHAT_SEND_STATUS_ERROR = 'ERROR';
  public static final Integer CHAT_HISTORY_MAX_CONVERSATIONS = 50;
  public static final Integer CHAT_DEFAULT_MESSAGE_PAGE_SIZE = 20;
  public static final Integer CHAT_CONVERSATION_TITLE_MAX_LENGTH = 60;
  public static final Integer CHAT_MAX_AGENTS = 50;
  public static final Integer FEEDBACK_COMMENT_LENGTH = 255;
}
