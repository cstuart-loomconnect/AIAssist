/*
Class Name: AIPiiFieldRegistry

=================================================================
=================================================================

Description: Read-only lookup of which fields are personal data, and of what type.

Step 1: Read the PII field metadata for an object from AIPIIFieldMetadata__c, once per object per transaction
Step 2: Cache the field API name to PII type map for that object
Step 3: Answer type and is-PII questions from the cache, with no PII for an object that has no synced registry

The metadata is configuration the end user cannot read (only Admin and Super User are granted
AIPIIFieldMetadata__c), and the package reads it on their behalf, so the query is explicit system mode.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPiiFieldRegistry {
  private static Map<String, Map<String, String>> piiFieldTypesByObject = new Map<String, Map<String, String>>();

  // The PII type of a field, or null when the field is not PII.
  public static String getFieldType(String objectApiName, String fieldApiName) {
    // [1] Nothing to look up - a name is missing
    if (String.isBlank(objectApiName) || String.isBlank(fieldApiName))
      return null;

    // [2] Return the type from the object's cached fields
    return getFieldTypes(objectApiName).get(fieldApiName);
  }

  // True when the field is registered as PII for the object.
  public static Boolean isPii(String objectApiName, String fieldApiName) {
    // [1] Nothing to look up - a name is missing
    if (String.isBlank(objectApiName) || String.isBlank(fieldApiName))
      return false;

    // [2] The field is PII when the object's cached fields include it
    return getFieldTypes(objectApiName).containsKey(fieldApiName);
  }

  // Field API name -> PII type for every PII field of the object. Bulk-friendly: one query per distinct object per transaction.
  public static Map<String, String> getFieldTypes(String objectApiName) {
    // [1] Nothing to look up - no object
    if (String.isBlank(objectApiName))
      return new Map<String, String>();

    // [2] Query the object's PII fields once and keep them for the rest of the transaction
    if (!piiFieldTypesByObject.containsKey(objectApiName)) {
      Map<String, String> fieldTypesByFieldApiName = new Map<String, String>();

      for (AIPIIFieldMetadata__c fieldMetadata : [
        SELECT FieldAPIName__c, PIIFieldType__c
        FROM AIPIIFieldMetadata__c
        WHERE
          PIIRegistry__r.ObjectAPIName__c = :objectApiName
          AND IsPII__c = TRUE
        WITH SYSTEM_MODE
      ]) {
        fieldTypesByFieldApiName.put(
          fieldMetadata.FieldAPIName__c,
          fieldMetadata.PIIFieldType__c
        );
      }

      piiFieldTypesByObject.put(objectApiName, fieldTypesByFieldApiName);
    }

    // [3] Return the cached fields
    return piiFieldTypesByObject.get(objectApiName);
  }
}
