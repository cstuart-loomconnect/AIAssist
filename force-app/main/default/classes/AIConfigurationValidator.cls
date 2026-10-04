/*
Class Name: AIConfigurationValidator

=================================================================
=================================================================

Description: Checks, when a configuration record is saved, that what it names exists in this org: the Apex
class of a data source or Workflow Action (and that it implements the right interface), the Named
Credential of a model configuration, and the permission set or permission set group of an assignment. A
name typed wrongly would otherwise be found out by the first user whose message fails. The error is put
on the field and says what was not found.

A name is checked when it is new or changed, so a record that pointed at something since deleted can
still be edited in other ways (the health check reports it). Assignments are checked on every save: the
trigger is not given the old values.

The same things are checked again at run time by the dispatchers and the agent manager; this is for the
administrator's benefit, so a failure of the check itself is logged and the save goes ahead.

Named Credentials, and classes outside the test's own, cannot be created in a test, and almost every test
builds configuration with made-up names. In a test the checks therefore run only when it asks for them
(isCheckedInTest), the same arrangement as AIPlanLimitService.isActivationChecked.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public inherited sharing class AIConfigurationValidator {
  @TestVisible
  private static Boolean isCheckedInTest = false;
  // Named Credentials cannot be created in a test: when set, these are the ones that exist.
  @TestVisible
  private static Set<String> namedCredentialsForTest;
  @TestVisible
  private static Boolean isTestFailureThrown = false;

  // The class named in nameField must exist and implement contract, for records whose typeField is "Apex".
  public static void checkApexClasses(
    List<SObject> newRecords,
    Map<Id, SObject> oldRecordsById,
    Schema.SObjectField nameField,
    Schema.SObjectField typeField,
    System.Type contract
  ) {
    try {
      for (SObject record : changed(newRecords, oldRecordsById, nameField)) {
        if (record.get(typeField) != 'Apex')
          continue;

        String className = ((String) record.get(nameField)).trim();
        // The empty namespace finds the subscriber's own unprefixed classes from managed code, as the dispatchers do.
        System.Type apexType = Type.forName('', className);
        if (apexType == null || !contract.isAssignableFrom(apexType))
          record.addError(
            nameField,
            String.format(
              Label.AI_Error_Apex_Class_Not_Found,
              new List<String>{ className, contract.getName() }
            )
          );
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIConfigurationValidator',
        'checkApexClasses'
      );
    }
  }

  // NamedCredential__c must name a Named Credential in this org.
  public static void checkNamedCredentials(
    List<AIModelConfiguration__c> newRecords,
    Map<Id, AIModelConfiguration__c> oldRecordsById
  ) {
    try {
      List<SObject> toCheck = changed(
        newRecords,
        oldRecordsById,
        AIModelConfiguration__c.NamedCredential__c
      );
      if (toCheck.isEmpty())
        return;

      // "ns__Name" is a credential from a namespace; a name without one is the subscriber's own.
      Set<String> unprefixedNames = new Set<String>();
      for (SObject record : toCheck) {
        String name = ((AIModelConfiguration__c) record)
          .NamedCredential__c.trim();
        unprefixedNames.add(
          name.contains('__') ? name.substringAfter('__') : name
        );
      }

      Set<String> existingNames = new Set<String>();
      if (namedCredentialsForTest != null) {
        for (String testName : namedCredentialsForTest)
          existingNames.add(testName.toLowerCase());
      } else {
        for (NamedCredential credential : [
          SELECT DeveloperName, NamespacePrefix
          FROM NamedCredential
          WHERE DeveloperName IN :unprefixedNames
          WITH SYSTEM_MODE
          LIMIT 2000
        ])
          existingNames.add(
            (String.isBlank(credential.NamespacePrefix)
                ? credential.DeveloperName
                : credential.NamespacePrefix + '__' + credential.DeveloperName)
              .toLowerCase()
          );
      }

      for (SObject record : toCheck) {
        String name = ((AIModelConfiguration__c) record)
          .NamedCredential__c.trim();
        if (!existingNames.contains(name.toLowerCase()))
          record.addError(
            AIModelConfiguration__c.NamedCredential__c,
            String.format(
              Label.AI_Error_Named_Credential_Not_Found,
              new List<String>{ name }
            )
          );
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIConfigurationValidator',
        'checkNamedCredentials'
      );
    }
  }

  // The name in nameField must be a permission set or a permission set group, which is what an assignment is matched against.
  public static void checkPermissionSets(
    List<SObject> newRecords,
    Schema.SObjectField nameField
  ) {
    try {
      List<SObject> toCheck = changed(newRecords, null, nameField);
      if (toCheck.isEmpty())
        return;

      Set<String> names = new Set<String>();
      for (SObject record : toCheck)
        names.add(((String) record.get(nameField)).trim());

      Set<String> existingNames = new Set<String>();
      for (PermissionSet permissionSet : [
        SELECT Name
        FROM PermissionSet
        WHERE Name IN :names AND IsOwnedByProfile = FALSE
        WITH SYSTEM_MODE
        LIMIT 2000
      ])
        existingNames.add(permissionSet.Name.toLowerCase());
      for (PermissionSetGroup permissionSetGroup : [
        SELECT DeveloperName
        FROM PermissionSetGroup
        WHERE DeveloperName IN :names
        WITH SYSTEM_MODE
        LIMIT 2000
      ])
        existingNames.add(permissionSetGroup.DeveloperName.toLowerCase());

      for (SObject record : toCheck) {
        String name = ((String) record.get(nameField)).trim();
        if (!existingNames.contains(name.toLowerCase()))
          record.addError(
            nameField,
            String.format(
              Label.AI_Error_Permission_Set_Not_Found,
              new List<String>{ name }
            )
          );
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIConfigurationValidator',
        'checkPermissionSets'
      );
    }
  }

  // The records whose field is filled in and is new or has changed. None in a test that has not asked for the checks.
  private static List<SObject> changed(
    List<SObject> newRecords,
    Map<Id, SObject> oldRecordsById,
    Schema.SObjectField field
  ) {
    List<SObject> changedRecords = new List<SObject>();

    if (isTestFailureThrown)
      throw new IllegalArgumentException(
        'Test exception for AIConfigurationValidator'
      );
    if (newRecords == null || (Test.isRunningTest() && !isCheckedInTest))
      return changedRecords;

    for (SObject record : newRecords) {
      String value = (String) record.get(field);
      SObject previous = oldRecordsById == null ||
        record.Id == null
        ? null
        : oldRecordsById.get(record.Id);
      if (
        String.isNotBlank(value) &&
        (previous == null ||
        (String) previous.get(field) != value)
      )
        changedRecords.add(record);
    }

    return changedRecords;
  }
}
