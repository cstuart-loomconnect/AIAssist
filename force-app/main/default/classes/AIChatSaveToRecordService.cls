/*
Class Name: AIChatSaveToRecordService

=================================================================
=================================================================

Description: Saves the text of an AI reply, as the user confirmed it, to the record the conversation is about.

Step 1: Check the target, that the user owns the reply, that the conversation is about a record the user can read, and that there is text
Step 2: Cut the text to the limit for the target
Step 3: Save it as a note, a Chatter post or a task, in user mode so the user's own permissions and sharing decide
Step 4: Turn any save failure into a friendly Custom Label, and return what was created

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIChatSaveToRecordService {

    public class AIChatSaveToRecordServiceException extends Exception {}

    // Saves the text to the record the reply's conversation is about. The text is what the user confirmed in the window, which they may have edited.
    public static AIChatDataStructure.SaveToRecordResult saveReplyToRecord(Id messageId, String target, String text) {

        // [1] Refuse a target that is not a note, a Chatter post or a task
        Set<String> targets = new Set<String>{ AIAssistApplicationConstants.SAVE_TARGET_NOTE, AIAssistApplicationConstants.SAVE_TARGET_CHATTER, AIAssistApplicationConstants.SAVE_TARGET_TASK };
        if (target == null || !targets.contains(target)) throw new AIChatSaveToRecordServiceException(Label.AI_Error_Save_Target_Invalid);

        // [2] Check the user owns the reply, and that its conversation is about a record
        AIConversationMessage__c reply = AIChatConversationService.getOwnedAgentMessage(messageId);
        Id recordId = AIChatDataStructure.getIdOrNull(reply.AIConversation__r.RelatedRecordId__c);
        if (recordId == null) throw new AIChatSaveToRecordServiceException(Label.AI_Error_Save_No_Record);

        // [3] Refuse a record the user cannot read
        List<AIConversation__c> aboutRecord = new List<AIConversation__c>{ new AIConversation__c(RelatedRecordId__c = String.valueOf(recordId)) };
        if (AIConversationVisibilityService.filterReadableRecords(aboutRecord).isEmpty()) throw new AIChatSaveToRecordServiceException(Label.AI_Error_Record_Access_Denied);

        // [4] Refuse blank text
        String trimmedText = text == null ? '' : text.trim();
        if (String.isBlank(trimmedText)) throw new AIChatSaveToRecordServiceException(Label.AI_Error_Save_Text_Empty);

        // [5] Save it for the target, and tell the user what was created
        AIChatDataStructure.SaveToRecordResult result = new AIChatDataStructure.SaveToRecordResult();
        result.target = target;

        try {

            if (target == AIAssistApplicationConstants.SAVE_TARGET_NOTE) {

                result.recordId = saveNote(recordId, trimmedText.left(AIAssistApplicationConstants.SAVE_NOTE_BODY_MAX_LENGTH));
                result.targetLabel = Label.AI_Chat_Save_Target_Note;
                result.message = Label.AI_Chat_Saved_As_Note;
            } else if (target == AIAssistApplicationConstants.SAVE_TARGET_CHATTER) {

                result.recordId = saveChatterPost(recordId, trimmedText.left(AIAssistApplicationConstants.SAVE_CHATTER_BODY_MAX_LENGTH));
                result.targetLabel = Label.AI_Chat_Save_Target_Chatter;
                result.message = Label.AI_Chat_Saved_As_Chatter;
            } else {

                result.recordId = saveTask(recordId, trimmedText);
                result.targetLabel = Label.AI_Chat_Save_Target_Task;
                result.message = Label.AI_Chat_Saved_As_Task;
            }

        } catch (AIChatSaveToRecordServiceException ex) {

            // [6] Pass on a refusal, which is already a Custom Label
            throw ex;
        } catch (Exception ex) {

            // [7] Log what went wrong once, and show the user a friendly label rather than the raw text
            AIPlatformLogManager.logException(ex, 'AIChatSaveToRecordService', 'saveReplyToRecord');
            throw new AIChatSaveToRecordServiceException(Label.AI_Error_Save_Failed);
        }

        // [8] Return the result
        return result;
    }

    // A note on the record: the note first, then its link to the record. Both are undone if either fails. Notes are read from the schema, because an org that has not switched Notes on has no ContentNote object and the package must still install there.
    private static Id saveNote(Id recordId, String text) {

        // [1] Refuse when the org has no Notes
        Schema.SObjectType noteType = Schema.getGlobalDescribe().get('ContentNote');
        if (noteType == null) throw new AIChatSaveToRecordServiceException(Label.AI_Error_Save_Notes_Unavailable);

        // [2] Build the note, titled with the first line, with the text as HTML so line breaks survive
        SObject note = noteType.newSObject();
        note.put('Title', getFirstLine(text, Label.AI_Chat_Note_Default_Title));
        note.put('Content', Blob.valueOf(text.escapeHtml4().replaceAll('\r\n|\r|\n', '<br>')));
        Savepoint beforeNote = Database.setSavepoint();

        try {

            // [3] Save the note, then link it to the record
            Database.insert(note, AccessLevel.USER_MODE);
            Database.insert(new ContentDocumentLink(ContentDocumentId = note.Id, LinkedEntityId = recordId, ShareType = AIAssistApplicationConstants.CONTENT_LINK_SHARE_TYPE_VIEWER, Visibility = AIAssistApplicationConstants.CONTENT_LINK_VISIBILITY_ALL_USERS), AccessLevel.USER_MODE);

        } catch (Exception ex) {

            // [4] Leave no note without a link behind
            Database.rollback(beforeNote);
            throw ex;
        }

        return note.Id;
    }

    // A Chatter text post on the record, when the record's object has feeds switched on.
    private static Id saveChatterPost(Id recordId, String text) {

        // [1] Refuse a record whose object has no Chatter feed
        if (!recordId.getSobjectType().getDescribe().isFeedEnabled()) throw new AIChatSaveToRecordServiceException(Label.AI_Error_Save_Chatter_Unavailable);

        // [2] Save the post
        FeedItem post = new FeedItem(ParentId = recordId, Type = AIAssistApplicationConstants.FEED_ITEM_TYPE_TEXT_POST, Body = text);
        Database.insert(post, AccessLevel.USER_MODE);

        return post.Id;
    }

    // A task owned by the user: about the record, or for the person when the record is a Contact or a Lead.
    private static Id saveTask(Id recordId, String text) {

        // [1] Build the task, titled with the first line
        Task followUp = new Task(OwnerId = UserInfo.getUserId(), Subject = getFirstLine(text, Label.AI_Chat_Task_Default_Subject), Description = text.left(AIAssistApplicationConstants.SAVE_TASK_DESCRIPTION_MAX_LENGTH), Status = AIAssistApplicationConstants.TASK_STATUS_NOT_STARTED);

        // [2] A Contact or a Lead is a Name on a task, and anything else is what the task is about
        Schema.SObjectType recordType = recordId.getSobjectType();

        if (recordType == Contact.SObjectType || recordType == Lead.SObjectType) followUp.WhoId = recordId;
        else followUp.WhatId = recordId;

        // [3] Save it
        Database.insert(followUp, AccessLevel.USER_MODE);

        return followUp.Id;
    }

    // The first line of the text cut to the title length, or the default when that line is blank.
    private static String getFirstLine(String text, String defaultTitle) {

        // [1] Take the first line that has anything on it
        for (String line : text.split('\r\n|\r|\n')) {

            if (String.isNotBlank(line)) return line.trim().left(AIAssistApplicationConstants.SAVE_TITLE_MAX_LENGTH);
        }

        // [2] Fall back to the default
        return defaultTitle;
    }
}
