/*
Class Name: AISchemaHelper

=================================================================
=================================================================

Description: One place for the schema questions the package asks: what object an Id belongs to, its labels and name
field, and what a field is (type, length). Describe calls are slow and count against the transaction,
so every answer is cached.

Two levels of cache, both holding only schema facts that are the same for every user:
[1] A static map, for the rest of the transaction.
[2] An org cache partition (AIAssistSchema), kept between transactions and users when the subscriber has
    created that partition (Setup > Platform Cache). The partition belongs to the subscriber, so it
    cannot ship in the package: without it, or when Platform Cache is not available, the helper quietly
    uses the static map alone. Values are stored as JSON, keyed by a hex encoding of the name, because
    cache keys must be alphanumeric.
Whether the current user can read an object depends on the user, so it is never persisted; it is cached
for the transaction only.

A cached answer can outlive a schema change (a field added later). clearCache empties both levels, and
the persisted entries expire after SCHEMA_CACHE_TTL_SECONDS on their own.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public inherited sharing class AISchemaHelper {
  public static final String PARTITION_NAME = 'AIAssistSchema';
  public static final Integer SCHEMA_CACHE_TTL_SECONDS = 86400;

  // What the helper needs of a cache, so a test can replace the platform.
  public interface ICache {
    String get(String key);
    void put(String key, String value, Integer ttlSeconds);
    void clear(String key);
  }

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

  // The org cache partition when the subscriber has one, otherwise nothing.
  private class OrgPartitionCache implements ICache {
    public String get(String key) {
      Cache.OrgPartition orgPartition = null;
      try {
        orgPartition = Cache.Org.getPartition('local.' + PARTITION_NAME);
      } catch (Exception noPartition) {
        orgPartition = null;
      }
      return orgPartition == null ? null : (String) orgPartition.get(key);
    }

    public void put(String key, String value, Integer ttlSeconds) {
      Cache.OrgPartition orgPartition = null;
      try {
        orgPartition = Cache.Org.getPartition('local.' + PARTITION_NAME);
      } catch (Exception noPartition) {
        orgPartition = null;
      }
      if (orgPartition != null)
        orgPartition.put(key, value, ttlSeconds);
    }

    public void clear(String key) {
      Cache.OrgPartition orgPartition = null;
      try {
        orgPartition = Cache.Org.getPartition('local.' + PARTITION_NAME);
      } catch (Exception noPartition) {
        orgPartition = null;
      }
      if (orgPartition != null)
        orgPartition.remove(key);
    }
  }

  @TestVisible
  private static Boolean isPersistentCacheUnavailable = false;

  @TestVisible
  private static ICache persistentCache = new OrgPartitionCache();
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

    // Cache keys must be alphanumeric, so the name is hex encoded; two different names can never share a key.
    String cacheKey =
      'obj' + EncodingUtil.convertToHex(Blob.valueOf(lowerName));

    ObjectInfo objectInfo = null;

    try {
      String cachedJson = isPersistentCacheUnavailable
        ? null
        : persistentCache.get(cacheKey);
      objectInfo = String.isBlank(cachedJson)
        ? null
        : (ObjectInfo) JSON.deserialize(cachedJson, ObjectInfo.class);
    } catch (Exception cacheReadFailure) {
      objectInfo = null; // A cache that is missing, full or unreadable just means a describe.
    }

    if (objectInfo == null) {
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
      objectInfo = new ObjectInfo();
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

      try {
        if (!isPersistentCacheUnavailable) {
          persistentCache.put(
            cacheKey,
            JSON.serialize(objectInfo),
            SCHEMA_CACHE_TTL_SECONDS
          );
        }
      } catch (Exception cacheWriteFailure) {
        // Too large for the cache, or no cache: stop using it for the rest of the transaction; the static map still serves it.
        isPersistentCacheUnavailable = true;
      }
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

  // Empties both levels for one object, or for everything the transaction has seen when no name is given.
  public static void clearCache(String objectApiName) {
    Set<String> namesToClear = String.isBlank(objectApiName)
      ? new Set<String>(infoByLowerName.keySet())
      : new Set<String>{ objectApiName.toLowerCase() };

    for (String lowerName : namesToClear) {
      infoByLowerName.remove(lowerName);
      accessibleByLowerName.remove(lowerName);
      try {
        persistentCache.clear(
          'obj' + EncodingUtil.convertToHex(Blob.valueOf(lowerName))
        );
      } catch (Exception cacheClearFailure) {
        // Platform Cache is an optimisation, never a reason to fail.
        isPersistentCacheUnavailable = true;
      }
    }
  }
}
