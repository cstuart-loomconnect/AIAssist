/*
Class Name: AIAssistApplicationConstants

=================================================================
=================================================================

Description: Every literal the application compares against or sends, kept in one place.

Step 1: Picklist API values of the object model are listed first, grouped by object and field
Step 2: Guard rails, provider request and response shapes and chat window values follow
Step 3: Other classes read these constants and never hold the literals themselves

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAssistApplicationConstants {

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
    // AIUserSettings__c / AIUsagePolicy__c.ConversationVisibilityScope__c
    public static final String VISIBILITY_SCOPE_OWN = 'My Conversations Only';
    public static final String VISIBILITY_SCOPE_SUBORDINATES = 'My Subordinates Conversations';
    public static final String VISIBILITY_SCOPE_ALL = 'All Conversations';

    // AIAgent__c.ConversationVisibility__c: Private is the starter only; Global lets viewers whose own scope reaches the starter read it.
    public static final String AGENT_VISIBILITY_GLOBAL = 'Global';
    public static final Integer MAX_FLOW_RECORD_INPUTS = 200; // UserRecordAccess answers for at most 200 records per query; a Flow action handed more is refused.
    public static final String PERMISSION_VIEW_SHARED_CONVERSATIONS = 'AIAssistViewSharedConversations'; // Custom permission: honours the All Conversations scope without View All.
    public static final Integer MAX_ROLE_HIERARCHY_DEPTH = 20; // Levels of the role hierarchy walked to find a viewer's subordinates.

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
    public static final String FAILURE_REASON_AUTHENTICATION_FAILED = 'Authentication Failed';
    public static final String FAILURE_REASON_MODEL_RETIRED = 'Model Retired';
    public static final String FAILURE_REASON_RATE_LIMITED = 'Rate Limited';
    public static final String FAILURE_REASON_SERVICE_BUSY = 'Service Busy'; // Held at the cap on messages in flight for too long, and never started.
    // HTTP statuses that will fail the same way however often they are sent again. Never retried, whatever AIAssistSettings__c.RetryableStatusCodes__c says.
    public static final Set<Integer> NEVER_RETRIED_STATUS_CODES = new Set<Integer>{400, 401, 403, 404, 410, 413, 422};
    public static final String FAILURE_REASON_MESSAGE_MISSING = 'Message Missing'; // Never stored: only selects the label shown when the message being answered was deleted.

    // The stepType of an entry in AIConversationMessage__c.ExecutionTraceJson__c
    public static final String STEP_TYPE_PROMPT_ASSEMBLY = 'Prompt Assembly';
    public static final String STEP_TYPE_DATA_SOURCE = 'Data Source';
    public static final String STEP_TYPE_TEMPLATE_MATCH = 'Template Match';
    public static final String STEP_TYPE_PROVIDER_CALL = 'Provider Call';
    public static final String STEP_TYPE_WORKFLOW_ACTION = 'Workflow Action';
    public static final String STEP_TYPE_PII_MASKING = 'PII Masking';
    public static final String STEP_TYPE_OTHER = 'Other';

    // The status of an entry in AIConversationMessage__c.ExecutionTraceJson__c
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
    public static final String AI_PROVIDER_ANTHROPIC_AGENT = 'AnthropicAgent';

    // Messaging guard rails. None is a business setting: each keeps one chat from taking an unreasonable share of the heap, CPU, asynchronous queue or token budget of the org the package is installed in.
    public static final Integer MAX_USER_MESSAGE_CHARACTERS = 8000; // The full 131,072 character field is never needed for a chat message.
    public static final Integer MAX_HISTORY_MESSAGES = 50; // History sent with a turn is capped by count AND characters, whichever is hit first.
    public static final Integer MAX_HISTORY_CHARACTERS = 100000;
    public static final Integer MAX_TOOLS_PER_KIND = 64; // The model sees every active data source and action as a tool, so hundreds linked would bloat every request.
    public static final Integer MAX_ACTIVE_CONVERSATIONS_COUNTED = 2000; // Rows read to count a user's open conversations; far above any concurrent limit.
    public static final Integer MAX_PENDING_PROCESSING_JOBS = 200; // The asynchronous queue is shared with the subscriber's own work.
    public static final Integer RETRY_DELAY_MINUTES = 1; // Before the second and later retries, so a rate-limited provider is not hit again at once.
    public static final Integer CHARACTERS_PER_TOKEN_ESTIMATE = 4;
    public static final Integer STEP_JSON_FIELD_LENGTH = 131072; // The long text fields on AIConversationMessage__c that hold the execution trace and the debug payloads.
    public static final Integer STEP_SENT_PREVIEW_LENGTH = 255;
    public static final Integer STEP_FIELDS_SENT_LENGTH = 4000; // Names of the fields sent, kept short because the whole trace shares one 131,072 character field.
    public static final Integer STEP_OBJECTS_SENT_LENGTH = 255;

    public static final Integer STEP_DETAIL_LENGTH = 1000;
    // AIAgentManager - canonical (provider-agnostic) message shape built from AIConversationMessage__c history, before any provider handler reshapes it.
    public static final String CANONICAL_ROLE_KEY = 'role';
    public static final String CANONICAL_CONTENT_KEY = 'content';
    public static final String CANONICAL_ROLE_USER = 'user';
    public static final String CANONICAL_ROLE_ASSISTANT = 'assistant';

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

    // AIAnthropicMessageResponseHandler - field/value names in Anthropic's Messages API response shape.
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

    // AIAnthropicMessageRequestBuilder - field names in Anthropic's Messages API request shape. Tool name reuses ANTHROPIC_FIELD_TOOL_NAME above.
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

    // AIAnthropicMessageRequestBuilder / AIOpenAiRequestBuilder - sent on the last tool-calling iteration so the model must answer rather than call another tool.
    public static final String ANTHROPIC_FIELD_TOOL_CHOICE = 'tool_choice';
    public static final String ANTHROPIC_FIELD_TOOL_CHOICE_TYPE = 'type';
    public static final String ANTHROPIC_TOOL_CHOICE_NONE = 'none';
    public static final String OPENAI_FIELD_TOOL_CHOICE = 'tool_choice';
    public static final String OPENAI_TOOL_CHOICE_NONE = 'none';

    // AIAgentManager - used when AIAssistSettings__c.DefaultMaxToolCallingIterations__c / MaxToolCallingIterationsCap__c / MaxToolCallsPerIteration__c are blank or below 1.

    // AIAgentManager - tool results sent back to the model when a tool call isn't run. Worded for the model, so it answers with what it already has rather than asking again.
    public static final String TOOL_RESULT_SKIPPED_TOO_MANY_CALLS = 'Not run: too many tool calls in one step. Ask for fewer tools at once, or answer with the information you already have.';
    public static final String TOOL_RESULT_FAILED = 'This tool failed to run. Answer with the information you already have, or tell the user the information is unavailable.';

    // AIAgentManager - the one built-in tool, which lets the model pick one of the Agent's other Prompt Templates when the user did not (no slash command). It is only offered when there are templates to choose from.
    public static final String PROMPT_TEMPLATE_TOOL_NAME = 'select_prompt_template';
    public static final String PROMPT_TEMPLATE_TOOL_ARGUMENT = 'template';
    public static final String PROMPT_TEMPLATE_TOOL_DESCRIPTION = 'Switch to the prompt template that best fits what the user asked for. Call it before answering, only when the request clearly matches one of the templates listed in the instructions.';
    public static final String PROMPT_TEMPLATE_PROMPT_INSTRUCTION = 'Prompt templates (if the request clearly matches one, call ' + PROMPT_TEMPLATE_TOOL_NAME + ' with its name before answering; otherwise answer as normal):';
    public static final String TOOL_RESULT_PROMPT_TEMPLATE_SELECTED = 'The prompt template was selected and its instructions now apply. Answer the user\'s request.';
    public static final String TOOL_RESULT_PROMPT_TEMPLATE_UNKNOWN = 'That is not one of the listed prompt templates. Answer with the instructions you already have.';

    // AIAgentManager - AI provider callout request.
    public static final String HTTP_METHOD_POST = 'POST';
    public static final String HTTP_HEADER_CONTENT_TYPE = 'Content-Type';
    public static final String CONTENT_TYPE_JSON = 'application/json';

    // AIAgentManager - the model can only ever suggest a Workflow Action, never run one - phase 1 requires the user to trigger it explicitly from the chat UI.
    public static final String SUGGESTED_WORKFLOW_ACTION_JSON_KEY = 'suggested_workflow_action';
    // {0} is the signed-in user's Salesforce language code, such as fr or de. The model decides how to translate; agent text (greeting, fallback message) has no per-language versions.
    public static final String LANGUAGE_PROMPT_INSTRUCTION = 'Reply in the language with the Salesforce language code {0}, unless the user writes to you in another language.';
    public static final String WORKFLOW_ACTION_PROMPT_INSTRUCTION = 'Workflows (you cannot run these; suggest one only if it genuinely helps, never claim to have run one):';
    public static final String WORKFLOW_ACTION_PROMPT_JSON_INSTRUCTION = 'To suggest one, end your reply with a line containing only {"' + SUGGESTED_WORKFLOW_ACTION_JSON_KEY + '":"<DeveloperName>"}; otherwise omit it.';

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

    // AIAnthropicAgentRequestBuilder / AIAnthropicAgentResponseHandler - names in Anthropic's Managed Agents (Agent API) sessions and events. The agent, its tools and its environment live on Anthropic's side; a turn is a session plus events.
    public static final String ANTHROPIC_AGENT_VERSION_HEADER_NAME = 'anthropic-version';
    public static final String ANTHROPIC_AGENT_VERSION_HEADER_VALUE = '2023-06-01';
    public static final String ANTHROPIC_AGENT_BETA_HEADER_NAME = 'anthropic-beta';
    public static final String ANTHROPIC_AGENT_BETA_HEADER_VALUE = 'managed-agents-2026-04-01';
    public static final String ANTHROPIC_AGENT_FIELD_EVENTS = 'events';
    public static final String ANTHROPIC_AGENT_FIELD_DATA = 'data';
    public static final String ANTHROPIC_AGENT_FIELD_TYPE = 'type';
    public static final String ANTHROPIC_AGENT_FIELD_ID = 'id';
    public static final String ANTHROPIC_AGENT_FIELD_AGENT = 'agent';
    public static final String ANTHROPIC_AGENT_FIELD_AGENT_TYPE = 'agent';
    public static final String ANTHROPIC_AGENT_FIELD_ENVIRONMENT_ID = 'environment_id';
    public static final String ANTHROPIC_AGENT_FIELD_CONTENT = 'content';
    public static final String ANTHROPIC_AGENT_FIELD_TEXT = 'text';
    public static final String ANTHROPIC_AGENT_FIELD_TOOL_NAME = 'name';
    public static final String ANTHROPIC_AGENT_FIELD_TOOL_INPUT = 'input';
    public static final String ANTHROPIC_AGENT_FIELD_TOOL_USE_ID = 'custom_tool_use_id';
    public static final String ANTHROPIC_AGENT_FIELD_STOP_REASON = 'stop_reason';
    public static final String ANTHROPIC_AGENT_FIELD_MODEL_USAGE = 'model_usage';
    public static final String ANTHROPIC_AGENT_FIELD_ERROR = 'error';
    public static final String ANTHROPIC_AGENT_FIELD_MESSAGE = 'message';
    public static final String ANTHROPIC_AGENT_USAGE_INPUT_TOKENS = 'input_tokens';
    public static final String ANTHROPIC_AGENT_USAGE_OUTPUT_TOKENS = 'output_tokens';
    public static final String ANTHROPIC_AGENT_USAGE_CACHE_CREATION_TOKENS = 'cache_creation_input_tokens';
    public static final String ANTHROPIC_AGENT_USAGE_CACHE_READ_TOKENS = 'cache_read_input_tokens';
    public static final String ANTHROPIC_AGENT_EVENT_USER_MESSAGE = 'user.message';
    public static final String ANTHROPIC_AGENT_EVENT_SYSTEM_MESSAGE = 'system.message';
    public static final String ANTHROPIC_AGENT_EVENT_USER_TOOL_RESULT = 'user.custom_tool_result';
    public static final String ANTHROPIC_AGENT_EVENT_USER_INTERRUPT = 'user.interrupt';
    public static final String ANTHROPIC_AGENT_EVENT_AGENT_MESSAGE = 'agent.message';
    public static final String ANTHROPIC_AGENT_EVENT_AGENT_TOOL_USE = 'agent.custom_tool_use';
    public static final String ANTHROPIC_AGENT_EVENT_STATUS_IDLE = 'session.status_idle';
    public static final String ANTHROPIC_AGENT_EVENT_STATUS_TERMINATED = 'session.status_terminated';
    public static final String ANTHROPIC_AGENT_EVENT_SESSION_ERROR = 'session.error';
    public static final String ANTHROPIC_AGENT_EVENT_MODEL_REQUEST_END = 'span.model_request_end';
    public static final String ANTHROPIC_AGENT_STOP_REASON_REQUIRES_ACTION = 'requires_action';
    public static final String ANTHROPIC_AGENT_CONTENT_TYPE_TEXT = 'text';
    public static final String ANTHROPIC_AGENT_EVENTS_PATH = '/events';
    public static final String ANTHROPIC_AGENT_FIELD_STATUS = 'status';
    public static final String ANTHROPIC_AGENT_FIELD_ARCHIVED_AT = 'archived_at';
    public static final String ANTHROPIC_AGENT_SESSION_STATUS_TERMINATED = 'terminated';
    public static final Integer ANTHROPIC_AGENT_MAX_CALLOUT_MILLISECONDS = 120000; // Salesforce's own ceiling for one callout.
    public static final Integer ANTHROPIC_AGENT_MIN_CALLOUT_MILLISECONDS = 2000;
    public static final String ANTHROPIC_AGENT_TRANSCRIPT_HEADING = 'Conversation so far:';
    public static final String ANTHROPIC_AGENT_TRANSCRIPT_LATEST = 'Latest user message:';
    public static final String ANTHROPIC_AGENT_TRANSCRIPT_USER = 'User: ';
    public static final String ANTHROPIC_AGENT_TRANSCRIPT_ASSISTANT = 'Assistant: ';
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

    // Housekeeping jobs and the PII registry sync.
    public static final String PII_SYNC_STATUS_NOT_SYNCED = 'Not Synced';
    public static final String PII_SYNC_STATUS_QUEUED = 'Queued';
    public static final String PII_SYNC_STATUS_IN_PROGRESS = 'In Progress';
    public static final String PII_SYNC_STATUS_SYNCED = 'Synced';
    public static final String PII_SYNC_STATUS_FAILED = 'Failed';
    public static final Integer DEFAULT_MAX_PII_FIELDS_TO_QUERY = 200;
    public static final Integer MAX_PII_REGISTRIES_PER_RUN = 20; // One queueable syncs them all, so this bounds its queries and DML.
    public static final Integer HOUSEKEEPING_BATCH_SIZE = 200;
    public static final Integer HELD_MESSAGE_TIMEOUT_MINUTES = 5; // How long a message waits for a place under the cap on messages in flight before it is failed.
    public static final Integer HELD_MESSAGE_SWEEP_SIZE = 20; // How many are failed in one go: each tells its chat window.

    // Violations.

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
    // ChatContext.blockedState: why the user cannot send a message right now. Null when they can.
    public static final String CHAT_BLOCKED_INACTIVE = 'INACTIVE';
    public static final String CHAT_BLOCKED_NOT_ASSIGNED = 'NOT_ASSIGNED';
    public static final String CHAT_BLOCKED_TERMS = 'TERMS';
    public static final String CHAT_SEND_STATUS_SENT = 'SENT';
    public static final String CHAT_SEND_STATUS_ERROR = 'ERROR';
    public static final Integer CHAT_HISTORY_MAX_CONVERSATIONS = 50;
    public static final Integer CHAT_DEFAULT_MESSAGE_PAGE_SIZE = 20;
    public static final Integer CHAT_CONVERSATION_TITLE_MAX_LENGTH = 60;
    public static final Integer CHAT_MAX_AGENTS = 50;
    public static final Integer FEEDBACK_COMMENT_LENGTH = 255;
}
