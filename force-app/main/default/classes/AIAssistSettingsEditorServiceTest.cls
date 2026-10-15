/*
Class Name: AIAssistSettingsEditorServiceTest

=================================================================
=================================================================

Description: Testing utility for AIAssistSettingsEditorService: reading, checking, saving and deleting the rows the Settings tab edits.

=================================================================
=================================================================
Applicable Classes:

AIAssistSettingsEditorService: Coverage TBC
AIAssistSettingsService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIAssistSettingsEditorServiceTest {

    // testScenario1: A manager reads the settings page -> the organisation row is first on both lists and holds the saved and default values.
    // testScenario2: A user without the Manage Settings permission reads the page -> the access label is shown.
    // testScenario3: A manager saves valid organisation values -> the row is saved and the service reads the new values.
    // testScenario4: A manager clears a required number -> it is refused as required.
    // testScenario5: A manager saves a number outside its range, a decimal and letters -> each is refused with the range message.
    // testScenario6: A manager saves an iteration cap below the default -> it is refused.
    // testScenario7: A manager saves a status code list with a bad code -> it is refused, and a spaced list is tidied.
    // testScenario8: A manager saves a user row with the five overridable limits -> the service gives that user the row's limits and everyone else the organisation's.
    // testScenario9: A manager saves a user row with a field that is about the whole org, or a cleared tool-calling number -> each is refused.
    // testScenario10: A manager saves a profile row, then a row with no owner -> the profile row is saved and the missing owner is refused.
    // testScenario11: A manager saves a UI settings user row and an invalid suggested actions choice -> the row is used by getUiSettings and the choice is refused.
    // testScenario12: A manager deletes a user row and tries to delete the organisation row -> the user row is gone and the organisation row is refused.
    // testScenario13: A manager searches profiles and users -> short text finds nothing, a profile name and a user name each find a match, and another scope is refused.
    // testScenario14: A manager saves an unknown field and an unknown settings name -> both are refused.
    // testScenario15: A required number is cleared in Setup -> the service gives it the default instead of failing.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Read the page
            Test.startTest();
                AIAssistSettingsDataStructure.SettingsPage page = AIAssistSettingsEditorService.getSettingsPage();
            Test.stopTest();

            // [2] Check the organisation row comes first and holds the saved and default values
            Assert.areEqual(AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION, page.assistRows[0].scope, 'The organisation row is first for AI Assist Settings.');
            Assert.areEqual(AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION, page.uiRows[0].scope, 'The organisation row is first for AI Assist UI Settings.');
            Assert.areEqual(true, page.assistRows[0].values.get('IsEnabled__c'), 'The saved switch is on.');
            Assert.areEqual(true, page.uiRows[0].values.get('IsFeedbackEnabled__c'), 'With no UI row the default-on switch reads as on.');
            Assert.isNotNull(page.assistRows[0].rowId, 'The organisation row was saved by the test setup.');
            Assert.isNull(page.uiRows[0].rowId, 'The UI organisation row has never been saved.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');

            // [2] Read the page as that user
            String refusal;

            Test.startTest();
                System.runAs(users[0]) {
                    try {

                        AIAssistSettingsEditorService.getSettingsPage();

                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {
                        refusal = ex.getMessage();
                    }
                }
            Test.stopTest();

            // [3] Check the user was refused
            Assert.areEqual(Label.AI_Settings_Error_Access, refusal, 'A user without the Manage Settings permission is refused.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Save valid organisation values
            Map<String, Object> assistValues = new Map<String, Object>{
                'IsEnabled__c' => true,
                'MaxMessageLength__c' => 4000,
                'MaxMessagesPerUserPerMinute__c' => 10,
                'MaxMessagesInFlight__c' => 50,
                'ProcessingLockSeconds__c' => 300,
                'CalloutTimeoutMilliseconds__c' => 60000,
                'RetryAttempts__c' => 3,
                'RetryableStatusCodes__c' => '429,503',
                'AIProviderSuccessStatusCodes__c' => '200',
                'DefaultMaxToolCallingIterations__c' => 4,
                'MaxToolCallingIterationsCap__c' => 10,
                'MaxToolCallsPerIteration__c' => 6
            };

            Test.startTest();
                AIAssistSettingsDataStructure.SettingsRow savedRow = AIAssistSettingsEditorService.saveRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION, null, assistValues);
            Test.stopTest();

            // [2] Read the settings the service now gives
            AIAssistSettings__c settings = AIAssistSettingsService.getSettings();

            // [3] Check the values were saved and the cache was dropped
            Assert.areEqual(4000, savedRow.values.get('MaxMessageLength__c'), 'The saved row holds the new message length.');
            Assert.areEqual(300, settings.ProcessingLockSeconds__c, 'The service reads the new lock time.');
            Assert.areEqual(60000, settings.CalloutTimeoutMilliseconds__c, 'The service reads the new timeout.');
            Assert.areEqual('429,503', settings.RetryableStatusCodes__c, 'The service reads the new retryable codes.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Clear a required number
            Map<String, Object> values = new Map<String, Object>{
                'IsEnabled__c' => true,
                'MaxMessageLength__c' => 4000,
                'MaxMessagesPerUserPerMinute__c' => 10,
                'MaxMessagesInFlight__c' => 50,
                'ProcessingLockSeconds__c' => 300,
                'CalloutTimeoutMilliseconds__c' => 60000,
                'RetryAttempts__c' => 3,
                'RetryableStatusCodes__c' => '429,503',
                'AIProviderSuccessStatusCodes__c' => '200',
                'DefaultMaxToolCallingIterations__c' => 4,
                'MaxToolCallingIterationsCap__c' => 10,
                'MaxToolCallsPerIteration__c' => 6
            };
            values.put('ProcessingLockSeconds__c', null);

            String refusal;

            Test.startTest();
                try {

                    AIAssistSettingsEditorService.saveRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION, null, values);

                } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                    refusal = ex.getMessage();
                }
            Test.stopTest();

            // [2] Check it was refused as required
            Assert.isNotNull(refusal, 'A cleared required number is refused.');
            Assert.isTrue(refusal.contains('is required'), 'The message says the number is required.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Try a timeout below its range, a decimal and letters
            Map<String, Object> tooLow = new Map<String, Object>{
                'IsEnabled__c' => true,
                'MaxMessageLength__c' => 4000,
                'MaxMessagesPerUserPerMinute__c' => 10,
                'MaxMessagesInFlight__c' => 50,
                'ProcessingLockSeconds__c' => 300,
                'CalloutTimeoutMilliseconds__c' => 60000,
                'RetryAttempts__c' => 3,
                'RetryableStatusCodes__c' => '429,503',
                'AIProviderSuccessStatusCodes__c' => '200',
                'DefaultMaxToolCallingIterations__c' => 4,
                'MaxToolCallingIterationsCap__c' => 10,
                'MaxToolCallsPerIteration__c' => 6
            };
            tooLow.put('CalloutTimeoutMilliseconds__c', 500);
            Map<String, Object> decimalValue = new Map<String, Object>{
                'IsEnabled__c' => true,
                'MaxMessageLength__c' => 4000,
                'MaxMessagesPerUserPerMinute__c' => 10,
                'MaxMessagesInFlight__c' => 50,
                'ProcessingLockSeconds__c' => 300,
                'CalloutTimeoutMilliseconds__c' => 60000,
                'RetryAttempts__c' => 3,
                'RetryableStatusCodes__c' => '429,503',
                'AIProviderSuccessStatusCodes__c' => '200',
                'DefaultMaxToolCallingIterations__c' => 4,
                'MaxToolCallingIterationsCap__c' => 10,
                'MaxToolCallsPerIteration__c' => 6
            };
            decimalValue.put('RetryAttempts__c', 1.5);
            Map<String, Object> letters = new Map<String, Object>{
                'IsEnabled__c' => true,
                'MaxMessageLength__c' => 4000,
                'MaxMessagesPerUserPerMinute__c' => 10,
                'MaxMessagesInFlight__c' => 50,
                'ProcessingLockSeconds__c' => 300,
                'CalloutTimeoutMilliseconds__c' => 60000,
                'RetryAttempts__c' => 3,
                'RetryableStatusCodes__c' => '429,503',
                'AIProviderSuccessStatusCodes__c' => '200',
                'DefaultMaxToolCallingIterations__c' => 4,
                'MaxToolCallingIterationsCap__c' => 10,
                'MaxToolCallsPerIteration__c' => 6
            };
            letters.put('MaxMessagesInFlight__c', 'many');

            String tooLowRefusal;
            String decimalRefusal;
            String lettersRefusal;

            Test.startTest();
                try {

                    AIAssistSettingsEditorService.saveRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION, null, tooLow);

                } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                    tooLowRefusal = ex.getMessage();
                }
                try {

                    AIAssistSettingsEditorService.saveRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION, null, decimalValue);

                } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                    decimalRefusal = ex.getMessage();
                }
                try {

                    AIAssistSettingsEditorService.saveRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION, null, letters);

                } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                    lettersRefusal = ex.getMessage();
                }
            Test.stopTest();

            // [2] Check each was refused with the range message
            Assert.isTrue(tooLowRefusal != null && tooLowRefusal.contains('whole number from 2000 to 120000'), 'A timeout below the minimum is refused with its range.');
            Assert.isTrue(decimalRefusal != null && decimalRefusal.contains('whole number'), 'A decimal is refused.');
            Assert.isTrue(lettersRefusal != null && lettersRefusal.contains('whole number'), 'Letters are refused.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Set the cap below the default
            Map<String, Object> values = new Map<String, Object>{
                'IsEnabled__c' => true,
                'MaxMessageLength__c' => 4000,
                'MaxMessagesPerUserPerMinute__c' => 10,
                'MaxMessagesInFlight__c' => 50,
                'ProcessingLockSeconds__c' => 300,
                'CalloutTimeoutMilliseconds__c' => 60000,
                'RetryAttempts__c' => 3,
                'RetryableStatusCodes__c' => '429,503',
                'AIProviderSuccessStatusCodes__c' => '200',
                'DefaultMaxToolCallingIterations__c' => 4,
                'MaxToolCallingIterationsCap__c' => 10,
                'MaxToolCallsPerIteration__c' => 6
            };
            values.put('DefaultMaxToolCallingIterations__c', 8);
            values.put('MaxToolCallingIterationsCap__c', 5);

            String refusal;

            Test.startTest();
                try {

                    AIAssistSettingsEditorService.saveRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION, null, values);

                } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                    refusal = ex.getMessage();
                }
            Test.stopTest();

            // [2] Check it was refused
            Assert.areEqual(Label.AI_Settings_Error_Cap_Below_Default, refusal, 'A cap below the default is refused.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Try a bad code, then a list with spaces
            Map<String, Object> badCode = new Map<String, Object>{
                'IsEnabled__c' => true,
                'MaxMessageLength__c' => 4000,
                'MaxMessagesPerUserPerMinute__c' => 10,
                'MaxMessagesInFlight__c' => 50,
                'ProcessingLockSeconds__c' => 300,
                'CalloutTimeoutMilliseconds__c' => 60000,
                'RetryAttempts__c' => 3,
                'RetryableStatusCodes__c' => '429,503',
                'AIProviderSuccessStatusCodes__c' => '200',
                'DefaultMaxToolCallingIterations__c' => 4,
                'MaxToolCallingIterationsCap__c' => 10,
                'MaxToolCallsPerIteration__c' => 6
            };
            badCode.put('RetryableStatusCodes__c', '429,abc');
            Map<String, Object> spaced = new Map<String, Object>{
                'IsEnabled__c' => true,
                'MaxMessageLength__c' => 4000,
                'MaxMessagesPerUserPerMinute__c' => 10,
                'MaxMessagesInFlight__c' => 50,
                'ProcessingLockSeconds__c' => 300,
                'CalloutTimeoutMilliseconds__c' => 60000,
                'RetryAttempts__c' => 3,
                'RetryableStatusCodes__c' => '429,503',
                'AIProviderSuccessStatusCodes__c' => '200',
                'DefaultMaxToolCallingIterations__c' => 4,
                'MaxToolCallingIterationsCap__c' => 10,
                'MaxToolCallsPerIteration__c' => 6
            };
            spaced.put('RetryableStatusCodes__c', ' 408, 429 ,503 ');

            String badCodeRefusal;

            Test.startTest();
                try {

                    AIAssistSettingsEditorService.saveRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION, null, badCode);

                } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                    badCodeRefusal = ex.getMessage();
                }
                AIAssistSettingsDataStructure.SettingsRow spacedRow = AIAssistSettingsEditorService.saveRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION, null, spaced);
            Test.stopTest();

            // [2] Check the bad code was refused and the spaced list was tidied
            Assert.isTrue(badCodeRefusal != null && badCodeRefusal.contains('100 to 599'), 'A code that is not a number is refused.');
            Assert.areEqual('408,429,503', spacedRow.values.get('RetryableStatusCodes__c'), 'Spaces are removed from the list.');
        }
    }

    @IsTest static void testScenario8() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Save the organisation row, then a row for the user
            Map<String, Object> overrideValues = new Map<String, Object>{
                'MaxMessageLength__c' => 1000,
                'MaxMessagesPerUserPerMinute__c' => 2,
                'DefaultMaxToolCallingIterations__c' => 2,
                'MaxToolCallingIterationsCap__c' => 3,
                'MaxToolCallsPerIteration__c' => 1
            };

            Map<String, Object> assistValues = new Map<String, Object>{
                'IsEnabled__c' => true,
                'MaxMessageLength__c' => 4000,
                'MaxMessagesPerUserPerMinute__c' => 10,
                'MaxMessagesInFlight__c' => 50,
                'ProcessingLockSeconds__c' => 300,
                'CalloutTimeoutMilliseconds__c' => 60000,
                'RetryAttempts__c' => 3,
                'RetryableStatusCodes__c' => '429,503',
                'AIProviderSuccessStatusCodes__c' => '200',
                'DefaultMaxToolCallingIterations__c' => 4,
                'MaxToolCallingIterationsCap__c' => 10,
                'MaxToolCallsPerIteration__c' => 6
            };

            AIAssistSettingsEditorService.saveRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION, null, assistValues);
            List<User> otherUsers = AIAssistTestDataFactory.createUsers(1, true);

            Test.startTest();
                AIAssistSettingsDataStructure.SettingsRow userRow = AIAssistSettingsEditorService.saveRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, AIAssistApplicationConstants.SETTINGS_SCOPE_USER, superUser.Id, overrideValues);
            Test.stopTest();

            // [2] Read the settings for the user, and for someone else
            AIAssistSettings__c settingsForUser = AIAssistSettingsService.getSettings();
            AIAssistSettingsService.clearCache();
            AIAssistSettings__c settingsForOther;

            System.runAs(otherUsers[0]) {
                settingsForOther = AIAssistSettingsService.getSettings();
            }

            // [3] Check the user got the row's limits, the org-wide numbers stayed, and the other user got the organisation's
            Assert.areEqual(AIAssistApplicationConstants.SETTINGS_SCOPE_USER, userRow.scope, 'The saved row is a user row.');
            Assert.areEqual(1000, settingsForUser.MaxMessageLength__c, 'The user gets the row message length.');
            Assert.areEqual(3, settingsForUser.MaxToolCallingIterationsCap__c, 'The user gets the row cap.');
            Assert.areEqual(60000, settingsForUser.CalloutTimeoutMilliseconds__c, 'The org-wide timeout is not overridden.');
            Assert.areEqual(4000, settingsForOther.MaxMessageLength__c, 'Another user gets the organisation message length.');
        }
    }

    @IsTest static void testScenario9() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Try a whole-org field on a user row, and a user row with no tool-calling numbers
            Map<String, Object> wholeOrgField = new Map<String, Object>{
                'MaxMessageLength__c' => 1000,
                'MaxMessagesPerUserPerMinute__c' => 2,
                'DefaultMaxToolCallingIterations__c' => 2,
                'MaxToolCallingIterationsCap__c' => 3,
                'MaxToolCallsPerIteration__c' => 1
            };
            wholeOrgField.put('CalloutTimeoutMilliseconds__c', 5000);
            Map<String, Object> noToolNumbers = new Map<String, Object>{
                'MaxMessageLength__c' => 500,
                'MaxToolCallsPerIteration__c' => null
            };
            String wholeOrgRefusal;
            String missingRefusal;

            Test.startTest();
                try {

                    AIAssistSettingsEditorService.saveRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, AIAssistApplicationConstants.SETTINGS_SCOPE_USER, superUser.Id, wholeOrgField);

                } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                    wholeOrgRefusal = ex.getMessage();
                }
                try {

                    AIAssistSettingsEditorService.saveRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, AIAssistApplicationConstants.SETTINGS_SCOPE_USER, superUser.Id, noToolNumbers);

                } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                    missingRefusal = ex.getMessage();
                }
            Test.stopTest();

            // [2] Check both were refused
            Assert.isTrue(wholeOrgRefusal != null && wholeOrgRefusal.contains('cannot be set on this row'), 'A whole-org field cannot be set on a user row.');
            Assert.isTrue(missingRefusal != null && missingRefusal.contains('is required'), 'A user row must hold the tool-calling numbers.');
        }
    }

    @IsTest static void testScenario10() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Save a row for the user's profile, and one with no owner
            Map<String, Object> overrideValues = new Map<String, Object>{
                'MaxMessageLength__c' => 1000,
                'MaxMessagesPerUserPerMinute__c' => 2,
                'DefaultMaxToolCallingIterations__c' => 2,
                'MaxToolCallingIterationsCap__c' => 3,
                'MaxToolCallsPerIteration__c' => 1
            };

            String noOwnerRefusal;

            Test.startTest();
                AIAssistSettingsDataStructure.SettingsRow profileRow = AIAssistSettingsEditorService.saveRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, AIAssistApplicationConstants.SETTINGS_SCOPE_PROFILE, UserInfo.getProfileId(), overrideValues);

                try {

                    AIAssistSettingsEditorService.saveRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, AIAssistApplicationConstants.SETTINGS_SCOPE_PROFILE, null, overrideValues);

                } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                    noOwnerRefusal = ex.getMessage();
                }
            Test.stopTest();

            // [2] Read the page back
            AIAssistSettingsDataStructure.SettingsPage page = AIAssistSettingsEditorService.getSettingsPage();

            // [3] Check the profile row was saved and listed, and the missing owner refused
            Assert.areEqual(AIAssistApplicationConstants.SETTINGS_SCOPE_PROFILE, profileRow.scope, 'The saved row is a profile row.');
            Assert.areEqual(2, page.assistRows.size(), 'The page lists the organisation row and the profile row.');
            Assert.areEqual(AIAssistApplicationConstants.SETTINGS_SCOPE_PROFILE, page.assistRows[1].scope, 'The profile row follows the organisation row.');
            Assert.areEqual(Label.AI_Settings_Error_Owner, noOwnerRefusal, 'A profile row with no profile is refused.');
        }
    }

    @IsTest static void testScenario11() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Save a UI row for the user that turns feedback off, and try a bad suggested actions choice
            Map<String, Object> goodValues = new Map<String, Object>{
                'IsFeedbackEnabled__c' => false,
                'SuggestedActionsDisplay__c' => AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS,
                'MaxVisibleMessageHistory__c' => 30
            };
            Map<String, Object> badChoice = new Map<String, Object>{'SuggestedActionsDisplay__c' => 'Popups'};
            String choiceRefusal;

            Test.startTest();
                AIAssistSettingsEditorService.saveRow(AIAssistApplicationConstants.SETTINGS_NAME_UI, AIAssistApplicationConstants.SETTINGS_SCOPE_USER, superUser.Id, goodValues);

                try {

                    AIAssistSettingsEditorService.saveRow(AIAssistApplicationConstants.SETTINGS_NAME_UI, AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION, null, badChoice);

                } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                    choiceRefusal = ex.getMessage();
                }
            Test.stopTest();

            // [2] Read the UI settings the chat window would use
            AIAssistUISettings__c uiSettings = AIAssistSettingsService.getUiSettings();

            // [3] Check the user row is used and the bad choice refused
            Assert.areEqual(false, uiSettings.IsFeedbackEnabled__c, 'The user row turns feedback off.');
            Assert.areEqual(30, uiSettings.MaxVisibleMessageHistory__c, 'The user row sets the page size.');
            Assert.isTrue(choiceRefusal != null && choiceRefusal.contains('not allowed'), 'A suggested actions display that is not a choice is refused.');
        }
    }

    @IsTest static void testScenario12() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Save a user row, then delete it, and try to delete the organisation row
            Map<String, Object> overrideValues = new Map<String, Object>{
                'MaxMessageLength__c' => 1000,
                'MaxMessagesPerUserPerMinute__c' => 2,
                'DefaultMaxToolCallingIterations__c' => 2,
                'MaxToolCallingIterationsCap__c' => 3,
                'MaxToolCallsPerIteration__c' => 1
            };

            AIAssistSettingsDataStructure.SettingsRow userRow = AIAssistSettingsEditorService.saveRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, AIAssistApplicationConstants.SETTINGS_SCOPE_USER, superUser.Id, overrideValues);
            Id organisationRowId = AIAssistSettingsEditorService.getSettingsPage().assistRows[0].rowId;
            String organisationRefusal;
            String missingRefusal;

            Test.startTest();
                AIAssistSettingsEditorService.deleteRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, userRow.rowId);

                try {

                    AIAssistSettingsEditorService.deleteRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, organisationRowId);

                } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {
                    organisationRefusal = ex.getMessage();
                }

                try {

                    AIAssistSettingsEditorService.deleteRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, userRow.rowId);

                } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {
                    missingRefusal = ex.getMessage();
                }
            Test.stopTest();

            // [2] Read the page back
            AIAssistSettingsDataStructure.SettingsPage page = AIAssistSettingsEditorService.getSettingsPage();

            // [3] Check only the organisation row is left, and both refusals were shown
            Assert.areEqual(1, page.assistRows.size(), 'Only the organisation row is left.');
            Assert.areEqual(Label.AI_Settings_Error_Org_Row_Delete, organisationRefusal, 'The organisation row cannot be deleted.');
            Assert.areEqual(Label.AI_Settings_Error_Row_Not_Found, missingRefusal, 'A deleted row is not found.');
        }
    }

    @IsTest static void testScenario13() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Search with too little text, a profile name, a user name and a bad scope
            String refusal;

            Test.startTest();
                List<AIAssistSettingsDataStructure.OwnerOption> shortResults = AIAssistSettingsEditorService.findOwners(AIAssistApplicationConstants.SETTINGS_SCOPE_PROFILE, 'S');
                List<AIAssistSettingsDataStructure.OwnerOption> profileResults = AIAssistSettingsEditorService.findOwners(AIAssistApplicationConstants.SETTINGS_SCOPE_PROFILE, 'Standard User');
                List<AIAssistSettingsDataStructure.OwnerOption> userResults = AIAssistSettingsEditorService.findOwners(AIAssistApplicationConstants.SETTINGS_SCOPE_USER, 'Assist Tester');

                try {

                    AIAssistSettingsEditorService.findOwners('Team', 'Standard');

                } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {
                    refusal = ex.getMessage();
                }
            Test.stopTest();

            // [2] Check each answer
            Assert.isTrue(shortResults.isEmpty(), 'One letter is too little to search.');
            Assert.isFalse(profileResults.isEmpty(), 'The Standard User profile is found.');
            Assert.isFalse(userResults.isEmpty(), 'The test user is found by name.');
            Assert.isNotNull(userResults[0].detail, 'A user result shows the username.');
            Assert.areEqual(Label.AI_Settings_Error_Owner, refusal, 'A scope other than Profile or User is refused.');
        }
    }

    @IsTest static void testScenario14() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Save a field the tab does not know, then an unknown settings name
            String fieldRefusal;
            String nameRefusal;

            Test.startTest();
                try {

                    AIAssistSettingsEditorService.saveRow(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST, AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION, null, new Map<String, Object>{'Name' => 'Hacked'});

                } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                    fieldRefusal = ex.getMessage();
                }
                try {

                    AIAssistSettingsEditorService.saveRow('Account', AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION, null, new Map<String, Object>());

                } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                    nameRefusal = ex.getMessage();
                }
            Test.stopTest();

            // [2] Check each was refused
            Assert.isTrue(fieldRefusal != null && fieldRefusal.contains('cannot be set on this row'), 'A field the tab does not list is refused.');
            Assert.areEqual(Label.AI_Settings_Error_Settings_Name, nameRefusal, 'An unknown settings name is refused.');
        }
    }

    @IsTest static void testScenario15() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Clear every required number straight on the row, as Setup allows
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.ProcessingLockSeconds__c = null;
            settings.CalloutTimeoutMilliseconds__c = null;
            settings.RetryAttempts__c = null;
            settings.DefaultMaxToolCallingIterations__c = null;
            settings.MaxToolCallingIterationsCap__c = null;
            settings.MaxToolCallsPerIteration__c = null;

            System.runAs(AIAssistTestDataFactory.getSetupUser()) {

                update settings;
            }

            // [2] Read the settings through the service
            AIAssistSettingsService.clearCache();

            Test.startTest();
                AIAssistSettings__c readSettings = AIAssistSettingsService.getSettings();
            Test.stopTest();

            // [3] Check each number has its default
            Assert.areEqual(AIAssistApplicationConstants.SETTINGS_DEFAULT_PROCESSING_LOCK_SECONDS, readSettings.ProcessingLockSeconds__c, 'A blank lock time gets its default.');
            Assert.areEqual(AIAssistApplicationConstants.SETTINGS_DEFAULT_CALLOUT_TIMEOUT_MILLISECONDS, readSettings.CalloutTimeoutMilliseconds__c, 'A blank timeout gets its default.');
            Assert.areEqual(AIAssistApplicationConstants.SETTINGS_DEFAULT_RETRY_ATTEMPTS, readSettings.RetryAttempts__c, 'A blank retry count gets its default.');
            Assert.areEqual(AIAssistApplicationConstants.SETTINGS_DEFAULT_MAX_TOOL_CALLING_ITERATIONS, readSettings.DefaultMaxToolCallingIterations__c, 'A blank default iteration count gets its default.');
            Assert.areEqual(AIAssistApplicationConstants.SETTINGS_DEFAULT_TOOL_CALLING_ITERATIONS_CAP, readSettings.MaxToolCallingIterationsCap__c, 'A blank cap gets its default.');
            Assert.areEqual(AIAssistApplicationConstants.SETTINGS_DEFAULT_MAX_TOOL_CALLS_PER_ITERATION, readSettings.MaxToolCallsPerIteration__c, 'A blank tool calls number gets its default.');
        }
    }
}
