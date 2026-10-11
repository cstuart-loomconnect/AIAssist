// Sets up the usage-limit banner test for the running user. Change SCENARIO and run it again to move between cases.
// SCENARIO: NONE | TOKENS_NEW | TOKENS_MESSAGES | TOKENS_NOTIFY | DAILY_CONVERSATIONS | OPEN_CONVERSATIONS
String SCENARIO = 'TOKENS_NEW';

Id userId = UserInfo.getUserId();
String policyTag = 'Usage banner test';

// [1] One test policy, reused on every run
List<AIUsagePolicy__c> policies = [SELECT Id FROM AIUsagePolicy__c WHERE Description__c = :policyTag LIMIT 1];
AIUsagePolicy__c policy = policies.isEmpty() ? new AIUsagePolicy__c(Description__c = policyTag, IsActive__c = true, IsUserInitiatedChatEnabled__c = true) : policies[0];

policy.MaxTokensPer24Hours__c = null;
policy.MaxConversationsPer24Hours__c = null;
policy.MaxConcurrentConversations__c = null;
policy.UsageLimitReachedBehavior__c = 'Block New Conversations Only';

if (SCENARIO == 'TOKENS_NEW' || SCENARIO == 'TOKENS_MESSAGES' || SCENARIO == 'TOKENS_NOTIFY') policy.MaxTokensPer24Hours__c = 100;
if (SCENARIO == 'TOKENS_MESSAGES') policy.UsageLimitReachedBehavior__c = 'Block New Messages';
if (SCENARIO == 'TOKENS_NOTIFY') policy.UsageLimitReachedBehavior__c = 'Notify Only';
if (SCENARIO == 'DAILY_CONVERSATIONS') policy.MaxConversationsPer24Hours__c = 1;
if (SCENARIO == 'OPEN_CONVERSATIONS') policy.MaxConcurrentConversations__c = 1;
upsert policy;

// [2] The user's own setting, with no behaviour of its own so the policy's applies
List<AIUserSettings__c> userSettings = [SELECT Id FROM AIUserSettings__c WHERE User__c = :userId LIMIT 1];
AIUserSettings__c userRow = userSettings.isEmpty() ? new AIUserSettings__c(User__c = userId) : userSettings[0];

if (userRow.Id == null) insert userRow;

// A new row takes the field's default behaviour, so clear it after the insert
userRow.IsActive__c = true;
userRow.UsageLimitReachedBehavior__c = null;
update userRow;

// [3] Assign the policy to the user
if ([SELECT COUNT() FROM AIUsagePolicyAssignment__c WHERE AIUsagePolicy__c = :policy.Id AND User__c = :userId] == 0) insert new AIUsagePolicyAssignment__c(AIUsagePolicy__c = policy.Id, AssigneeType__c = 'User', User__c = userId, IsActive__c = true);

// [4] Set today's tokens: over the limit for the token cases, none otherwise
List<AIUsage__c> usage = [SELECT Id FROM AIUsage__c WHERE User__c = :userId AND UsageDate__c = TODAY LIMIT 1];
Decimal tokens = SCENARIO.startsWith('TOKENS') ? 150 : 0;

if (usage.isEmpty()) insert new AIUsage__c(User__c = userId, UsageDate__c = Date.today(), TokensUsed__c = tokens, ConversationsStarted__c = 0);
else update new AIUsage__c(Id = usage[0].Id, TokensUsed__c = tokens);

System.debug('Scenario ' + SCENARIO + ' set. Limits: ' + AIUsagePolicyService.getUsageLimits(userId));
