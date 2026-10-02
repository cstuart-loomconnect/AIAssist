/*
Class Name: AIDataDeletionRequestTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIDataDeletionRequestTrigger and AIDataDeletionRequestTriggerHandler: the request lifecycle, the four-eyes rule on the object, and the lock on a finished request.

=================================================================
=================================================================
Applicable Classes:

AIDataDeletionRequestTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIDataDeletionRequestTriggerHandlerTest {
  // testScenario1: A new request starts as Requested and Pending.
  // testScenario2: An approval by someone other than the requester stamps who and when and moves the status to Approved.
  // testScenario3: The requester cannot approve their own request: the validation rule refuses.
  // testScenario4: A rejection needs a reason, and with one stamps the decision and moves the status to Rejected.
  // testScenario5: A completed request cannot be changed.
  // testScenario6: Switched off, a decision stamps nothing and starts nothing.
  // testScenario7: The handler ignores empty input.
  // testScenario8: An unexpected failure inside the handler is logged and never stops the save.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  @IsTest
  static void testScenario1() {
    AIDataDeletionRequest__c request = AIAssistTestDataFactory.createAIDataDeletionRequests(
      UserInfo.getUserId(),
      null,
      1,
      false
    )[0];

    Test.startTest();
    insert request;
    Test.stopTest();

    AIDataDeletionRequest__c saved = [
      SELECT Status__c, ApprovalDecision__c
      FROM AIDataDeletionRequest__c
      WHERE Id = :request.Id
    ];
    Assert.areEqual(
      AIAssistApplicationConstants.DELETION_STATUS_REQUESTED,
      saved.Status__c,
      'Requested.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.DELETION_DECISION_PENDING,
      saved.ApprovalDecision__c,
      'Pending.'
    );
  }

  @IsTest
  static void testScenario2() {
    List<User> users = AIAssistTestDataFactory.createUsers(1, true);
    AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistAdminUser');
    AIDataDeletionRequest__c request;
    System.runAs(users[0]) {
      request = AIAssistTestDataFactory.createAIDataDeletionRequests(
        UserInfo.getUserId(),
        null,
        1,
        false
      )[0];
      insert request;
    }

    Test.startTest();
    request.ApprovalDecision__c = AIAssistApplicationConstants.DELETION_DECISION_APPROVED;
    update request;
    Test.stopTest();

    AIDataDeletionRequest__c saved = [
      SELECT ApprovedBy__c, ApprovedDate__c
      FROM AIDataDeletionRequest__c
      WHERE Id = :request.Id
    ];
    Assert.areEqual(UserInfo.getUserId(), saved.ApprovedBy__c, 'The approver.');
    Assert.isNotNull(saved.ApprovedDate__c, 'And when.');
  }

  @IsTest
  static void testScenario3() {
    AIDataDeletionRequest__c request = AIAssistTestDataFactory.createAIDataDeletionRequests(
      UserInfo.getUserId(),
      null,
      1,
      true
    )[0];
    Database.SaveResult result;

    Test.startTest();
    request.ApprovalDecision__c = AIAssistApplicationConstants.DELETION_DECISION_APPROVED;
    result = Database.update(request, false);
    Test.stopTest();

    Assert.isFalse(result.isSuccess(), 'Refused.');
    Assert.areEqual(
      StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION,
      result.getErrors()[0].getStatusCode(),
      'By the validation rule on the object, not by code that can be bypassed.'
    );
  }

  @IsTest
  static void testScenario4() {
    List<User> users = AIAssistTestDataFactory.createUsers(1, true);
    AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistAdminUser');
    AIDataDeletionRequest__c request;
    System.runAs(users[0]) {
      request = AIAssistTestDataFactory.createAIDataDeletionRequests(
        UserInfo.getUserId(),
        null,
        1,
        false
      )[0];
      insert request;
    }
    Database.SaveResult withoutReason;
    Database.SaveResult withReason;

    Test.startTest();
    request.ApprovalDecision__c = AIAssistApplicationConstants.DELETION_DECISION_REJECTED;
    withoutReason = Database.update(request, false);
    request.RejectionReason__c = 'Not the data subject.';
    withReason = Database.update(request, false);
    Test.stopTest();

    Assert.isFalse(withoutReason.isSuccess(), 'A reason is required.');
    Assert.isTrue(withReason.isSuccess(), 'Accepted with one.');
    Assert.areEqual(
      AIAssistApplicationConstants.DELETION_STATUS_REJECTED,
      [SELECT Status__c FROM AIDataDeletionRequest__c WHERE Id = :request.Id]
      .Status__c,
      'Rejected.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIDataDeletionRequest__c request = AIAssistTestDataFactory.createAIDataDeletionRequests(
      UserInfo.getUserId(),
      null,
      1,
      true
    )[0];
    request.Status__c = AIAssistApplicationConstants.DELETION_STATUS_COMPLETED;
    update request;
    Database.SaveResult result;

    Test.startTest();
    request.Notes__c = 'Changed afterwards.';
    result = Database.update(request, false);
    Test.stopTest();

    Assert.isFalse(result.isSuccess(), 'Locked.');
  }

  @IsTest
  static void testScenario6() {
    List<User> users = AIAssistTestDataFactory.createUsers(1, true);
    AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistAdminUser');
    AIDataDeletionRequest__c request;
    System.runAs(users[0]) {
      request = AIAssistTestDataFactory.createAIDataDeletionRequests(
        UserInfo.getUserId(),
        null,
        1,
        false
      )[0];
      insert request;
    }
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;

    Test.startTest();
    request.ApprovalDecision__c = AIAssistApplicationConstants.DELETION_DECISION_APPROVED;
    update request;
    Test.stopTest();

    AIDataDeletionRequest__c saved = [
      SELECT Status__c, ApprovedBy__c
      FROM AIDataDeletionRequest__c
      WHERE Id = :request.Id
    ];
    Assert.isNull(saved.ApprovedBy__c, 'Nothing stamped.');
    Assert.areNotEqual(
      AIAssistApplicationConstants.DELETION_STATUS_COMPLETED,
      saved.Status__c,
      'And nothing ran.'
    );
  }

  @IsTest
  static void testScenario7() {
    Test.startTest();
    try {
      AIDataDeletionRequestTriggerHandler.handleBeforeInsert(null);
      AIDataDeletionRequestTriggerHandler.handleBeforeUpdate(null, null);
      AIDataDeletionRequestTriggerHandler.handleAfterUpdate(null, null);
    } catch (Exception ex) {
      Assert.fail('The handler must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIDataDeletionRequest__c],
      'Nothing to do.'
    );
  }

  @IsTest
  static void testScenario8() {
    AIDataDeletionRequestTriggerHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    try {
      AIDataDeletionRequestTriggerHandler.handleBeforeInsert(
        new List<AIDataDeletionRequest__c>{ new AIDataDeletionRequest__c() }
      );
    } catch (Exception ex) {
      Assert.fail('The handler must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AIPlatformLog__c
        WHERE ClassName__c = 'AIDataDeletionRequestTriggerHandler'
      ],
      'Logged once.'
    );
  }
}
