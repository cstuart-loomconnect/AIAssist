/*
Class Name: AIDataDeletionBatch

=================================================================
=================================================================

Description: Carries out an approved AIDataDeletionRequest__c. Runs in system mode because no user holds Delete
on these objects and the request, not the caller, is the authority. It will not run unless the request
is Approved (the four-eyes rule is enforced on the record, and checked again here).

For the subject (a user's conversations, or the conversations about one record) it:
[1] Conversations phase: skips conversations on legal hold and counts them; for the rest it removes the
    person and detail from any violations (violations are audit records, so they are anonymised, not
    deleted), deletes the feedback, counts the messages, and deletes the conversations. Messages, steps,
    masking records and PII mappings go with their conversation.
[2] Violations phase (user requests): anonymises the user's remaining violations.
[3] Usage phase (user requests): anonymises the user's daily usage rows, which are kept for cost
    reporting without the person.
Each phase adds its counts to the request, and the last one stamps the request Completed. Any failure
marks it Failed with the reason; the record never holds the deleted content.

Phases are chained from finish, so each handles any volume in batches of DATA_DELETION_BATCH_SIZE.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development. Implements the deletion action the security model describes.
*/

public inherited sharing class AIDataDeletionBatch implements Database.Batchable<SObject>, Database.Stateful {
  public static final String PHASE_CONVERSATIONS = 'Conversations';
  public static final String PHASE_VIOLATIONS = 'Violations';
  public static final String PHASE_USAGE = 'Usage';

  private Id requestId;
  private String phase;
  private AIDataDeletionRequest__c deletionRequest;
  private String failureDetail;
  private Decimal conversationsDeleted = 0;
  private Decimal messagesDeleted = 0;
  private Decimal feedbackDeleted = 0;
  private Decimal conversationsSkipped = 0;
  private Decimal violationsAnonymised = 0;
  private Decimal usageRowsAnonymised = 0;

  public AIDataDeletionBatch(Id requestId, String phase) {
    this.requestId = requestId;
    this.phase = phase;
  }

  // Starts the first phase of an approved request. Refuses one that is not approved; does nothing for one already running or finished.
  public static Id startApprovedRequest(Id requestId) {
    List<AIDataDeletionRequest__c> requests = [
      SELECT Id, ApprovalDecision__c, Status__c
      FROM AIDataDeletionRequest__c
      WHERE Id = :requestId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (
      requests.isEmpty() ||
      requests[0].ApprovalDecision__c !=
      AIAssistApplicationConstants.DELETION_DECISION_APPROVED
    ) {
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_DELETION_NOT_APPROVED,
        Label.AI_Error_Data_Deletion_Not_Approved
      );
    }

    if (
      requests[0].Status__c !=
      AIAssistApplicationConstants.DELETION_STATUS_APPROVED
    )
      return null;

    // Marked now, not when the first chunk runs, so a second call before the batch starts cannot start it twice.
    AIMessagingDataService.updateAsPackage(
      new List<SObject>{
        new AIDataDeletionRequest__c(
          Id = requestId,
          Status__c = AIAssistApplicationConstants.DELETION_STATUS_IN_PROGRESS
        )
      }
    );

    return Database.executeBatch(
      new AIDataDeletionBatch(requestId, PHASE_CONVERSATIONS),
      AIAssistApplicationConstants.DATA_DELETION_BATCH_SIZE
    );
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    deletionRequest = [
      SELECT Id, Scope__c, SubjectUser__c, SubjectRecordId__c, Status__c
      FROM AIDataDeletionRequest__c
      WHERE Id = :requestId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    Id subjectUserId = deletionRequest.Scope__c ==
      AIAssistApplicationConstants.DELETION_SCOPE_USER
      ? deletionRequest.SubjectUser__c
      : null;
    Set<String> recordIds = new Set<String>();

    if (
      deletionRequest.Scope__c ==
      AIAssistApplicationConstants.DELETION_SCOPE_RELATED_RECORD &&
      String.isNotBlank(deletionRequest.SubjectRecordId__c)
    ) {
      String rawSubjectRecordId = deletionRequest.SubjectRecordId__c.trim();
      recordIds.add(rawSubjectRecordId);
      recordIds.add(rawSubjectRecordId.left(15));
      recordIds.add(String.valueOf(Id.valueOf(rawSubjectRecordId)));
    }

    if (phase == PHASE_VIOLATIONS)
      return Database.getQueryLocator(
        [
          SELECT Id
          FROM AIViolation__c
          WHERE User__c = :subjectUserId AND User__c != NULL
          WITH SYSTEM_MODE
        ]
      );
    if (phase == PHASE_USAGE)
      return Database.getQueryLocator(
        [
          SELECT Id
          FROM AIUsageDaily__c
          WHERE User__c = :subjectUserId AND User__c != NULL
          WITH SYSTEM_MODE
        ]
      );

    return Database.getQueryLocator(
      [
        SELECT Id, IsOnLegalHold__c
        FROM AIConversation__c
        WHERE
          (OwnerId = :subjectUserId
          AND OwnerId != NULL)
          OR RelatedRecordId__c IN :recordIds
        WITH SYSTEM_MODE
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    try {
      if (phase == PHASE_VIOLATIONS) {
        for (SObject violation : scope) {
          violation.put('User__c', null);
          violation.put('Detail__c', null);
        }
        AIMessagingDataService.updateAsPackage(scope);
        violationsAnonymised += scope.size();
        return;
      }

      if (phase == PHASE_USAGE) {
        for (SObject usageRow : scope) {
          usageRow.put('User__c', null);
          usageRow.put('UsageKey__c', 'anonymised-' + usageRow.Id);
        }
        AIMessagingDataService.updateAsPackage(scope);
        usageRowsAnonymised += scope.size();
        return;
      }

      Set<Id> deletableIds = new Set<Id>();
      List<AIConversation__c> deletableConversations = new List<AIConversation__c>();

      for (AIConversation__c conversation : (List<AIConversation__c>) scope) {
        if (conversation.IsOnLegalHold__c == true) {
          conversationsSkipped++;
        } else {
          deletableConversations.add(conversation);
          deletableIds.add(conversation.Id);
        }
      }

      if (deletableConversations.isEmpty())
        return;

      // Audit records stay, without the person or the detail, before the lookup to the conversation is cleared by the delete.
      List<AIViolation__c> violations = [
        SELECT Id
        FROM AIViolation__c
        WHERE AIConversation__c IN :deletableIds
        WITH SYSTEM_MODE
      ];
      for (AIViolation__c violation : violations) {
        violation.User__c = null;
        violation.Detail__c = null;
      }
      AIMessagingDataService.updateAsPackage(violations);
      violationsAnonymised += violations.size();

      List<AIFeedback__c> feedbackRecords = [
        SELECT Id
        FROM AIFeedback__c
        WHERE AIConversation__c IN :deletableIds
        WITH SYSTEM_MODE
      ];
      feedbackDeleted += AIMessagingDataService.deleteAndLogFailures(
        feedbackRecords,
        'AIDataDeletionBatch',
        'execute'
      );

      messagesDeleted += [
        SELECT COUNT()
        FROM AIConversationMessage__c
        WHERE AIConversation__c IN :deletableIds
        WITH SYSTEM_MODE
      ];
      conversationsDeleted += AIMessagingDataService.deleteAndLogFailures(
        deletableConversations,
        'AIDataDeletionBatch',
        'execute'
      );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIDataDeletionBatch',
        'execute'
      );
      if (failureDetail == null)
        failureDetail = caughtException.getMessage();
    }
  }

  public void finish(Database.BatchableContext context) {
    try {
      AIDataDeletionRequest__c savedRequest = [
        SELECT
          Id,
          Scope__c,
          ConversationsDeleted__c,
          MessagesDeleted__c,
          FeedbackDeleted__c,
          ConversationsSkippedOnHold__c,
          ViolationsAnonymised__c,
          UsageRowsAnonymised__c
        FROM AIDataDeletionRequest__c
        WHERE Id = :requestId
        WITH SYSTEM_MODE
        LIMIT 1
      ];

      savedRequest.ConversationsDeleted__c =
        treatNullAsZero(savedRequest.ConversationsDeleted__c) +
        conversationsDeleted;
      savedRequest.MessagesDeleted__c =
        treatNullAsZero(savedRequest.MessagesDeleted__c) + messagesDeleted;
      savedRequest.FeedbackDeleted__c =
        treatNullAsZero(savedRequest.FeedbackDeleted__c) + feedbackDeleted;
      savedRequest.ConversationsSkippedOnHold__c =
        treatNullAsZero(savedRequest.ConversationsSkippedOnHold__c) +
        conversationsSkipped;
      savedRequest.ViolationsAnonymised__c =
        treatNullAsZero(savedRequest.ViolationsAnonymised__c) +
        violationsAnonymised;
      savedRequest.UsageRowsAnonymised__c =
        treatNullAsZero(savedRequest.UsageRowsAnonymised__c) +
        usageRowsAnonymised;

      Boolean isUserRequest =
        savedRequest.Scope__c ==
        AIAssistApplicationConstants.DELETION_SCOPE_USER;
      String nextPhase = failureDetail != null ||
        !isUserRequest ||
        phase == PHASE_USAGE
        ? null
        : (phase == PHASE_CONVERSATIONS ? PHASE_VIOLATIONS : PHASE_USAGE);

      if (failureDetail != null) {
        savedRequest.Status__c = AIAssistApplicationConstants.DELETION_STATUS_FAILED;
        savedRequest.FailureDetail__c = failureDetail.left(255);
      } else if (nextPhase == null) {
        savedRequest.Status__c = AIAssistApplicationConstants.DELETION_STATUS_COMPLETED;
        savedRequest.CompletedDate__c = System.now();
      }

      AIMessagingDataService.updateAsPackage(new List<SObject>{ savedRequest });

      if (nextPhase != null)
        Database.executeBatch(
          new AIDataDeletionBatch(requestId, nextPhase),
          AIAssistApplicationConstants.DATA_DELETION_BATCH_SIZE
        );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIDataDeletionBatch',
        'finish'
      );
    }
  }

  private static Decimal treatNullAsZero(Decimal value) {
    return value == null ? 0 : value;
  }
}
