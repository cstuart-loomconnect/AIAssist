/*
Class Name: AISchemaHelper

=================================================================
=================================================================

Description: One place for the schema questions the package asks: what object an Id belongs to, its labels and name
field, and what a field is (type, length). Describe calls are slow and count against the transaction,
so every answer is cached in a static map for the rest of the transaction. The answers are schema facts
that are the same for every user, except whether the current user can read an object, which is cached
the same way and so never outlives the transaction.

A cached answer can outlive a schema change made in the same transaction. clearCache empties it.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public inherited sharing class AISchemaHelper {
  public class ObjectInfo {
    public String apiName;
    public String label;
    public String pluralLabel;
    public String keyPrefix;
    public String nameField;
    public Map<String, FieldInfo> fieldsByLowerName = new Map<String, FieldInfo>();
  }

  public class FieldInfo {
    public String apiName;
    public String label;
    public String dataType;
    public Integer length;
    public Boolean isNameField = false;
  }

  @TestVisible
  private static Map<String, ObjectInfo> infoByLowerName = new Map<String, ObjectInfo>();
  @TestVisible
  private static Map<String, Boolean> accessibleByLowerName = new Map<String, Boolean>();
  @TestVisible
  private static Integer describeCount = 0; // How many describes were actually run, for the tests.

  // The object an Id belongs to, or null for a blank or invalid Id.
  public static String getObjectApiName(Id recordId) {
    return recordId == null ? null : String.valueOf(recordId.getSobjectType());
  }

  // Null when the object does not exist in this org.
  public static ObjectInfo getObjectInfo(String objectApiName) {
    if (String.isBlank(objectApiName))
      return null;

    String lowerName = objectApiName.toLowerCase();

    if (infoByLowerName.containsKey(lowerName))
      return infoByLowerName.get(lowerName);

    Schema.SObjectType objectType = Schema.getGlobalDescribe()
      .get(objectApiName);
    if (objectType == null) {
      infoByLowerName.put(lowerName, null);
      return null;
    }

    describeCount++;

    Schema.DescribeSObjectResult describeResult = objectType.getDescribe(
      SObjectDescribeOptions.DEFERRED
    );
    ObjectInfo objectInfo = new ObjectInfo();
    objectInfo.apiName = describeResult.getName();
    objectInfo.label = describeResult.getLabel();
    objectInfo.pluralLabel = describeResult.getLabelPlural();
    objectInfo.keyPrefix = describeResult.getKeyPrefix();

    for (
      Schema.SObjectField fieldToken : describeResult.fields.getMap().values()
    ) {
      Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
      FieldInfo fieldInfo = new FieldInfo();
      fieldInfo.apiName = fieldDescribe.getName();
      fieldInfo.label = fieldDescribe.getLabel();
      fieldInfo.dataType = String.valueOf(fieldDescribe.getType());
      fieldInfo.length = fieldDescribe.getLength() > 0
        ? fieldDescribe.getLength()
        : null;
      fieldInfo.isNameField = fieldDescribe.isNameField();

      objectInfo.fieldsByLowerName.put(
        fieldInfo.apiName.toLowerCase(),
        fieldInfo
      );
      if (fieldInfo.isNameField && objectInfo.nameField == null)
        objectInfo.nameField = fieldInfo.apiName;
    }

    infoByLowerName.put(lowerName, objectInfo);

    return objectInfo;
  }

  public static ObjectInfo getObjectInfo(Id recordId) {
    return getObjectInfo(getObjectApiName(recordId));
  }

  public static String getLabel(String objectApiName) {
    ObjectInfo objectInfo = getObjectInfo(objectApiName);
    return objectInfo == null ? null : objectInfo.label;
  }

  // The field that holds the record's name (Name, CaseNumber, Subject), or null.
  public static String getNameField(String objectApiName) {
    ObjectInfo objectInfo = getObjectInfo(objectApiName);
    return objectInfo == null ? null : objectInfo.nameField;
  }

  public static FieldInfo getFieldInfo(
    String objectApiName,
    String fieldApiName
  ) {
    ObjectInfo objectInfo = getObjectInfo(objectApiName);

    return objectInfo == null || String.isBlank(fieldApiName)
      ? null
      : objectInfo.fieldsByLowerName.get(fieldApiName.toLowerCase());
  }

  public static Boolean hasField(String objectApiName, String fieldApiName) {
    return getFieldInfo(objectApiName, fieldApiName) != null;
  }

  // The field's length, or null when it has none or does not exist. Used to cut a value to fit before saving.
  public static Integer getFieldLength(
    String objectApiName,
    String fieldApiName
  ) {
    FieldInfo fieldInfo = getFieldInfo(objectApiName, fieldApiName);
    return fieldInfo == null ? null : fieldInfo.length;
  }

  // True when the signed-in user can read the object. Per user, so cached for this transaction only.
  public static Boolean isAccessible(String objectApiName) {
    if (String.isBlank(objectApiName))
      return false;

    String lowerName = objectApiName.toLowerCase();

    if (!accessibleByLowerName.containsKey(lowerName)) {
      Schema.SObjectType objectType = Schema.getGlobalDescribe()
        .get(objectApiName);
      accessibleByLowerName.put(
        lowerName,
        objectType != null && objectType.getDescribe().isAccessible()
      );
    }

    return accessibleByLowerName.get(lowerName);
  }

  // Empties the cache for one object, or for everything the transaction has seen when no name is given.
  public static void clearCache(String objectApiName) {
    if (String.isBlank(objectApiName)) {
      infoByLowerName.clear();
      accessibleByLowerName.clear();
      return;
    }

    infoByLowerName.remove(objectApiName.toLowerCase());
    accessibleByLowerName.remove(objectApiName.toLowerCase());
  }
}
