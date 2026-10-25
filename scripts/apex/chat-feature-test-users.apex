/*
Script Name: chat-feature-test-users.apex

=================================================================
=================================================================

Description: Creates the second user the Share scenarios need: "Dana Recipient", a Standard User with the AI Assist User permission set. Run this BEFORE chat-feature-test-data.apex. User and permission set assignment are setup records, so they cannot be created in the same transaction as the AI settings that chat-feature-test-data.apex adds.

Step 1: Refuse to run outside a sandbox or scratch org
Step 2: Find or create Dana Recipient
Step 3: Give Dana the AI Assist User permission set when she does not have it

Run:  sf apex run --file scripts/apex/chat-feature-test-users.apex --target-org <alias>
Safe to run again.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public class ChatFeatureTestUsers {

  public void run() {

    // [1] Never run in production
    if (![SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox) {

      System.debug(LoggingLevel.ERROR, 'Not a sandbox or scratch org. Nothing was created.');
      return;
    }

    // [2] Find Dana, or create her
    String username = 'dana.recipient@' + UserInfo.getOrganizationId().toLowerCase() + '.example.com';
    List<User> existing = [SELECT Id FROM User WHERE Username = :username LIMIT 1];
    User dana;

    if (existing.isEmpty()) {

      Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
      dana = new User(FirstName = 'Dana', LastName = 'Recipient', Alias = 'drecip', Email = 'dana.recipient@example.com', Username = username, ProfileId = standardProfile.Id, TimeZoneSidKey = 'Europe/London', LocaleSidKey = 'en_GB', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US', Title = 'Support Lead');
      insert dana;
    } else {

      dana = existing[0];
    }

    // [3] Give her the AI Assist User permission set
    Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'AIAssistUser' LIMIT 1].Id;
    Integer assigned = [SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :dana.Id AND PermissionSetId = :permissionSetId];

    if (assigned == 0) insert new PermissionSetAssignment(AssigneeId = dana.Id, PermissionSetId = permissionSetId);

    System.debug(LoggingLevel.ERROR, 'Dana Recipient: ' + dana.Id + ' (' + username + ')');
  }
}

new ChatFeatureTestUsers().run();
