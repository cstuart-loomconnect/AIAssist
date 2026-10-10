/*
Class Name: AIPiiFieldTypeClassifier

=================================================================
=================================================================

Description: Classifies a field's PII type (Name, Email, National Insurance Number and so on) from its API name, label, data type and Compliance Group.

Step 1: Return nothing when the name, label, data type or Compliance Group is missing
Step 2: Read the AIPiiFieldType__mdt rules and Compliance Groups once per transaction
Step 3: Return the type of the first keyword rule that matches
Step 4: Otherwise return the Compliance Group fallback type, or Other when there is none

Called once per field by AIPiiRegistrySyncWorker; the answer is stored on AIPIIFieldMetadata__c.PIIFieldType__c.
The rules are editable in Setup without a deployment. Other is returned because Data Classification
already flagged the field, so it is treated as PII.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPiiFieldTypeClassifier {
  // Tests set these two instead of reading custom metadata, which cannot be inserted.
  @TestVisible
  private static List<AIPiiFieldType__mdt> fieldTypes;
  @TestVisible
  private static Map<Id, AIPiiComplianceGroup__mdt> complianceGroupsById;

  // The PII type of a field, Other when it is flagged but matches no rule, or null when it cannot be classified.
  public static String classify(
    String fieldApiName,
    String fieldLabel,
    String dataType,
    String complianceGroup
  ) {
    try {
      // [1] Nothing to classify with - a name, label, type or group is missing
      if (
        String.isBlank(fieldApiName) ||
        String.isBlank(fieldLabel) ||
        String.isBlank(dataType) ||
        String.isBlank(complianceGroup)
      )
        return null;

      // [2] Reduce the name and label to letters and digits, so Social_Security_Number, "SSN Number" and ssn-number all take the same shape
      String nameAndLabel =
        fieldApiName.toLowerCase().replaceAll('[^a-z0-9]', '') +
        ' ' +
        fieldLabel.toLowerCase().replaceAll('[^a-z0-9]', '');
      String apiName = fieldApiName.toLowerCase();
      String lowerDataType = dataType.toLowerCase();

      // [3] Read the keyword rules once per transaction
      if (fieldTypes == null) {
        fieldTypes = [
          SELECT
            Keyword__c,
            MatchField__c,
            PIIFieldType__c,
            ComplianceGroup__c,
            IsComplianceGroupFallback__c
          FROM AIPiiFieldType__mdt
          WHERE IsActive__c = TRUE
          WITH SYSTEM_MODE
          ORDER BY DisplayOrder__c ASC
        ];
      }

      // [4] Read the Compliance Groups once per transaction
      if (complianceGroupsById == null) {
        complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>(
          [
            SELECT MasterLabel, IsActive__c
            FROM AIPiiComplianceGroup__mdt
            WITH SYSTEM_MODE
          ]
        );
      }

      AIPiiFieldType__mdt fallback = null;

      for (AIPiiFieldType__mdt fieldType : fieldTypes) {
        String matchField = String.isBlank(fieldType.MatchField__c)
          ? ''
          : fieldType.MatchField__c.trim();

        // [5] Return the rule's type when one of its keywords matches the way the rule says to match
        for (
          String keyword : String.isBlank(fieldType.Keyword__c)
            ? new List<String>()
            : fieldType.Keyword__c.split(',')
        ) {
          String lowerKeyword = keyword.trim().toLowerCase();
          if (String.isBlank(lowerKeyword))
            continue;

          Boolean isMatch = matchField.equalsIgnoreCase(
              AIAssistApplicationConstants.PII_MATCH_FIELD_API_NAME_EXACT
            )
            ? apiName == lowerKeyword
            : matchField.equalsIgnoreCase(
                  AIAssistApplicationConstants.PII_MATCH_FIELD_DATA_TYPE_CONTAINS
                )
                ? lowerDataType.contains(lowerKeyword)
                : matchField.equalsIgnoreCase(
                    AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS
                  ) && nameAndLabel.contains(lowerKeyword);

          if (isMatch)
            return fieldType.PIIFieldType__c;
        }

        // [6] Remember the first fallback rule that belongs to this field's Compliance Group
        if (
          fallback == null &&
          fieldType.IsComplianceGroupFallback__c == true &&
          fieldType.ComplianceGroup__c != null
        ) {
          AIPiiComplianceGroup__mdt fieldGroup = complianceGroupsById.get(
            fieldType.ComplianceGroup__c
          );

          if (
            fieldGroup != null &&
            fieldGroup.IsActive__c == true &&
            complianceGroup.equalsIgnoreCase(fieldGroup.MasterLabel)
          )
            fallback = fieldType;
        }
      }

      // [7] No keyword matched - use the Compliance Group fallback, or Other when there is none
      return fallback == null
        ? AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER
        : fallback.PIIFieldType__c;
    } catch (Exception ex) {
      AIPlatformLogManager.logException(
        ex,
        'AIPiiFieldTypeClassifier',
        'classify'
      );
      return null;
    }
  }
}
