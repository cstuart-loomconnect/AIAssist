/*
Class Name: AIChatSaveToRecordServiceTest

=================================================================
=================================================================

Description: Testing utility for AIChatSaveToRecordService: saving an AI reply to the record its conversation is about as a note, a Chatter post or a task, and every refusal.

=================================================================
=================================================================
Applicable Classes:

AIChatSaveToRecordService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIChatSaveToRecordServiceTest {

    // testScenario1: Save a multi-line reply as a note -> a ContentNote titled with the first line, HTML-escaped with line breaks, linked to the record, and the result names it.
    // testScenario2: Save a reply as a Chatter post -> a FeedItem on the record with the confirmed text.
    // testScenario3: Save a reply as a task for an Account and for a Contact -> WhatId for the Account, WhoId for the Contact, owned by the user and Not Started.
    // testScenario4: Save text over each limit -> the note, the post and the task description are cut to their limits, and a blank first line gives the default title.
    // testScenario5: Bad target, blank text, no related record, another user's reply, a reply from the user and a missing Id -> each is refused with its label and nothing is saved.
    // testScenario6: A record the user cannot read, a record with no Chatter feed and a record that cannot take a task -> each is refused with a friendly label and no raw text.
    // testScenario7: A user who can only read the record saves a note -> it is saved with a viewer link, as the user's own sharing allows.

    private static final String AGENT_VISIBILITY_GLOBAL = 'Global';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an account, a conversation about it and an AI reply
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, false)[0];
            conversation.RelatedRecordId__c = account.Id;
            insert conversation;
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            AIChatDataStructure.SaveToRecordResult result;

            // [2] Save an edited, multi-line text as a note
            Test.startTest();
                result = AIChatSaveToRecordService.saveReplyToRecord(reply.Id, AIAssistApplicationConstants.SAVE_TARGET_NOTE, '  First <b>line</b> & more\nSecond line  ');
            Test.stopTest();

            // [3] Read the note and its link
            Id noteId = result.recordId;
            SObject note = Database.query('SELECT Id, Title, Content FROM ContentNote WHERE Id = :noteId');
            List<ContentDocumentLink> links = [SELECT LinkedEntityId, ShareType, Visibility FROM ContentDocumentLink WHERE ContentDocumentId = :noteId AND LinkedEntityId = :account.Id];

            // [4] Check the note, its content and its link
            Assert.areEqual(AIAssistApplicationConstants.SAVE_TARGET_NOTE, result.target, 'The result should name the target.');
            Assert.areEqual(Label.AI_Chat_Save_Target_Note, result.targetLabel, 'The result should carry the target label.');
            Assert.areEqual(Label.AI_Chat_Saved_As_Note, result.message, 'The result should carry the saved message.');
            Assert.areEqual('First <b>line</b> & more', (String) note.get('Title'), 'The title should be the first line of the confirmed text.');
            Assert.areEqual('First &lt;b&gt;line&lt;/b&gt; &amp; more<br>Second line', ((Blob) note.get('Content')).toString(), 'The content should be escaped with line breaks as br.');
            Assert.areEqual(1, links.size(), 'The note should be linked to the record once.');
            Assert.areEqual('V', links[0].ShareType, 'The link should give viewer access.');
            Assert.areEqual('AllUsers', links[0].Visibility, 'The link should be visible to all users.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an account, a conversation about it and an AI reply
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, false)[0];
            conversation.RelatedRecordId__c = account.Id;
            insert conversation;
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            AIChatDataStructure.SaveToRecordResult result;

            // [2] Save the text as a Chatter post
            Test.startTest();
                result = AIChatSaveToRecordService.saveReplyToRecord(reply.Id, AIAssistApplicationConstants.SAVE_TARGET_CHATTER, 'Post this');
            Test.stopTest();

            // [3] Read the post
            FeedItem post = [SELECT ParentId, Body, Type FROM FeedItem WHERE Id = :result.recordId];

            // [4] Check the post and the result
            Assert.areEqual(account.Id, post.ParentId, 'The post should be on the record.');
            Assert.areEqual('Post this', post.Body, 'The post should hold the confirmed text.');
            Assert.areEqual('TextPost', post.Type, 'The post should be a text post.');
            Assert.areEqual(Label.AI_Chat_Saved_As_Chatter, result.message, 'The result should carry the posted message.');
            Assert.areEqual(Label.AI_Chat_Save_Target_Chatter, result.targetLabel, 'The result should carry the target label.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an account and a contact, a conversation about each, and an AI reply in each
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
            Contact contact = new Contact(LastName = 'Task Contact', AccountId = account.Id);
            insert contact;

            AIConversation__c onAccount = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, false)[0];
            onAccount.RelatedRecordId__c = account.Id;
            AIConversation__c onContact = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, false)[0];
            onContact.RelatedRecordId__c = contact.Id;
            insert new List<AIConversation__c>{ onAccount, onContact };

            AIConversationMessage__c accountReply = AIAssistTestDataFactory.createAIConversationMessages(onAccount.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];
            AIConversationMessage__c contactReply = AIAssistTestDataFactory.createAIConversationMessages(onContact.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            AIChatDataStructure.SaveToRecordResult accountResult;
            AIChatDataStructure.SaveToRecordResult contactResult;

            // [2] Save a task for each
            Test.startTest();
                accountResult = AIChatSaveToRecordService.saveReplyToRecord(accountReply.Id, AIAssistApplicationConstants.SAVE_TARGET_TASK, 'Call them back\nAbout the renewal');
                contactResult = AIChatSaveToRecordService.saveReplyToRecord(contactReply.Id, AIAssistApplicationConstants.SAVE_TARGET_TASK, 'Email the contact');
            Test.stopTest();

            // [3] Read the tasks
            Task accountTask = [SELECT WhatId, WhoId, OwnerId, Subject, Description, Status FROM Task WHERE Id = :accountResult.recordId];
            Task contactTask = [SELECT WhatId, WhoId, OwnerId, Subject, Description, Status FROM Task WHERE Id = :contactResult.recordId];

            // [4] Check the account task is about the account and the contact task is for the contact
            Assert.areEqual(account.Id, accountTask.WhatId, 'The account task should be about the account.');
            Assert.isNull(accountTask.WhoId, 'The account task should have no name.');
            Assert.areEqual('Call them back', accountTask.Subject, 'The subject should be the first line.');
            Assert.areEqual('Call them back\nAbout the renewal', accountTask.Description, 'The description should be the whole text.');
            Assert.areEqual(superUser.Id, accountTask.OwnerId, 'The user should own the task.');
            Assert.areEqual('Not Started', accountTask.Status, 'The task should be Not Started.');
            Assert.areEqual(contact.Id, contactTask.WhoId, 'The contact task should be for the contact.');
            Assert.areEqual(Label.AI_Chat_Saved_As_Task, contactResult.message, 'The result should carry the task message.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an account, a conversation about it, an AI reply and over-long text
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, false)[0];
            conversation.RelatedRecordId__c = account.Id;
            insert conversation;
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            String longText = 'x'.repeat(AIAssistApplicationConstants.SAVE_NOTE_BODY_MAX_LENGTH + 50);
            AIChatDataStructure.SaveToRecordResult noteResult;
            AIChatDataStructure.SaveToRecordResult postResult;
            AIChatDataStructure.SaveToRecordResult taskResult;

            // [2] Save the same long text three ways
            Test.startTest();
                noteResult = AIChatSaveToRecordService.saveReplyToRecord(reply.Id, AIAssistApplicationConstants.SAVE_TARGET_NOTE, longText);
                postResult = AIChatSaveToRecordService.saveReplyToRecord(reply.Id, AIAssistApplicationConstants.SAVE_TARGET_CHATTER, longText);
                taskResult = AIChatSaveToRecordService.saveReplyToRecord(reply.Id, AIAssistApplicationConstants.SAVE_TARGET_TASK, longText);
            Test.stopTest();

            // [3] Read what was saved
            Id longNoteId = noteResult.recordId;
            SObject note = Database.query('SELECT Title, Content FROM ContentNote WHERE Id = :longNoteId');
            FeedItem post = [SELECT Body FROM FeedItem WHERE Id = :postResult.recordId];
            Task followUp = [SELECT Subject, Description FROM Task WHERE Id = :taskResult.recordId];

            // [4] Check each was cut to its limit and the title to 80
            Assert.areEqual(AIAssistApplicationConstants.SAVE_NOTE_BODY_MAX_LENGTH, ((Blob) note.get('Content')).size(), 'The note should be cut to its limit.');
            Assert.areEqual(AIAssistApplicationConstants.SAVE_TITLE_MAX_LENGTH, ((String) note.get('Title')).length(), 'The title should be cut to 80.');
            Assert.areEqual(AIAssistApplicationConstants.SAVE_CHATTER_BODY_MAX_LENGTH, post.Body.length(), 'The post should be cut to its limit.');
            Assert.areEqual(AIAssistApplicationConstants.SAVE_TASK_DESCRIPTION_MAX_LENGTH, followUp.Description.length(), 'The description should be cut to its limit.');
            Assert.areEqual(AIAssistApplicationConstants.SAVE_TITLE_MAX_LENGTH, followUp.Subject.length(), 'The subject should be cut to 80.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a conversation about an account, one about no record, another user's, and a reply from the user
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
            AIConversation__c about = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, false)[0];
            about.RelatedRecordId__c = account.Id;
            insert about;
            AIConversation__c noRecord = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];
            User other = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(agent.Id, other.Id, 1, false)[0];
            theirs.RelatedRecordId__c = account.Id;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { insert theirs; }

            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(about.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];
            AIConversationMessage__c userMessage = AIAssistTestDataFactory.createAIConversationMessages(about.Id, AIAssistApplicationConstants.SENDER_USER, 5, 1, true)[0];
            AIConversationMessage__c noRecordReply = AIAssistTestDataFactory.createAIConversationMessages(noRecord.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];
            AIConversationMessage__c theirReply = AIAssistTestDataFactory.createAIConversationMessages(theirs.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            List<String> refusals = new List<String>();

            // [2] Try each save that must be refused
            Test.startTest();
                try { AIChatSaveToRecordService.saveReplyToRecord(reply.Id, 'EMAIL', 'Text'); } catch (AIChatSaveToRecordService.AIChatSaveToRecordServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIChatSaveToRecordService.saveReplyToRecord(reply.Id, null, 'Text'); } catch (AIChatSaveToRecordService.AIChatSaveToRecordServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIChatSaveToRecordService.saveReplyToRecord(reply.Id, AIAssistApplicationConstants.SAVE_TARGET_NOTE, '  \n '); } catch (AIChatSaveToRecordService.AIChatSaveToRecordServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIChatSaveToRecordService.saveReplyToRecord(reply.Id, AIAssistApplicationConstants.SAVE_TARGET_NOTE, null); } catch (AIChatSaveToRecordService.AIChatSaveToRecordServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIChatSaveToRecordService.saveReplyToRecord(noRecordReply.Id, AIAssistApplicationConstants.SAVE_TARGET_NOTE, 'Text'); } catch (AIChatSaveToRecordService.AIChatSaveToRecordServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIChatSaveToRecordService.saveReplyToRecord(theirReply.Id, AIAssistApplicationConstants.SAVE_TARGET_NOTE, 'Text'); } catch (AIChatConversationService.AIChatConversationServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIChatSaveToRecordService.saveReplyToRecord(userMessage.Id, AIAssistApplicationConstants.SAVE_TARGET_NOTE, 'Text'); } catch (AIChatConversationService.AIChatConversationServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIChatSaveToRecordService.saveReplyToRecord(null, AIAssistApplicationConstants.SAVE_TARGET_NOTE, 'Text'); } catch (AIChatConversationService.AIChatConversationServiceException ex) { refusals.add(ex.getMessage()); }
            Test.stopTest();

            // [3] Check each refusal and that nothing was saved
            Assert.areEqual(Label.AI_Error_Save_Target_Invalid, refusals[0], 'An unknown target should be refused.');
            Assert.areEqual(Label.AI_Error_Save_Target_Invalid, refusals[1], 'A missing target should be refused.');
            Assert.areEqual(Label.AI_Error_Save_Text_Empty, refusals[2], 'Blank text should be refused.');
            Assert.areEqual(Label.AI_Error_Save_Text_Empty, refusals[3], 'Missing text should be refused.');
            Assert.areEqual(Label.AI_Error_Save_No_Record, refusals[4], 'A conversation about no record should be refused.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[5], 'Another user\'s reply should be not found.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[6], 'A message from the user should be not found.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[7], 'A missing message should be not found.');
            Assert.areEqual(0, Database.countQuery('SELECT COUNT() FROM ContentNote'), 'No note should have been saved.');
            Assert.areEqual(0, [SELECT COUNT() FROM Task], 'No task should have been saved.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who cannot read another user's private conversation, and a conversation of theirs about it
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);
            AIAssistTestDataFactory.assignPermissionSet(users, AIAssistApplicationConstants.PERMISSION_SET_USER);
            AIConversation__c hidden = AIAssistTestDataFactory.createAIConversations(agent.Id, users[1].Id, 1, true)[0];

            AIConversation__c aboutHidden = AIAssistTestDataFactory.createAIConversations(agent.Id, users[0].Id, 1, false)[0];
            aboutHidden.RelatedRecordId__c = hidden.Id;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { insert aboutHidden; }

            // [2] Create a conversation about an agent record, which has no Chatter feed and takes no tasks
            AIConversation__c aboutAgent = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, false)[0];
            aboutAgent.RelatedRecordId__c = agent.Id;
            insert aboutAgent;

            AIConversationMessage__c hiddenReply = AIAssistTestDataFactory.createAIConversationMessages(aboutHidden.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];
            AIConversationMessage__c agentReply = AIAssistTestDataFactory.createAIConversationMessages(aboutAgent.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            List<String> refusals = new List<String>();

            // [3] Save as the user who cannot read the record, then to the agent record as a post and as a task
            Test.startTest();
                System.runAs(users[0]) {
                    try { AIChatSaveToRecordService.saveReplyToRecord(hiddenReply.Id, AIAssistApplicationConstants.SAVE_TARGET_NOTE, 'Text'); } catch (AIChatSaveToRecordService.AIChatSaveToRecordServiceException ex) { refusals.add(ex.getMessage()); }
                }

                try { AIChatSaveToRecordService.saveReplyToRecord(agentReply.Id, AIAssistApplicationConstants.SAVE_TARGET_CHATTER, 'Text'); } catch (AIChatSaveToRecordService.AIChatSaveToRecordServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIChatSaveToRecordService.saveReplyToRecord(agentReply.Id, AIAssistApplicationConstants.SAVE_TARGET_TASK, 'Text'); } catch (AIChatSaveToRecordService.AIChatSaveToRecordServiceException ex) { refusals.add(ex.getMessage()); }
            Test.stopTest();

            // [4] Check each is refused with a friendly label
            Assert.areEqual(Label.AI_Error_Record_Access_Denied, refusals[0], 'A record the user cannot read should be refused.');
            Assert.areEqual(Label.AI_Error_Save_Chatter_Unavailable, refusals[1], 'A record with no feed should be refused for a post.');
            Assert.areEqual(Label.AI_Error_Save_Failed, refusals[2], 'A record that cannot take a task should give the friendly failure.');
            Assert.areEqual(0, Database.countQuery('SELECT COUNT() FROM ContentNote'), 'No note should have been saved.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who can only read a private record, because it was shared with them Read, and their conversation about it
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);
            AIAssistTestDataFactory.assignPermissionSet(users, AIAssistApplicationConstants.PERMISSION_SET_USER);
            AIConversation__c readOnlyRecord = AIAssistTestDataFactory.createAIConversations(agent.Id, users[1].Id, 1, true)[0];

            System.runAs(AIAssistTestDataFactory.getSetupUser()) {
                insert new AIConversation__Share(ParentId = readOnlyRecord.Id, UserOrGroupId = users[0].Id, AccessLevel = 'Read', RowCause = Schema.AIConversation__Share.RowCause.DirectShare__c);
            }

            AIConversation__c aboutIt = AIAssistTestDataFactory.createAIConversations(agent.Id, users[0].Id, 1, false)[0];
            aboutIt.RelatedRecordId__c = readOnlyRecord.Id;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { insert aboutIt; }

            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(aboutIt.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];
            AIChatDataStructure.SaveToRecordResult result;

            // [2] Save a note about the record the user can only read
            Test.startTest();
                System.runAs(users[0]) {
                    result = AIChatSaveToRecordService.saveReplyToRecord(reply.Id, AIAssistApplicationConstants.SAVE_TARGET_NOTE, 'Text');
                }
            Test.stopTest();

            // [3] Check the note was saved and linked to the record
            Assert.isNotNull(result.recordId, 'The note should be saved.');
            Assert.areEqual(1, [SELECT COUNT() FROM ContentDocumentLink WHERE ContentDocumentId = :result.recordId AND LinkedEntityId = :readOnlyRecord.Id], 'The note should be linked to the record.');
        }
    }
}
