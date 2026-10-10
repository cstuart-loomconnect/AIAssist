/*
Class Name: AIAssistUserTriggerHandler

=================================================================
=================================================================

Description: Runs the business logic for the User trigger: keeps each user's AIUserSettings__c in step with whether the user is active.

Step 1: After a user is created or reactivated, start a background job that creates or reactivates their settings
Step 2: After a user is deactivated, start a background job that deactivates their settings
Step 3: The background jobs save the settings and log any failures

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAssistUserTriggerHandler {

    public class AIAssistUserTriggerHandlerException extends Exception {}

    // Creates default settings for users who have none, and reactivates the settings of users who have inactive ones. It runs in the background because a User cannot be saved in the same transaction as the settings.
    public class InitialiseAIAssistUserQueueable implements Queueable {

        private Set<Id> userIds;

        public InitialiseAIAssistUserQueueable(Set<Id> userIds) {
            this.userIds = userIds;
        }

        public void execute(QueueableContext context) {

            try {

                // [1] Nothing to do - no users
                if (userIds == null || userIds.isEmpty()) return;

                // [2] Find the settings these users already have
                Map<Id, AIUserSettings__c> existingSettingsByUserId = new Map<Id, AIUserSettings__c>();

                for (AIUserSettings__c existingSettings : [SELECT Id, User__c, IsActive__c FROM AIUserSettings__c WHERE User__c IN :userIds WITH SYSTEM_MODE]) {

                    existingSettingsByUserId.put(existingSettings.User__c, existingSettings);
                }

                // [3] Build default settings for users with none, and mark inactive settings active
                List<AIUserSettings__c> settingsToInsert = new List<AIUserSettings__c>();
                List<AIUserSettings__c> settingsToReactivate = new List<AIUserSettings__c>();

                for (Id userId : userIds) {

                    AIUserSettings__c existingSettings = existingSettingsByUserId.get(userId);

                    if (existingSettings == null) {

                        settingsToInsert.add(AIAssistUserDefaults.build(new User(Id = userId)));

                    } else if (!existingSettings.IsActive__c) {

                        existingSettings.IsActive__c = true;
                        settingsToReactivate.add(existingSettings);
                    }
                }

                // [4] Save the new settings and log any failures
                if (!settingsToInsert.isEmpty()) {

                    List<Database.SaveResult> insertResults = Database.insert(settingsToInsert, false, AccessLevel.SYSTEM_MODE);
                    AIPlatformLogManager.logExceptions(insertResults, 'AIAssistUserTriggerHandler', 'InitialiseAIAssistUserQueueable');
                }

                // [5] Save the reactivated settings and log any failures
                if (!settingsToReactivate.isEmpty()) {

                    List<Database.SaveResult> updateResults = Database.update(settingsToReactivate, false, AccessLevel.SYSTEM_MODE);
                    AIPlatformLogManager.logExceptions(updateResults, 'AIAssistUserTriggerHandler', 'InitialiseAIAssistUserQueueable');
                }

            } catch (Exception ex) {
                AIPlatformLogManager.logException(ex, 'AIAssistUserTriggerHandler', 'InitialiseAIAssistUserQueueable');
            }
        }
    }

    // Marks the settings of deactivated users inactive. The rows are kept so they can be reactivated later.
    public class DeactivateAIAssistUserQueueable implements Queueable {

        private Set<Id> userIds;

        public DeactivateAIAssistUserQueueable(Set<Id> userIds) {
            this.userIds = userIds;
        }

        public void execute(QueueableContext context) {

            try {

                // [1] Nothing to do - no users
                if (userIds == null || userIds.isEmpty()) return;

                // [2] Find the active settings of these users
                List<AIUserSettings__c> settingsToDeactivate = [SELECT Id, IsActive__c FROM AIUserSettings__c WHERE User__c IN :userIds AND IsActive__c = true WITH SYSTEM_MODE];

                // [3] Mark each one inactive
                for (AIUserSettings__c settings : settingsToDeactivate) {

                    settings.IsActive__c = false;
                }

                // [4] Save them and log any failures
                if (!settingsToDeactivate.isEmpty()) {

                    List<Database.SaveResult> updateResults = Database.update(settingsToDeactivate, false, AccessLevel.SYSTEM_MODE);
                    AIPlatformLogManager.logExceptions(updateResults, 'AIAssistUserTriggerHandler', 'DeactivateAIAssistUserQueueable');
                }

            } catch (Exception ex) {
                AIPlatformLogManager.logException(ex, 'AIAssistUserTriggerHandler', 'DeactivateAIAssistUserQueueable');
            }
        }
    }

    @TestVisible
    private static Boolean isTestCustomExceptionThrown = false;

    // Starts the background job that gives each new active user their default settings.
    public static void handleAfterInsert(Map<Id, User> newUsersById) {

        try {

            // [1] Nothing to do - no users
            if (newUsersById == null || newUsersById.isEmpty()) return;

            // [2] Throw on purpose when a test asks for it
            if (isTestCustomExceptionThrown) throw new AIAssistUserTriggerHandlerException('Test exception for AIAssistUserTriggerHandler.handleAfterInsert');

            // [3] Keep the users who are active
            Set<Id> activeUserIds = new Set<Id>();

            for (User newUser : newUsersById.values()) {

                if (newUser.IsActive) activeUserIds.add(newUser.Id);
            }

            // [4] Start the job that creates their settings
            if (!activeUserIds.isEmpty() && isQueueableRunnable()) System.enqueueJob(new InitialiseAIAssistUserQueueable(activeUserIds));

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIAssistUserTriggerHandler', 'handleAfterInsert');
        }
    }

    // Starts the background jobs that reactivate the settings of reactivated users and deactivate the settings of deactivated users.
    public static void handleAfterUpdate(Map<Id, User> oldUsersById, Map<Id, User> newUsersById) {

        try {

            // [1] Nothing to do - no users
            if (oldUsersById == null || oldUsersById.isEmpty() || newUsersById == null || newUsersById.isEmpty()) return;

            // [2] Throw on purpose when a test asks for it
            if (isTestCustomExceptionThrown) throw new AIAssistUserTriggerHandlerException('Test exception for AIAssistUserTriggerHandler.handleAfterUpdate');

            // [3] Sort the users whose active flag changed into reactivated and deactivated
            Set<Id> reactivatedUserIds = new Set<Id>();
            Set<Id> deactivatedUserIds = new Set<Id>();

            for (User newUser : newUsersById.values()) {

                User oldUser = oldUsersById.get(newUser.Id);

                if (oldUser == null || oldUser.IsActive == newUser.IsActive) continue;

                if (newUser.IsActive) reactivatedUserIds.add(newUser.Id);
                else deactivatedUserIds.add(newUser.Id);
            }

            // [4] Start the job that reactivates settings
            if (!reactivatedUserIds.isEmpty() && isQueueableRunnable()) System.enqueueJob(new InitialiseAIAssistUserQueueable(reactivatedUserIds));

            // [5] Start the job that deactivates settings
            if (!deactivatedUserIds.isEmpty() && isQueueableRunnable()) System.enqueueJob(new DeactivateAIAssistUserQueueable(deactivatedUserIds));

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIAssistUserTriggerHandler', 'handleAfterUpdate');
        }
    }

    // Whether another background job can be started from here.
    private static Boolean isQueueableRunnable() {

        try {

            // [1] A future method cannot start a background job
            if (System.isFuture()) return false;

            Integer queueableJobsUsed = Limits.getQueueableJobs();

            // [2] From a batch or another background job, only one more job is allowed
            if (System.isBatch() || System.isQueueable()) return queueableJobsUsed < 1;

            // [3] Anywhere else, use the normal limit
            return queueableJobsUsed < Limits.getLimitQueueableJobs();

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIAssistUserTriggerHandler', 'isQueueableRunnable');
            return false;
        }
    }
}
