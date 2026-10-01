/*
Class Name: AIPiiFieldRegistry

=================================================================
=================================================================

Description: Read-only lookup of which fields are personal data, and of what type. The answer
comes from AIPIIFieldMetadata__c, which the PII registry sync fills in per object. Nothing is
treated as PII until a registry has been synced for its object: an object with no registry
returns false for every field.

One query per object per transaction, cached, so a result with hundreds of records across
several objects costs one query per object, not one per field.

The metadata is configuration the end user cannot read (only Admin and Super User are granted
AIPIIFieldMetadata__c), and the package reads it on their behalf, so the query is explicit system
mode.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Explicit system mode. Sharing relaxed to inherited.
*/

public inherited sharing class AIPiiFieldRegistry {
  private static Map<String, Map<String, String>> piiFieldTypesByObject = new Map<String, Map<String, String>>();

  // The PII type of a field, or null when the field is not PII.
  public static String getFieldType(String objectApiName, String fieldApiName) {
    if (String.isBlank(objectApiName) || String.isBlank(fieldApiName))
      return null;

    return getFieldTypes(objectApiName).get(fieldApiName);
  }

  public static Boolean isPii(String objectApiName, String fieldApiName) {
    if (String.isBlank(objectApiName) || String.isBlank(fieldApiName))
      return false;

    return getFieldTypes(objectApiName).containsKey(fieldApiName);
  }

  // Field API name -> PII type for every PII field of the object. Bulk-friendly: one query per distinct object per transaction.
  public static Map<String, String> getFieldTypes(String objectApiName) {
    if (String.isBlank(objectApiName))
      return new Map<String, String>();

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

    return piiFieldTypesByObject.get(objectApiName);
  }
}
