/*
Class Name: AIChatStateServiceTest

=================================================================
=================================================================

Description: Testing utility for AIChatStateService: the UI settings, what a user may do from their usage policy, channel and terms state.

=================================================================
=================================================================
Applicable Classes:

AIChatStateService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIChatStateServiceTest {

    // testScenario1: Build UI settings from a configured record and an empty one -> the configured values are used and the empty one gets the defaults.
    // testScenario2: Build the user state with no policy, then with the UI settings on, then off -> no policy grants nothing, the UI settings drive Workflow Actions, the policy drives debug, export and new chats.
    // testScenario3: Check a channel with no policy, no channel, a listed channel and an unlisted channel -> allowed unless the channel is not on the list.
    // testScenario4: Build the terms state unsigned, signed and with no version configured -> required only while the configured version is unsigned.
    // testScenario5: Set the blocked state for a ready user, inactive app, no agent and terms to accept -> each is named with its message and a ready user is not blocked.
    // testScenario6: A user covered by the default policy, then with every policy off, then with a policy assigned to them -> full use, none with the no access refusal, and full use.
    // testScenario7: Set the blocked state for a user with no access -> it is named with its message.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a configured UI settings record
            AIAssistUISettings__c ui = new AIAssistUISettings__c(ShowTimestampOnMessages__c = true, IsFeedbackEnabled__c = false, SuggestedActionsDisplay__c = AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS, MaxVisibleMessageHistory__c = 7);

            AIChatDataStructure.UiSettings configured;
            AIChatDataStructure.UiSettings defaults;

            // [2] Build the UI settings from the configured record and from an empty one
            Test.startTest();
                configured = AIChatStateService.buildUiSettings(ui);
                defaults = AIChatStateService.buildUiSettings(new AIAssistUISettings__c());
            Test.stopTest();

            // [3] Check the configured values are used and the empty record gets the defaults
            Assert.isTrue(configured.showTimestamps, 'Timestamps should follow the setting.');
            Assert.isFalse(configured.feedbackEnabled, 'Feedback should be off when the setting is false.');

            Assert.areEqual(AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS, configured.suggestedActionsDisplay, 'Inline buttons should be used when asked for.');

            Assert.areEqual(7, configured.messagePageSize, 'The configured page size should be used.');
            Assert.areEqual(AIAssistApplicationConstants.CHAT_DEFAULT_MESSAGE_PAGE_SIZE, defaults.messagePageSize, 'The default page size should be used when none is set.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a usage policy with debug and export enabled, and one with new chats turned off
            AIUsagePolicy__c policy = new AIUsagePolicy__c(IsActive__c = true, DebugModeEnabled__c = true, ConversationExportEnabled__c = true, IsUserInitiatedChatEnabled__c = true);
            AIUsagePolicy__c pausedPolicy = new AIUsagePolicy__c(IsActive__c = true, IsUserInitiatedChatEnabled__c = false);

            AIChatDataStructure.UserState none;
            AIChatDataStructure.UserState full;
            AIChatDataStructure.UserState off;
            AIChatDataStructure.UserState paused;

            // [2] Build the user state with no policy, then with Workflow Actions on, then off, and with a policy that turns new chats off
            Test.startTest();
                none = AIChatStateService.buildUserState(null);

                AIAssistTestDataFactory.upsertUiSettings(true);
                full = AIChatStateService.buildUserState(policy);

                AIAssistTestDataFactory.upsertUiSettings(false);
                off = AIChatStateService.buildUserState(policy);
                paused = AIChatStateService.buildUserState(pausedPolicy);
            Test.stopTest();

            // [3] Check what each state grants
            Assert.isFalse(none.debugMode || none.exportEnabled || none.workflowActionsEnabled || none.newChatsDisabled, 'A user with no policy and no UI settings should have nothing, and may start new chats.');
            Assert.isTrue(full.debugMode && full.exportEnabled && full.workflowActionsEnabled, 'The UI settings and a policy with debug and export should grant everything.');
            Assert.isFalse(full.newChatsDisabled, 'A policy that allows new chats should not disable them.');

            Assert.isFalse(off.workflowActionsEnabled, 'Workflow Actions should follow the UI settings.');
            Assert.isTrue(off.debugMode && off.exportEnabled, 'Debug mode and export should follow the user\'s policy.');
            Assert.isTrue(paused.newChatsDisabled, 'New chats should be disabled when the user\'s policy turns them off.');

            Assert.areEqual(UserInfo.getUserId(), none.userId, 'The state should be for the signed-in user.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a usage policy that allows only the mobile channel
            AIUsagePolicy__c policy = new AIUsagePolicy__c(AllowedChannels__c = AIAssistApplicationConstants.CHANNEL_MOBILE);

            Boolean noPolicy;
            Boolean noChannel;
            Boolean listed;
            Boolean unlisted;

            // [2] Check a channel with no policy, no channel, a listed channel and an unlisted channel
            Test.startTest();
                noPolicy = AIChatStateService.isChannelAllowed(null, AIAssistApplicationConstants.CHANNEL_UTILITY_BAR);
                noChannel = AIChatStateService.isChannelAllowed(policy, null);
                listed = AIChatStateService.isChannelAllowed(policy, AIAssistApplicationConstants.CHANNEL_MOBILE);
                unlisted = AIChatStateService.isChannelAllowed(policy, AIAssistApplicationConstants.CHANNEL_UTILITY_BAR);
            Test.stopTest();

            // [3] Check a channel is allowed unless it is not on the list
            Assert.isTrue(noPolicy, 'A channel should be allowed when the user has no policy.');
            Assert.isTrue(noChannel, 'A missing channel should be allowed.');

            Assert.isTrue(listed, 'A channel on the list should be allowed.');
            Assert.isFalse(unlisted, 'A channel not on the list should not be allowed.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Configure a current terms version and policy link
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.CurrentTermsVersion__c = 'v3';
            settings.AIUsagePolicyUrl__c = 'https://example.com/policy';

            AIChatDataStructure.TermsState unsigned;
            AIChatDataStructure.TermsState signed;
            AIChatDataStructure.TermsState none;

            // [2] Build the terms state unsigned, then signed, then with no version configured
            Test.startTest();
                unsigned = AIChatStateService.buildTermsState(settings);

                insert AIAssistTestDataFactory.createAITermsAcknowledgments(UserInfo.getUserId(), 'v3', 1, false);
                signed = AIChatStateService.buildTermsState(settings);

                settings.CurrentTermsVersion__c = null;
                none = AIChatStateService.buildTermsState(settings);
            Test.stopTest();

            // [3] Check the terms are required only while the configured version is unsigned
            Assert.isTrue(unsigned.required, 'The terms should be required until the version is signed.');
            Assert.areEqual('https://example.com/policy', unsigned.policyUrl, 'The policy link should be passed on.');

            Assert.isFalse(signed.required, 'The terms should not be required once signed.');

            Assert.isFalse(none.required, 'The terms should not be required when none are configured.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Load the settings and build the contexts for each state
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();

            AIChatDataStructure.ChatContext notBlocked = new AIChatDataStructure.ChatContext();
            notBlocked.state = AIAssistApplicationConstants.CHAT_STATE_READY;

            AIChatDataStructure.ChatContext inactive = new AIChatDataStructure.ChatContext();
            inactive.state = AIAssistApplicationConstants.CHAT_STATE_INACTIVE;

            AIChatDataStructure.ChatContext notAssigned = new AIChatDataStructure.ChatContext();
            notAssigned.state = AIAssistApplicationConstants.CHAT_STATE_NO_AGENT;

            AIChatDataStructure.ChatContext termsContext = new AIChatDataStructure.ChatContext();
            termsContext.state = AIAssistApplicationConstants.CHAT_STATE_TERMS;
            termsContext.terms = new AIChatDataStructure.TermsState();
            termsContext.terms.required = true;

            // [2] Set the blocked state for a ready user, an inactive app, no agent and terms to accept
            Test.startTest();
                AIChatStateService.setBlockedState(notBlocked);

                settings.IsEnabled__c = false;
                System.runAs(AIAssistTestDataFactory.getSetupUser()) {

                    update settings;
                }
                AIAssistSettingsService.cachedSettings = null;
                AIChatStateService.setBlockedState(inactive);

                settings.IsEnabled__c = true;
                System.runAs(AIAssistTestDataFactory.getSetupUser()) {

                    update settings;
                }
                AIAssistSettingsService.cachedSettings = null;

                AIChatStateService.setBlockedState(notAssigned);
                AIChatStateService.setBlockedState(termsContext);
            Test.stopTest();

            // [3] Check each blocked state and message
            Assert.isNull(notBlocked.blockedState, 'A ready user should not be blocked.');

            Assert.areEqual(AIAssistApplicationConstants.CHAT_BLOCKED_INACTIVE, inactive.blockedState, 'A switched-off application should block the user.');
            Assert.areEqual(Label.AI_Error_Application_Inactive, inactive.blockedMessage, 'The inactive state should carry its message.');

            Assert.areEqual(AIAssistApplicationConstants.CHAT_BLOCKED_NOT_ASSIGNED, notAssigned.blockedState, 'A user with no agent should be blocked as not assigned.');

            Assert.areEqual(AIAssistApplicationConstants.CHAT_BLOCKED_TERMS, termsContext.blockedState, 'A user with terms to accept should be blocked.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Note the access the default policy gives, then switch every policy off
            String withDefault;
            String withNone;
            String withAssigned;
            String noAccessRefusal;

            Test.startTest();
                withDefault = AIChatStateService.getAccessLevel();

                // [2] With every policy off the user has no access and is refused
                AIAssistTestDataFactory.deactivateUsagePolicies();
                withNone = AIChatStateService.getAccessLevel();

                try {

                    AIChatStateService.requireAccess();

                } catch (AIChatStateService.AIChatStateServiceException ex) {
                    noAccessRefusal = ex.getMessage();
                }

                // [3] A policy assigned to the user gives full use again
                AIAssistTestDataFactory.createAIUsagePolicyForUser(superUser.Id, null, null, null, null);
                withAssigned = AIChatStateService.getAccessLevel();
            Test.stopTest();

            // [4] Check each outcome
            Assert.areEqual(AIAssistApplicationConstants.ACCESS_LEVEL_FULL, withDefault, 'The default policy should give full use.');
            Assert.areEqual(AIAssistApplicationConstants.ACCESS_LEVEL_NONE, withNone, 'No policy should give none.');
            Assert.areEqual(Label.AI_Error_No_Access, noAccessRefusal, 'Reading with no policy should be refused with the no access label.');
            Assert.areEqual(AIAssistApplicationConstants.ACCESS_LEVEL_FULL, withAssigned, 'A policy assigned to the user should give full use.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a context for a user with no access
            AIChatDataStructure.ChatContext noAccess = new AIChatDataStructure.ChatContext();
            noAccess.state = AIAssistApplicationConstants.CHAT_STATE_NO_ACCESS;

            // [2] Set the blocked state
            Test.startTest();
                AIChatStateService.setBlockedState(noAccess);
            Test.stopTest();

            // [3] Check it is named with its message
            Assert.areEqual(AIAssistApplicationConstants.CHAT_BLOCKED_NO_ACCESS, noAccess.blockedState, 'A user with no access should be blocked as such.');
            Assert.areEqual(Label.AI_Error_No_Access, noAccess.blockedMessage, 'The no access state should carry its message.');
        }
    }
}
