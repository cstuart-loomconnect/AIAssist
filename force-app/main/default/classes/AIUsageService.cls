/*
Class Name: AIUsageService

=================================================================
=================================================================

Description: Keeps what each user has used of AI Assist today on one AIUsage__c record per user, and reads it back for the limits and the chat window.

Step 1: Work out today's date in the org's time zone
Step 2: Lock the users' records and start again any that belong to an earlier day
Step 3: Add the new tokens and conversations, and create a record for a user who has none
Step 4: Read back today's tokens and conversations for a user

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIUsageService {

    public class AIUsageServiceException extends Exception {}

    // What to add to one user's usage for today.
    public class UsageToAdd {
        public Decimal tokens = 0;
        public Decimal inputTokens = 0;
        public Decimal outputTokens = 0;
        public Decimal conversations = 0;
    }

    private static String orgTimeZone;

    // A test sets the day, so it can move to the next one without waiting for midnight.
    @TestVisible
    private static Date todayForTest;

    // Today's date in the org's time zone, because the day a limit resets on is the org's day and not the running user's.
    public static Date getToday() {

        // [1] Use the day a test set, if there is one
        if (todayForTest != null) return todayForTest;

        // [2] Look up the org's time zone once
        if (orgTimeZone == null) orgTimeZone = [SELECT TimeZoneSidKey FROM Organization LIMIT 1].TimeZoneSidKey;

        // [3] Read the date as it is in that time zone right now
        return Date.valueOf(System.now().format('yyyy-MM-dd', orgTimeZone));
    }

    // Adds tokens and conversations to each user's usage for today. A record from an earlier day is started again first. Never blocks the work it describes.
    public static void addUsage(Map<Id, UsageToAdd> additionsByUserId) {

        try {

            // [1] Nothing to add
            if (additionsByUserId == null || additionsByUserId.isEmpty()) return;

            // [2] Lock the users' records, so two transactions add to each other instead of overwriting
            Date today = getToday();
            Set<Id> userIds = additionsByUserId.keySet();
            Map<Id, AIUsage__c> usageByUserId = new Map<Id, AIUsage__c>();

            for (AIUsage__c usage : [SELECT Id, User__c, UsageDate__c, TokensUsed__c, InputTokens__c, OutputTokens__c, ConversationsStarted__c FROM AIUsage__c WHERE User__c IN :userIds WITH SYSTEM_MODE FOR UPDATE]) {

                if (!usageByUserId.containsKey(usage.User__c)) usageByUserId.put(usage.User__c, usage);
            }

            // [3] Find the users' own settings records, to link a new usage record to
            Map<Id, Id> settingsIdByUserId = new Map<Id, Id>();

            for (AIUserSettings__c settings : [SELECT Id, User__c FROM AIUserSettings__c WHERE User__c IN :userIds WITH SYSTEM_MODE]) {

                settingsIdByUserId.put(settings.User__c, settings.Id);
            }

            // [4] Work out the new totals for each user
            List<AIUsage__c> toInsert = new List<AIUsage__c>();
            List<AIUsage__c> toUpdate = new List<AIUsage__c>();

            for (Id userId : userIds) {

                UsageToAdd addition = additionsByUserId.get(userId);
                AIUsage__c existing = usageByUserId.get(userId);

                // [5] A record from an earlier day, or no record at all, starts from zero
                Boolean isToday = existing != null && existing.UsageDate__c == today;
                Decimal tokens = isToday ? valueOrZero(existing.TokensUsed__c) : 0;
                Decimal inputTokens = isToday ? valueOrZero(existing.InputTokens__c) : 0;
                Decimal outputTokens = isToday ? valueOrZero(existing.OutputTokens__c) : 0;
                Decimal conversations = isToday ? valueOrZero(existing.ConversationsStarted__c) : 0;

                AIUsage__c changed = new AIUsage__c(Id = existing?.Id, UsageDate__c = today, TokensUsed__c = tokens + addition.tokens, InputTokens__c = inputTokens + addition.inputTokens, OutputTokens__c = outputTokens + addition.outputTokens, ConversationsStarted__c = conversations + addition.conversations);

                // [6] Update the record the user has, or create one linked to their settings
                if (existing == null) {

                    changed.User__c = userId;
                    changed.AIUserSettings__c = settingsIdByUserId.get(userId);
                    toInsert.add(changed);

                } else {

                    toUpdate.add(changed);
                }
            }

            // [7] Save the changes and log any that fail
            AIMessagingDataService.insertAndLogFailures(toInsert, 'AIUsageService', 'addUsage');
            AIMessagingDataService.updateAndLogFailures(toUpdate, 'AIUsageService', 'addUsage');

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIUsageService', 'addUsage');
        }
    }

    // The tokens the user has used today. Zero when they have no record for today.
    public static Decimal getTokensUsedToday(Id userId) {

        // [1] Read today's usage and return its tokens
        AIUsage__c usage = getUsageToday(userId);

        return usage == null || usage.TokensUsed__c == null ? 0 : usage.TokensUsed__c;
    }

    // The conversations the user has started today. Zero when they have no record for today.
    public static Integer getConversationsStartedToday(Id userId) {

        // [1] Read today's usage and return its conversations
        AIUsage__c usage = getUsageToday(userId);

        return usage == null || usage.ConversationsStarted__c == null ? 0 : Integer.valueOf(usage.ConversationsStarted__c);
    }

    // The user's usage record when it belongs to today, else null. A record from an earlier day is not today's usage. It must see the user's record whoever asks, so the class runs without sharing.
    private static AIUsage__c getUsageToday(Id userId) {

        // [1] Nothing to look up
        if (userId == null) return null;

        // [2] Find the record, if any, that belongs to today
        Date today = getToday();
        List<AIUsage__c> usageRows = [SELECT Id, TokensUsed__c, ConversationsStarted__c FROM AIUsage__c WHERE User__c = :userId AND UsageDate__c = :today WITH SYSTEM_MODE ORDER BY Id LIMIT 1];

        return usageRows.isEmpty() ? null : usageRows[0];
    }

    // A counter that has never been set is zero.
    private static Decimal valueOrZero(Decimal counter) {

        // [1] Return the counter, or zero when it is blank
        return counter == null ? 0 : counter;
    }
}
