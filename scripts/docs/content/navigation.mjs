// What the site contains: the data-model groups and the user interface screens.
// To document a new screen, add an entry to TABS and run `npm run docs:build`.

// Folder name for each group in site/data-model/ (the keys come from build-model.mjs).
export const DOMAIN_FOLDERS = {
  config: 'agent-configuration',
  conversation: 'conversations',
  usage: 'usage-and-policies',
  pii: 'pii-protection',
  platform: 'settings-and-logging'
};

// lwc / apex: name prefixes used to list the matching components and classes.
export const TABS = [
  { slug: 'chat', title: 'Chat window', lwc: ['aiAssistChat', 'aiChat'], apex: ['AIChat'], objects: ['AIConversation__c', 'AIConversationMessage__c', 'AIFeedback__c', 'AITermsAcknowledgment__c', 'AIUsage__c'],
    blurb: 'Where users talk to an agent, on a record page, the utility bar or mobile. Messages are saved first and answered asynchronously, so the window polls for the reply.',
    notes: ['While a reply is pending the window polls <code>AIChatController.getConversationUpdate</code> with a growing delay, and pauses when the browser tab is hidden.', 'A new reply is detected by a new agent message arriving, so Regenerate and retry keep the old reply visible until the new one is saved.', 'A refused send shows as an error with text from a Custom Label.', 'Screen Flow workflow actions open in a modal and run as the user.'] },
  { slug: 'agent-wizard', title: 'Agent Wizard', lwc: ['aiAgentWizard'], apex: ['AIAgentWizard'], objects: ['AIAgent__c', 'AIAgentDataSource__c', 'AIAgentWorkflowAction__c', 'AIAgentAssignment__c'],
    blurb: 'A step-by-step builder to create, copy and edit agents: basics, model, tools, access, limits, conversation behaviour and a review.',
    notes: ['Links to data sources and workflow actions default to inactive and the runtime reads only active links, so the wizard sets them active.', 'Access Mode defaults to Assigned Users Only; a user must also have an active usage policy to send messages.'] },
  { slug: 'models', title: 'AI Models', lwc: ['aiModels'], apex: ['AIModels'], objects: ['AIModelConfiguration__c', 'AIAgent__c'],
    blurb: 'Manage connections to AI providers. A model is only switched on after a test message succeeds.',
    notes: ['The connection test runs the real chat path with a stand-in agent and a small token cap, so it works for every provider.', 'Switching a model off requires each active agent using it to be moved to another active model.'] },
  { slug: 'prompt-templates', title: 'Prompt Templates', lwc: ['aiPromptTemplates'], apex: ['AIPromptTemplates', 'AIPromptTemplateService', 'AIPromptMergeFieldService'], objects: ['AIPromptTemplate__c', 'AIPromptTestMessage__c'],
    blurb: 'Write, publish, archive and try out the system prompts that agents answer with, including merge fields.', notes: ['Try It sends saved test messages through the template and shows the result.', 'Used By lists the agents and conversations relying on a template.'] },
  { slug: 'ai-tools', title: 'AI Tools', lwc: ['aiTools'], apex: ['AITools', 'AISoqlTemplate', 'AIDataSource', 'AIWorkflowAction'], objects: ['AIDataSource__c', 'AIWorkflowAction__c', 'AIAgentDataSource__c', 'AIAgentWorkflowAction__c'],
    blurb: 'Data sources (information the model can fetch) and workflow actions (things it can suggest or do), each built with a guided wizard and tested before use.',
    notes: ['Each data source and workflow action records its last test result and time.', '"Run as" another user is a field-access check from that user\'s permission sets, not real impersonation.', 'A SOQL template with no LIMIT gets one added (warning); a LIMIT over 200 is an error.'] },
  { slug: 'policies', title: 'AI Policies', lwc: ['aiPolicies'], apex: ['AIPolicies', 'AIUsage'], objects: ['AIUsagePolicy__c', 'AIUsagePolicyAssignment__c', 'AIUsage__c'],
    blurb: 'Usage limits live on policies; a policy is assigned to users, and a check-a-user tool shows what applies to someone.', notes: ['Limits are read from the policy only. Per-user behaviour on reaching a limit stays on user settings.'] },
  { slug: 'pii-registry', title: 'PII Registry', lwc: ['aiPiiRegistry'], apex: ['AIPiiRegistry', 'AIPiiField', 'AIPiiPseudonymization'], objects: ['AIPIIRegistry__c', 'AIPIIFieldMetadata__c', 'AIPIIMapping__c', 'AIPIIMaskingRecord__c'],
    blurb: 'Choose which objects are scanned, review how each field is classified, test masking, and see unprotected fields.',
    notes: ['A manual override on a field is kept when the sync worker re-classifies; Reset re-classifies it.', 'A registry whose Active box is off stops masking.', 'A registry fails (and is retried) when an object has more fields than its Max Fields To Query.'] },
  { slug: 'settings', title: 'AI Assist Settings', lwc: ['aiAssistSettings'], apex: ['AIAssistSettings'], objects: ['AIAssistSettings__c', 'AIAssistUISettings__c'],
    blurb: 'Org-wide behaviour and appearance settings, with Org-wide, Profile and User levels.', notes: ['Only five limits can be overridden below org level: message length, messages per minute and three tool-calling numbers.', 'Editing requires the AIAssistManageSettings custom permission.'] }
];
