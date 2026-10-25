// Reads the object metadata under force-app and writes site/data/model.json, the data the documentation site draws
// its object reference and ERDs from. Run: node scripts/docs/build-model.mjs
import { readdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const root = new URL('../../', import.meta.url).pathname;
const objectsDir = join(root, 'force-app/main/default/objects');

const DOMAINS = [
  {
    key: 'config',
    title: 'Agent configuration',
    summary: 'What an agent is made of: its model, prompt template, tools and who may use it.',
    objects: ['AIAgent__c', 'AIModelConfiguration__c', 'AIPromptTemplate__c', 'AIPromptTestMessage__c', 'AIDataSource__c', 'AIWorkflowAction__c', 'AIAgentDataSource__c', 'AIAgentWorkflowAction__c', 'AIAgentAssignment__c']
  },
  {
    key: 'conversation',
    title: 'Conversations',
    summary: 'What users say to an agent, what it answers, and the feedback and terms around it.',
    objects: ['AIConversation__c', 'AIConversationMessage__c', 'AIFeedback__c', 'AITermsAcknowledgment__c', 'AIAgent__c', 'AIPromptTemplate__c', 'AIModelConfiguration__c', 'AIWorkflowAction__c']
  },
  {
    key: 'usage',
    title: 'Usage and policies',
    summary: 'Limits live on policies, assigned to users; consumption is counted one row per user per day.',
    objects: ['AIUsagePolicy__c', 'AIUsagePolicyAssignment__c', 'AIUsage__c']
  },
  {
    key: 'pii',
    title: 'PII protection',
    summary: 'The registry of fields to protect, and the pseudonym mappings recorded for each conversation.',
    objects: ['AIPIIRegistry__c', 'AIPIIFieldMetadata__c', 'AIPIIMapping__c', 'AIPIIMaskingRecord__c', 'AIConversation__c', 'AIConversationMessage__c', 'AIPiiComplianceGroup__mdt', 'AIPiiDataMaskingRule__mdt', 'AIPiiFieldType__mdt']
  },
  {
    key: 'platform',
    title: 'Settings and logging',
    summary: 'Org-wide settings, chat commands, and the platform log.',
    objects: ['AIAssistSettings__c', 'AIAssistUISettings__c', 'AIChatCommand__mdt', 'AIPlatformLog__c', 'AIPlatformLogEvent__e']
  }
];
// An object is "owned" by the first domain that lists it; later mentions are shown as context in that diagram.
const owner = {};
for (const d of DOMAINS) for (const o of d.objects) owner[o] ??= d.key;


// Object descriptions are not in the metadata yet, so the site's one-line summaries live here.
const SUMMARY = {
  AIAgent__c: 'An assistant a user can chat with: persona, access mode, conversation limits and retention, tied to a model and a prompt template.',
  AIModelConfiguration__c: 'A connection to an AI provider: named credential, model identifier, temperature and output limits.',
  AIPromptTemplate__c: 'The system prompt an agent answers with, including merge fields. Can be tested with Try It.',
  AIPromptTestMessage__c: 'A saved test message used to try a prompt template.',
  AIDataSource__c: 'A tool that fetches data for the model, e.g. a SOQL template, Apex or Flow.',
  AIWorkflowAction__c: 'A tool that does something on the user\'s behalf, e.g. an Apex action or a Screen Flow.',
  AIAgentDataSource__c: 'Junction: which data sources an agent may call.',
  AIAgentWorkflowAction__c: 'Junction: which workflow actions an agent may suggest.',
  AIAgentAssignment__c: 'Grants a user access to an agent when its access mode is Assigned Users Only.',
  AIConversation__c: 'One chat between a user and an agent. Private to its owner unless shared.',
  AIConversationMessage__c: 'A single message in a conversation, user or assistant, with status, tokens and any suggested action.',
  AIFeedback__c: 'Thumbs up or down, with comments, on an assistant message.',
  AITermsAcknowledgment__c: 'Records that a user accepted the AI terms.',
  AIUsagePolicy__c: 'Limits (messages, tokens) applied to the users it is assigned to.',
  AIUsagePolicyAssignment__c: 'Assigns a usage policy to a user.',
  AIUsage__c: 'Daily consumption for one user: one row per user per day.',
  AIPIIRegistry__c: 'A registry entry for an object whose fields are scanned for PII.',
  AIPIIFieldMetadata__c: 'The PII classification of one field on a registered object.',
  AIPIIMapping__c: 'The pseudonym mapping for a conversation, so replies can be un-masked.',
  AIPIIMaskingRecord__c: 'Audit record of a value masked in a message.',
  AIPiiComplianceGroup__mdt: 'Compliance grouping (e.g. GDPR) for PII field types.',
  AIPiiDataMaskingRule__mdt: 'How a PII field type is masked.',
  AIPiiFieldType__mdt: 'A kind of PII (name, email, phone...) and how it is detected.',
  AIAssistSettings__c: 'Org-wide behaviour settings (hierarchy custom setting).',
  AIAssistUISettings__c: 'Chat window appearance and wording settings (hierarchy custom setting).',
  AIChatCommand__mdt: 'A slash command available in the chat composer.',
  AIPlatformLog__c: 'A persisted log entry written by the platform log manager.',
  AIPlatformLogEvent__e: 'Platform event used to write log entries even when a transaction rolls back.'
};

const tag = (xml, name) => xml.match(new RegExp(`<${name}>([\\s\\S]*?)</${name}>`))?.[1]?.trim();
const clean = (s) => s?.replace(/\s+/g, ' ').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&apos;/g, "'");
const list = (dir, suffix) => (existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith(suffix)) : []);

const kindOf = (name) => (name.endsWith('__mdt') ? 'Custom metadata' : name.endsWith('__e') ? 'Platform event' : 'Custom object');

const objects = {};
for (const name of readdirSync(objectsDir).sort()) {
  const dir = join(objectsDir, name);
  const metaFile = join(dir, `${name}.object-meta.xml`);
  if (!existsSync(metaFile)) continue;
  const meta = readFileSync(metaFile, 'utf8');
  const fields = list(join(dir, 'fields'), '.field-meta.xml').map((f) => {
    const x = readFileSync(join(dir, 'fields', f), 'utf8');
    const type = tag(x, 'type');
    const values = [...x.matchAll(/<value>\s*<fullName>([^<]*)<\/fullName>/g)].map((m) => clean(m[1]));
    return {
      name: f.replace('.field-meta.xml', ''),
      label: clean(tag(x, 'label')),
      type,
      required: tag(x, 'required') === 'true' || type === 'MasterDetail',
      unique: tag(x, 'unique') === 'true',
      externalId: tag(x, 'externalId') === 'true',
      referenceTo: tag(x, 'referenceTo'),
      deleteConstraint: tag(x, 'deleteConstraint'),
      values,
      description: clean(tag(x, 'description'))
    };
  });
  objects[name] = {
    name,
    label: clean(tag(meta, 'label')),
    kind: kindOf(name),
    sharing: tag(meta, 'sharingModel') ?? null,
    description: SUMMARY[name] ?? clean(tag(meta, 'description')) ?? '',
    domain: owner[name] ?? 'platform',
    fields,
    validationRules: list(join(dir, 'validationRules'), '.validationRule-meta.xml').map((f) => f.replace('.validationRule-meta.xml', '')),
    hasTrigger: existsSync(join(root, 'force-app/main/default/triggers', `${name.replace(/__[a-z]+$/, '')}Trigger.trigger`))
  };
}

const relationships = [];
for (const o of Object.values(objects))
  for (const f of o.fields)
    if (f.referenceTo) relationships.push({ from: o.name, to: f.referenceTo, field: f.name, type: f.type, required: f.required });

const out = { generated: new Date().toISOString().slice(0, 10), domains: DOMAINS, objects, relationships };
writeFileSync(join(root, 'site/data/model.json'), JSON.stringify(out, null, 1));
console.log(`${Object.keys(objects).length} objects, ${relationships.length} relationships -> site/data/model.json`);
