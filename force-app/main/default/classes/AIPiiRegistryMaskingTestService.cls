/*
Class Name: AIPiiRegistryMaskingTestService

=================================================================
=================================================================

Description: Shows an administrator what the registry would send to the AI provider for a real record, with nothing saved and nothing sent.

Step 1: Check the record belongs to the registered object, and read it as the user, so field access and sharing apply
Step 2: Mask each PII field that has a value with AIPiiPseudonymizationService.previewMasking
Step 3: Return the real value, the stand-in and the rule applied for each field

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPiiRegistryMaskingTestService {

    public class AIPiiRegistryMaskingTestServiceException extends Exception {}

    // Runs the masking of a record's PII fields. The record is read as the user, so a field or a record they cannot see is left out, and nothing is written: no mapping, no tally, no log.
    public static AIPiiRegistryDataStructure.MaskingTestResult runMaskingTest(Id registryId, Id recordId) {

        // [1] Refuse a user who may not use the tab, an object that is not there, and a record of another object
        AIAssistSettingsEditorService.requireManager();
        AIPIIRegistry__c registry = AIPiiRegistryEditorService.findRegistry(registryId);
        String objectName = registry.ObjectAPIName__c;
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName.toLowerCase());
        if (recordId == null || objectType == null || recordId.getSobjectType() != objectType) throw new AIPiiRegistryMaskingTestServiceException(Label.AI_PiiRegistry_Error_Test_Record_Invalid);

        // [2] Keep the PII fields that exist, that the user can read and that hold a single value
        Map<String, Schema.SObjectField> fieldTokensByName = objectType.getDescribe().fields.getMap();
        Map<String, String> labelByFieldName = new Map<String, String>();

        for (AIPIIFieldMetadata__c field : [SELECT FieldAPIName__c, FieldLabel__c FROM AIPIIFieldMetadata__c WHERE PIIRegistry__c = :registryId AND IsPII__c = TRUE WITH SYSTEM_MODE ORDER BY FieldLabel__c LIMIT :AIAssistApplicationConstants.PII_MASKING_TEST_MAX_FIELDS]) {

            Schema.SObjectField fieldToken = fieldTokensByName.get(field.FieldAPIName__c.toLowerCase());
            if (fieldToken == null) continue;

            Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
            Boolean isSingleValue = fieldDescribe.getType() != Schema.DisplayType.ADDRESS && fieldDescribe.getType() != Schema.DisplayType.LOCATION;
            if (fieldDescribe.isAccessible() && isSingleValue) labelByFieldName.put(fieldDescribe.getName(), field.FieldLabel__c);
        }

        AIPiiRegistryDataStructure.MaskingTestResult result = new AIPiiRegistryDataStructure.MaskingTestResult();
        if (labelByFieldName.isEmpty()) return result;

        // [3] Read the record as the user
        String soql = 'SELECT ' + String.join(new List<String>(labelByFieldName.keySet()), ', ') + ' FROM ' + objectName + ' WHERE Id = :recordId LIMIT 1';
        List<SObject> records = Database.queryWithBinds(soql, new Map<String, Object>{'recordId' => recordId}, AccessLevel.USER_MODE);
        if (records.isEmpty()) throw new AIPiiRegistryMaskingTestServiceException(Label.AI_PiiRegistry_Error_Test_Record_Not_Found);

        // [4] Mask each field that holds a value, so two values never share one stand-in
        Set<String> valuesInUse = new Set<String>();

        for (String fieldName : new List<String>(labelByFieldName.keySet())) {

            Object rawValue = records[0].get(fieldName);
            if (rawValue == null || String.isBlank(String.valueOf(rawValue))) continue;

            String realValue = String.valueOf(rawValue);
            AIPiiPseudonymizationService.MaskingPreview preview = AIPiiPseudonymizationService.previewMasking(objectName, fieldName, realValue, valuesInUse);
            if (preview == null) continue;

            // [5] Describe the rule that was applied, or why the value was redacted instead
            AIPiiRegistryDataStructure.MaskingTestRow row = new AIPiiRegistryDataStructure.MaskingTestRow();
            row.fieldLabel = labelByFieldName.get(fieldName);
            row.realValue = realValue;
            row.sentValue = preview.fakeValue;
            row.ruleText = preview.isRuleApplied ? preview.strategy : getRedactedText(preview);
            result.rows.add(row);
        }

        return result;
    }

    // Says why a value was redacted instead of masked by its rule.
    private static String getRedactedText(AIPiiPseudonymizationService.MaskingPreview preview) {

        // [1] No rule, or one that is switched off
        if (preview.redactReason == AIAssistApplicationConstants.PII_REDACT_REASON_NO_RULE) return Label.AI_PiiRegistry_Rule_Redacted_No_Rule;

        // [2] A rule whose list of substitutes is used up
        if (preview.redactReason == AIAssistApplicationConstants.PII_REDACT_REASON_EXHAUSTED) return Label.AI_PiiRegistry_Rule_Redacted_Exhausted;

        // [3] A rule whose strategy the package does not apply
        return String.format(Label.AI_PiiRegistry_Rule_Redacted_Strategy, new List<String>{preview.strategy});
    }
}
