/*
Class Name: AIDataDeletionBatchTest

=================================================================
=================================================================

Description: Testing utility for AIDataDeletionBatch: an approved request deletes the subject's conversations and children, keeps anything on legal hold, anonymises audit records and usage, and records what it did.

=================================================================
=================================================================
Applicable Classes:

AIDataDeletionBatch

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIDataDeletionBatchTest {
  // testScenario1: An approved request for a user deletes their conversations, messages and feedback, skips the one on legal hold, and records the counts and Completed.
  // testScenario2: Another user's conversations, violations and usage are untouched.
  // testScenario3: Violations are kept as audit records but lose the person and the detail, both those tied to a deleted conversation and those that were not.
  // testScenario4: Daily usage rows stay for cost reporting without the person, and their key is freed.
  // testScenario5: A request about a record deletes the conversations about that record and leaves the user's others.
  // testScenario6: begin refuses a request that is not approved, with the not approved label, and does nothing when called again for one already started.
  // testScenario7: Rejecting a request deletes nothing.
  // testScenario8: Bulk: a hundred conversations of the subject, the scope size, are deleted.

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
    List<User> users = AIAssistTestDataFactory.createUsers(3, true);
    User subject = users[0];
    User requester = users[1];
    User bystander = users[2];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ requester },
      'AIAssistAdminUser'
    );
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    List<AIConversation__c> subjectConversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      subject.Id,
      3,
      true
    );
    AIConversation__c held = subjectConversations[2];
    held.IsOnLegalHold__c = true;
    update held;
    AIConversation__c bystanderConversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      bystander.Id,
      1,
      true
    )[0];
    AIConversationMessage__c firstMessage = AIAssistTestDataFactory.createAIConversationMessages(
      subjectConversations[0].Id,
      5,
      2,
      true
    )[0];
    AIAssistTestDataFactory.createAIConversationMessages(
      bystanderConversation.Id,
      5,
      1,
      true
    );
    AIAssistTestDataFactory.createAIFeedback(
      subjectConversations[0].Id,
      firstMessage.Id,
      1,
      true
    );
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      true
    )[0];
    AIViolation__c inConversation = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      subject.Id,
      subjectConversations[0].Id,
      1,
      true
    )[0];
    AIViolation__c loose = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      subject.Id,
      null,
      1,
      true
    )[0];
    AIViolation__c bystanderViolation = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      bystander.Id,
      null,
      1,
      true
    )[0];
    List<AIUsageDaily__c> usage = AIAssistTestDataFactory.createAIUsageDailies(
      subject.Id,
      agent.Id,
      model.Id,
      1,
      true
    );
    AIUsageDaily__c bystanderUsage = AIAssistTestDataFactory.createAIUsageDailies(
      bystander.Id,
      agent.Id,
      model.Id,
      1,
      true
    )[0];
    AIDataDeletionRequest__c request;
    System.runAs(requester) {
      request = AIAssistTestDataFactory.createAIDataDeletionRequests(
        subject.Id,
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

    AIDataDeletionRequest__c done = [
      SELECT
        Status__c,
        ConversationsDeleted__c,
        MessagesDeleted__c,
        FeedbackDeleted__c,
        ConversationsSkippedOnHold__c,
        CompletedDate__c
      FROM AIDataDeletionRequest__c
      WHERE Id = :request.Id
    ];
    Assert.areEqual(
      AIAssistApplicationConstants.DELETION_STATUS_COMPLETED,
      done.Status__c,
      'Completed.'
    );
    Assert.areEqual(2, done.ConversationsDeleted__c, 'Two conversations.');
    Assert.areEqual(2, done.MessagesDeleted__c, 'Their two messages.');
    Assert.areEqual(1, done.FeedbackDeleted__c, 'And the feedback.');
    Assert.areEqual(
      1,
      done.ConversationsSkippedOnHold__c,
      'The held one was skipped and counted.'
    );
    Assert.isNotNull(done.CompletedDate__c, 'With a completion time.');
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AIConversation__c WHERE Id = :held.Id],
      'The held conversation remains.'
    );
  }

  @IsTest
  static void testScenario2() {
    List<User> users = AIAssistTestDataFactory.createUsers(3, true);
    User subject = users[0];
    User requester = users[1];
    User bystander = users[2];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ requester },
      'AIAssistAdminUser'
    );
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    List<AIConversation__c> subjectConversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      subject.Id,
      3,
      true
    );
    AIConversation__c held = subjectConversations[2];
    held.IsOnLegalHold__c = true;
    update held;
    AIConversation__c bystanderConversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      bystander.Id,
      1,
      true
    )[0];
    AIConversationMessage__c firstMessage = AIAssistTestDataFactory.createAIConversationMessages(
      subjectConversations[0].Id,
      5,
      2,
      true
    )[0];
    AIAssistTestDataFactory.createAIConversationMessages(
      bystanderConversation.Id,
      5,
      1,
      true
    );
    AIAssistTestDataFactory.createAIFeedback(
      subjectConversations[0].Id,
      firstMessage.Id,
      1,
      true
    );
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      true
    )[0];
    AIViolation__c inConversation = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      subject.Id,
      subjectConversations[0].Id,
      1,
      true
    )[0];
    AIViolation__c loose = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      subject.Id,
      null,
      1,
      true
    )[0];
    AIViolation__c bystanderViolation = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      bystander.Id,
      null,
      1,
      true
    )[0];
    List<AIUsageDaily__c> usage = AIAssistTestDataFactory.createAIUsageDailies(
      subject.Id,
      agent.Id,
      model.Id,
      1,
      true
    );
    AIUsageDaily__c bystanderUsage = AIAssistTestDataFactory.createAIUsageDailies(
      bystander.Id,
      agent.Id,
      model.Id,
      1,
      true
    )[0];
    AIDataDeletionRequest__c request;
    System.runAs(requester) {
      request = AIAssistTestDataFactory.createAIDataDeletionRequests(
        subject.Id,
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

    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AIConversation__c
        WHERE Id = :bystanderConversation.Id
      ],
      'Their conversation remains.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AIConversationMessage__c
        WHERE AIConversation__c = :bystanderConversation.Id
      ],
      'And its message.'
    );
    Assert.areEqual(
      bystander.Id,
      [SELECT User__c FROM AIViolation__c WHERE Id = :bystanderViolation.Id]
      .User__c,
      'Their violation still names them.'
    );
    Assert.areEqual(
      bystander.Id,
      [SELECT User__c FROM AIUsageDaily__c WHERE Id = :bystanderUsage.Id]
      .User__c,
      'Their usage still names them.'
    );
  }

  @IsTest
  static void testScenario3() {
    List<User> users = AIAssistTestDataFactory.createUsers(3, true);
    User subject = users[0];
    User requester = users[1];
    User bystander = users[2];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ requester },
      'AIAssistAdminUser'
    );
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    List<AIConversation__c> subjectConversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      subject.Id,
      3,
      true
    );
    AIConversation__c held = subjectConversations[2];
    held.IsOnLegalHold__c = true;
    update held;
    AIConversation__c bystanderConversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      bystander.Id,
      1,
      true
    )[0];
    AIConversationMessage__c firstMessage = AIAssistTestDataFactory.createAIConversationMessages(
      subjectConversations[0].Id,
      5,
      2,
      true
    )[0];
    AIAssistTestDataFactory.createAIConversationMessages(
      bystanderConversation.Id,
      5,
      1,
      true
    );
    AIAssistTestDataFactory.createAIFeedback(
      subjectConversations[0].Id,
      firstMessage.Id,
      1,
      true
    );
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      true
    )[0];
    AIViolation__c inConversation = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      subject.Id,
      subjectConversations[0].Id,
      1,
      true
    )[0];
    AIViolation__c loose = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      subject.Id,
      null,
      1,
      true
    )[0];
    AIViolation__c bystanderViolation = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      bystander.Id,
      null,
      1,
      true
    )[0];
    List<AIUsageDaily__c> usage = AIAssistTestDataFactory.createAIUsageDailies(
      subject.Id,
      agent.Id,
      model.Id,
      1,
      true
    );
    AIUsageDaily__c bystanderUsage = AIAssistTestDataFactory.createAIUsageDailies(
      bystander.Id,
      agent.Id,
      model.Id,
      1,
      true
    )[0];
    AIDataDeletionRequest__c request;
    System.runAs(requester) {
      request = AIAssistTestDataFactory.createAIDataDeletionRequests(
        subject.Id,
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

    List<AIViolation__c> violations = [
      SELECT User__c, Detail__c, AIViolationRule__c, AIConversation__c
      FROM AIViolation__c
      WHERE Id IN :new Set<Id>{ inConversation.Id, loose.Id }
    ];
    Assert.areEqual(2, violations.size(), 'Both violations remain.');
    for (AIViolation__c violation : violations) {
      Assert.isNull(violation.User__c, 'No person.');
      Assert.isNull(violation.Detail__c, 'No detail.');
      Assert.areEqual(
        rule.Id,
        violation.AIViolationRule__c,
        'The rule is kept for reporting.'
      );
    }
    Assert.areEqual(
      2,
      [
        SELECT ViolationsAnonymised__c
        FROM AIDataDeletionRequest__c
        WHERE Id = :request.Id
      ]
      .ViolationsAnonymised__c,
      'Both counted.'
    );
  }

  @IsTest
  static void testScenario4() {
    List<User> users = AIAssistTestDataFactory.createUsers(3, true);
    User subject = users[0];
    User requester = users[1];
    User bystander = users[2];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ requester },
      'AIAssistAdminUser'
    );
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    List<AIConversation__c> subjectConversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      subject.Id,
      3,
      true
    );
    AIConversation__c held = subjectConversations[2];
    held.IsOnLegalHold__c = true;
    update held;
    AIConversation__c bystanderConversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      bystander.Id,
      1,
      true
    )[0];
    AIConversationMessage__c firstMessage = AIAssistTestDataFactory.createAIConversationMessages(
      subjectConversations[0].Id,
      5,
      2,
      true
    )[0];
    AIAssistTestDataFactory.createAIConversationMessages(
      bystanderConversation.Id,
      5,
      1,
      true
    );
    AIAssistTestDataFactory.createAIFeedback(
      subjectConversations[0].Id,
      firstMessage.Id,
      1,
      true
    );
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      true
    )[0];
    AIViolation__c inConversation = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      subject.Id,
      subjectConversations[0].Id,
      1,
      true
    )[0];
    AIViolation__c loose = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      subject.Id,
      null,
      1,
      true
    )[0];
    AIViolation__c bystanderViolation = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      bystander.Id,
      null,
      1,
      true
    )[0];
    List<AIUsageDaily__c> usage = AIAssistTestDataFactory.createAIUsageDailies(
      subject.Id,
      agent.Id,
      model.Id,
      1,
      true
    );
    AIUsageDaily__c bystanderUsage = AIAssistTestDataFactory.createAIUsageDailies(
      bystander.Id,
      agent.Id,
      model.Id,
      1,
      true
    )[0];
    AIDataDeletionRequest__c request;
    System.runAs(requester) {
      request = AIAssistTestDataFactory.createAIDataDeletionRequests(
        subject.Id,
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

    AIUsageDaily__c row = [
      SELECT User__c, UsageKey__c, InputTokens__c
      FROM AIUsageDaily__c
      WHERE Id = :usage[0].Id
    ];
    Assert.isNull(row.User__c, 'No person.');
    Assert.isTrue(
      row.UsageKey__c.startsWith('anonymised-'),
      'The key no longer names them.'
    );
    Assert.areEqual(
      1,
      [
        SELECT UsageRowsAnonymised__c
        FROM AIDataDeletionRequest__c
        WHERE Id = :request.Id
      ]
      .UsageRowsAnonymised__c,
      'Counted.'
    );
  }

  @IsTest
  static void testScenario5() {
    List<User> users = AIAssistTestDataFactory.createUsers(2, true);
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ users[1] },
      'AIAssistAdminUser'
    );
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    Account record = AIAssistTestDataFactory.createAccounts(1, true)[0];
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      users[0].Id,
      2,
      false
    );
    conversations[0].RelatedObjectAPIName__c = 'Account';
    conversations[0].RelatedRecordId__c = String.valueOf(record.Id);
    insert conversations;
    AIDataDeletionRequest__c request;
    System.runAs(users[1]) {
      request = AIAssistTestDataFactory.createAIDataDeletionRequests(
        null,
        String.valueOf(record.Id),
        1,
        false
      )[0];
      insert request;
    }

    Test.startTest();
    request.ApprovalDecision__c = AIAssistApplicationConstants.DELETION_DECISION_APPROVED;
    update request;
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIConversation__c WHERE Id = :conversations[0].Id],
      'The conversation about the record is deleted.'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AIConversation__c WHERE Id = :conversations[1].Id],
      'The user\'s other conversation remains.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.DELETION_STATUS_COMPLETED,
      [SELECT Status__c FROM AIDataDeletionRequest__c WHERE Id = :request.Id]
      .Status__c,
      'Completed.'
    );
  }

  @IsTest
  static void testScenario6() {
    List<User> users = AIAssistTestDataFactory.createUsers(3, true);
    User subject = users[0];
    User requester = users[1];
    User bystander = users[2];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ requester },
      'AIAssistAdminUser'
    );
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    List<AIConversation__c> subjectConversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      subject.Id,
      3,
      true
    );
    AIConversation__c held = subjectConversations[2];
    held.IsOnLegalHold__c = true;
    update held;
    AIConversation__c bystanderConversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      bystander.Id,
      1,
      true
    )[0];
    AIConversationMessage__c firstMessage = AIAssistTestDataFactory.createAIConversationMessages(
      subjectConversations[0].Id,
      5,
      2,
      true
    )[0];
    AIAssistTestDataFactory.createAIConversationMessages(
      bystanderConversation.Id,
      5,
      1,
      true
    );
    AIAssistTestDataFactory.createAIFeedback(
      subjectConversations[0].Id,
      firstMessage.Id,
      1,
      true
    );
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      true
    )[0];
    AIViolation__c inConversation = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      subject.Id,
      subjectConversations[0].Id,
      1,
      true
    )[0];
    AIViolation__c loose = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      subject.Id,
      null,
      1,
      true
    )[0];
    AIViolation__c bystanderViolation = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      bystander.Id,
      null,
      1,
      true
    )[0];
    List<AIUsageDaily__c> usage = AIAssistTestDataFactory.createAIUsageDailies(
      subject.Id,
      agent.Id,
      model.Id,
      1,
      true
    );
    AIUsageDaily__c bystanderUsage = AIAssistTestDataFactory.createAIUsageDailies(
      bystander.Id,
      agent.Id,
      model.Id,
      1,
      true
    )[0];
    AIDataDeletionRequest__c request;
    System.runAs(requester) {
      request = AIAssistTestDataFactory.createAIDataDeletionRequests(
        subject.Id,
        null,
        1,
        false
      )[0];
      insert request;
    }
    Id started;
    String code;
    String shown;

    Test.startTest();
    try {
      AIDataDeletionBatch.startApprovedRequest(request.Id);
      Assert.fail('A pending request should have been refused.');
    } catch (AIMessagingException ex) {
      code = ex.code;
      shown = ex.getMessage();
    }
    request.ApprovalDecision__c = AIAssistApplicationConstants.DELETION_DECISION_APPROVED;
    update request;
    started = AIDataDeletionBatch.startApprovedRequest(request.Id);
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_DELETION_NOT_APPROVED,
      code,
      'The code.'
    );
    Assert.areEqual(
      Label.AI_Error_Data_Deletion_Not_Approved,
      shown,
      'The text is the Custom Label.'
    );
    Assert.isNull(
      started,
      'Approving started it, so a second call does nothing.'
    );
  }

  @IsTest
  static void testScenario7() {
    List<User> users = AIAssistTestDataFactory.createUsers(3, true);
    User subject = users[0];
    User requester = users[1];
    User bystander = users[2];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ requester },
      'AIAssistAdminUser'
    );
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    List<AIConversation__c> subjectConversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      subject.Id,
      3,
      true
    );
    AIConversation__c held = subjectConversations[2];
    held.IsOnLegalHold__c = true;
    update held;
    AIConversation__c bystanderConversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      bystander.Id,
      1,
      true
    )[0];
    AIConversationMessage__c firstMessage = AIAssistTestDataFactory.createAIConversationMessages(
      subjectConversations[0].Id,
      5,
      2,
      true
    )[0];
    AIAssistTestDataFactory.createAIConversationMessages(
      bystanderConversation.Id,
      5,
      1,
      true
    );
    AIAssistTestDataFactory.createAIFeedback(
      subjectConversations[0].Id,
      firstMessage.Id,
      1,
      true
    );
    AIViolationRule__c rule = AIAssistTestDataFactory.createAIViolationRules(
      agent.Id,
      1,
      AIAssistApplicationConstants.DETECTION_METHOD_DETERMINISTIC,
      true
    )[0];
    AIViolation__c inConversation = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      subject.Id,
      subjectConversations[0].Id,
      1,
      true
    )[0];
    AIViolation__c loose = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      subject.Id,
      null,
      1,
      true
    )[0];
    AIViolation__c bystanderViolation = AIAssistTestDataFactory.createAIViolations(
      rule.Id,
      bystander.Id,
      null,
      1,
      true
    )[0];
    List<AIUsageDaily__c> usage = AIAssistTestDataFactory.createAIUsageDailies(
      subject.Id,
      agent.Id,
      model.Id,
      1,
      true
    );
    AIUsageDaily__c bystanderUsage = AIAssistTestDataFactory.createAIUsageDailies(
      bystander.Id,
      agent.Id,
      model.Id,
      1,
      true
    )[0];
    AIDataDeletionRequest__c request;
    System.runAs(requester) {
      request = AIAssistTestDataFactory.createAIDataDeletionRequests(
        subject.Id,
        null,
        1,
        false
      )[0];
      insert request;
    }

    Test.startTest();
    request.ApprovalDecision__c = AIAssistApplicationConstants.DELETION_DECISION_REJECTED;
    request.RejectionReason__c = 'Not the data subject.';
    update request;
    Test.stopTest();

    Assert.areEqual(
      3,
      [SELECT COUNT() FROM AIConversation__c WHERE OwnerId = :subject.Id],
      'Nothing was deleted.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.DELETION_STATUS_REJECTED,
      [SELECT Status__c FROM AIDataDeletionRequest__c WHERE Id = :request.Id]
      .Status__c,
      'Rejected.'
    );
  }

  @IsTest
  static void testScenario8() {
    List<User> users = AIAssistTestDataFactory.createUsers(2, true);
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ users[1] },
      'AIAssistAdminUser'
    );
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      users[0].Id,
      AIAssistApplicationConstants.DATA_DELETION_BATCH_SIZE,
      true
    );
    AIDataDeletionRequest__c request;
    System.runAs(users[1]) {
      request = AIAssistTestDataFactory.createAIDataDeletionRequests(
        users[0].Id,
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

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIConversation__c WHERE OwnerId = :users[0].Id],
      'All deleted.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.DATA_DELETION_BATCH_SIZE,
      [
        SELECT ConversationsDeleted__c
        FROM AIDataDeletionRequest__c
        WHERE Id = :request.Id
      ]
      .ConversationsDeleted__c,
      'All counted.'
    );
  }
}
