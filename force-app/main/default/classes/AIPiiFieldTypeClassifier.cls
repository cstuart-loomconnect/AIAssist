/*
Class Name: AIPiiFieldTypeClassifier

=================================================================
=================================================================

Description: Classifies a field's PII type (Name, Email, National Insurance Number and so on) from its API name,
label, data type and Compliance Group. Called once per field by AIPiiRegistrySyncWorker; the answer
is stored on AIPIIFieldMetadata__c.PIIFieldType__c.

The matching rules are AIPiiFieldType__mdt records, editable in Setup without a deployment. When no
keyword rule matches, the field type flagged IsComplianceGroupFallback__c for the field's Compliance
Group is used, and when there is none the type is Other: Data Classification flagged the field, so
it is treated as PII. A field with no name, label, type or Compliance Group is not classified.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from the old classifier. System mode read of the metadata, rules read once per transaction, logging only on a real failure.
*/

public inherited sharing class AIPiiFieldTypeClassifier {
  @TestVisible
  private static List<AIPiiFieldType__mdt> fieldTypes; // Tests set these two instead of reading custom metadata, which cannot be inserted.
  @TestVisible
  private static Map<Id, AIPiiComplianceGroup__mdt> complianceGroupsById;

  public static String classify(
    String fieldApiName,
    String fieldLabel,
    String dataType,
    String complianceGroup
  ) {
    try {
      if (
        String.isBlank(fieldApiName) ||
        String.isBlank(fieldLabel) ||
        String.isBlank(dataType) ||
        String.isBlank(complianceGroup)
      )
        return null;

      // Letters and digits only, so Social_Security_Number, "SSN Number" and ssn-number all take the same shape.
      String nameAndLabel =
        fieldApiName.toLowerCase().replaceAll('[^a-z0-9]', '') +
        ' ' +
        fieldLabel.toLowerCase().replaceAll('[^a-z0-9]', '');
      String apiName = fieldApiName.toLowerCase();
      String lowerDataType = dataType.toLowerCase();

      if (fieldTypes == null) {
        fieldTypes = [
          SELECT
            Keyword__c,
            MatchField__c,
            PIIFieldType__c,
            ComplianceGroup__c,
            IsComplianceGroupFallback__c
          FROM AIPiiFieldType__mdt
          WHERE Active__c = TRUE
          WITH SYSTEM_MODE
          ORDER BY DisplayOrder__c ASC
        ];
      }

      if (complianceGroupsById == null) {
        complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>(
          [
            SELECT MasterLabel, Active__c
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
            fieldGroup.Active__c == true &&
            complianceGroup.equalsIgnoreCase(fieldGroup.MasterLabel)
          )
            fallback = fieldType;
        }
      }

      return fallback == null
        ? AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER
        : fallback.PIIFieldType__c;
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIPiiFieldTypeClassifier',
        'classify'
      );
      return null;
    }
  }
}
