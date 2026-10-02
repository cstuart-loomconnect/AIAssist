/*
Class Name: AIDataDeletionRequestTriggerHandler

=================================================================
=================================================================

Description: Business logic for AIDataDeletionRequest__c.

Before insert: a new request starts as Requested / Pending.
Before update: when the decision becomes Approved or Rejected the handler stamps who decided and when,
and moves the status to Approved or Rejected. The four-eyes rule (the requester cannot approve their
own request) and the lock on a completed request are validation rules on the object, so they hold
however the record is changed.
After update: a request that has just been Approved is handed to AIDataDeletionBatch. Nothing is
deleted unless the request is Approved; the batch checks that again.

Does nothing while the application is switched off: an approved request waits until it is on again
and can be started from the console. Bulk-safe: no queries, one batch started per approved request.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
3.0          Chandler Stuart          Restructured to the standard pattern: the trigger only routes by context to handleBeforeInsert, handleAfterUpdate and so on, each handler has its own exception type and a test seam, and a failure is logged and never stops the save.
*/

public inherited sharing class AIDataDeletionRequestTriggerHandler {
  public class AIDataDeletionRequestTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleBeforeInsert(
    List<AIDataDeletionRequest__c> newRequests
  ) {
    try {
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIDataDeletionRequestTriggerHandlerException(
          'Test exception for AIDataDeletionRequestTriggerHandler.handleBeforeInsert'
        );
      }

      if (newRequests == null)
        return;

      for (AIDataDeletionRequest__c request : newRequests) {
        if (request.Status__c == null)
          request.Status__c = AIAssistApplicationConstants.DELETION_STATUS_REQUESTED;
        if (request.ApprovalDecision__c == null)
          request.ApprovalDecision__c = AIAssistApplicationConstants.DELETION_DECISION_PENDING;
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIDataDeletionRequestTriggerHandler',
        'handleBeforeInsert'
      );
    }
  }

  public static void handleBeforeUpdate(
    Map<Id, AIDataDeletionRequest__c> oldRequests,
    List<AIDataDeletionRequest__c> newRequests
  ) {
    try {
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIDataDeletionRequestTriggerHandlerException(
          'Test exception for AIDataDeletionRequestTriggerHandler.handleBeforeUpdate'
        );
      }

      if (oldRequests == null || newRequests == null)
        return;

      for (AIDataDeletionRequest__c request : newRequests) {
        AIDataDeletionRequest__c previous = oldRequests.get(request.Id);
        if (
          previous == null ||
          previous.ApprovalDecision__c == request.ApprovalDecision__c
        )
          continue;

        Boolean isApproved =
          request.ApprovalDecision__c ==
          AIAssistApplicationConstants.DELETION_DECISION_APPROVED;
        Boolean isRejected =
          request.ApprovalDecision__c ==
          AIAssistApplicationConstants.DELETION_DECISION_REJECTED;
        if (!isApproved && !isRejected)
          continue;

        request.ApprovedBy__c = UserInfo.getUserId();
        request.ApprovedDate__c = System.now();
        request.Status__c = isApproved
          ? AIAssistApplicationConstants.DELETION_STATUS_APPROVED
          : AIAssistApplicationConstants.DELETION_STATUS_REJECTED;
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIDataDeletionRequestTriggerHandler',
        'handleBeforeUpdate'
      );
    }
  }

  public static void handleAfterUpdate(
    Map<Id, AIDataDeletionRequest__c> oldRequests,
    List<AIDataDeletionRequest__c> newRequests
  ) {
    try {
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIDataDeletionRequestTriggerHandlerException(
          'Test exception for AIDataDeletionRequestTriggerHandler.handleAfterUpdate'
        );
      }

      if (oldRequests == null || newRequests == null)
        return;

      for (AIDataDeletionRequest__c request : newRequests) {
        AIDataDeletionRequest__c previous = oldRequests.get(request.Id);

        if (
          previous != null &&
          previous.Status__c != request.Status__c &&
          request.Status__c ==
          AIAssistApplicationConstants.DELETION_STATUS_APPROVED
        )
          AIDataDeletionBatch.startApprovedRequest(request.Id);
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIDataDeletionRequestTriggerHandler',
        'handleAfterUpdate'
      );
    }
  }
}
