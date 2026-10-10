/*
Class Name: AISchemaHelper

=================================================================
=================================================================

Description: Gives the object facts the chat needs for a record, described once per transaction and kept in a static variable.

Step 1: Describe the record's object the first time it is asked for
Step 2: Keep the answer in a static variable so every later question in the transaction is free
Step 3: Split a comma separated list of object names into a lower case set

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AISchemaHelper {
  public class ObjectInfo {
    public String apiName;
    public String label;
    public String pluralLabel;
    public String nameField;
    public Boolean isAccessible = false;
  }

  @TestVisible
  private static Map<String, ObjectInfo> infoByLowerName = new Map<String, ObjectInfo>();

  // The facts about the record's object, or null when there is no Id. The name field is the one that holds the record's name (Name, CaseNumber, Subject), and isAccessible is whether the signed-in user can read the object.
  public static ObjectInfo getObjectInfo(Id recordId) {
    // [1] Nothing to describe when there is no record
    if (recordId == null)
      return null;

    // [2] Use the answer already kept for this object
    Schema.SObjectType objectType = recordId.getSobjectType();
    String lowerName = String.valueOf(objectType).toLowerCase();

    if (infoByLowerName.containsKey(lowerName))
      return infoByLowerName.get(lowerName);

    // [3] Describe the object once and copy the facts across
    Schema.DescribeSObjectResult describeResult = objectType.getDescribe(
      SObjectDescribeOptions.DEFERRED
    );
    ObjectInfo objectInfo = new ObjectInfo();
    objectInfo.apiName = describeResult.getName();
    objectInfo.label = describeResult.getLabel();
    objectInfo.pluralLabel = describeResult.getLabelPlural();
    objectInfo.isAccessible = describeResult.isAccessible();

    // [4] Find the field that holds the record's name
    for (
      Schema.SObjectField fieldToken : describeResult.fields.getMap().values()
    ) {
      Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();

      if (fieldDescribe.isNameField()) {
        objectInfo.nameField = fieldDescribe.getName();
        break;
      }
    }

    // [5] Keep the answer for the rest of the transaction and return it
    infoByLowerName.put(lowerName, objectInfo);

    return objectInfo;
  }

  // The lower case API names in a comma separated list such as 'Account, Contact'. Blank entries are dropped, so a blank list is an empty set.
  public static Set<String> getObjectApiNameSet(String objectApiNames) {
    // [1] Start with an empty set, which is also the answer for a blank list
    Set<String> names = new Set<String>();

    if (String.isBlank(objectApiNames))
      return names;

    // [2] Add each name that is not blank
    for (String objectApiName : objectApiNames.split(',')) {
      if (String.isNotBlank(objectApiName))
        names.add(objectApiName.trim().toLowerCase());
    }

    return names;
  }
}
