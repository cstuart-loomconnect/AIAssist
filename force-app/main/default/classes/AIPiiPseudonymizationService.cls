/*
Class Name: AIPiiPseudonymizationService

=================================================================
=================================================================

Description: Masks personal data before it reaches the model and restores it after, and keeps the evidence of what it masked.

Step 1: Return a value unchanged when its field is not PII, using AIPiiFieldRegistry
Step 2: Reuse the stand-in already paired with the value in the conversation, using AIPiiMappingService
Step 3: Otherwise pick an unused substitute from the field type's AIPiiDataMaskingRule__mdt, or a generic REDACTED value
Step 4: Remember the pairing and tally what was masked, by object and field
Step 5: Turn a reply's stand-ins back into real values with restore(), and hand over the tallies with takeTallies()

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPiiPseudonymizationService {

    // What was masked for one object and field since the last takeTallies().
    public class MaskingTally {
        public String sourceObject;
        public String sourceField;
        public String piiFieldType;
        public String complianceGroup;
        public String maskingStrategy;
        public Decimal valuesMasked = 0;
        public String outcome = AIAssistApplicationConstants.MASKING_OUTCOME_MASKED;
    }

    private static Map<String, MaskingTally> tallyByKey = new Map<String, MaskingTally>();

    // A missing rule is reported once per field type per transaction, not once per value masked.
    private static Set<String> fieldTypesAlreadyLogged = new Set<String>();

    // Tests set these two instead of reading custom metadata, which cannot be inserted.
    @TestVisible
    private static Map<String, AIPiiDataMaskingRule__mdt> ruleByFieldType;
    @TestVisible
    private static Map<String, String> complianceGroupByFieldType;

    // A field that is not PII comes back unchanged. Otherwise the stand-in already paired with this value in the conversation, or a new one that is remembered. Blank for invalid input. Only the SubstituteFromList strategy produces a stand-in: any other strategy, a missing or inactive rule, or a list whose every value is already used in the conversation falls back to a generic REDACTED-<digits> value and says so in the platform log, once per field type per transaction. Every stand-in is unique within a conversation, because two real values sharing one fake value could not be restored correctly. Tallies hold names and counts only, never values.
    public static String pseudonymize(Id conversationId, String objectApiName, String fieldApiName, String realValue) {

        try {

            // [1] Refuse invalid input
            if (conversationId == null || conversationId.getSobjectType() != AIConversation__c.SObjectType || String.isBlank(objectApiName) || String.isBlank(fieldApiName) || String.isBlank(realValue)) return '';

            // [2] Return the value unchanged when the field is not PII
            String fieldType = AIPiiFieldRegistry.getFieldType(objectApiName, fieldApiName);
            if (String.isBlank(fieldType)) return realValue;

            // [3] Read the masking rules once per transaction, because they do not change mid-conversation
            if (ruleByFieldType == null) {

                ruleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>();
                complianceGroupByFieldType = new Map<String, String>();

                for (AIPiiFieldType__mdt fieldTypeRule : [SELECT PIIFieldType__c, ComplianceGroup__r.MasterLabel, MaskingRule__r.Strategy__c, MaskingRule__r.SubstituteValues__c, MaskingRule__r.IsActive__c FROM AIPiiFieldType__mdt WHERE IsActive__c = TRUE AND MaskingRule__c != NULL WITH SYSTEM_MODE]) {

                    ruleByFieldType.put(fieldTypeRule.PIIFieldType__c, fieldTypeRule.MaskingRule__r);
                    complianceGroupByFieldType.put(fieldTypeRule.PIIFieldType__c, fieldTypeRule.ComplianceGroup__r == null ? null : fieldTypeRule.ComplianceGroup__r.MasterLabel);
                }
            }

            AIPiiDataMaskingRule__mdt maskingRule = ruleByFieldType.get(fieldType);
            String strategy = maskingRule == null ? null : maskingRule.Strategy__c;

            // [4] Reuse the stand-in already paired with this value in the conversation
            String fakeValue = AIPiiMappingService.getFakeValue(conversationId, realValue);

            if (String.isBlank(fakeValue)) {

                if (maskingRule != null && maskingRule.IsActive__c && maskingRule.Strategy__c == AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST) {

                    // [5] Collect every value already in use on either side of a pairing, because reusing a fake value, or choosing another record's real value, would make restoring ambiguous
                    Map<String, String> fakeByReal = AIPiiMappingService.getMapping(conversationId);
                    Set<String> valuesInUse = new Set<String>(fakeByReal.values());
                    valuesInUse.addAll(fakeByReal.keySet());

                    // [6] Keep the substitutes from the rule that are not in use
                    List<String> candidates = new List<String>();

                    for (String candidate : String.isBlank(maskingRule.SubstituteValues__c) ? new List<String>() : maskingRule.SubstituteValues__c.split(',')) {

                        if (String.isNotBlank(candidate) && !valuesInUse.contains(candidate.trim())) candidates.add(candidate.trim());
                    }

                    // [7] Pick one at random, or log once that the rule has run out of values
                    if (!candidates.isEmpty()) {

                        fakeValue = candidates[Integer.valueOf(Math.floor(Math.random() * candidates.size()))];

                    } else if (!fieldTypesAlreadyLogged.contains(fieldType)) {

                        fieldTypesAlreadyLogged.add(fieldType);
                        AIPlatformLogManager.logCustomMessage('Every substitute value for PII field type "' + fieldType + '" is already used in this conversation. A generic redacted value was used; add more values to the masking rule.', null, 'AIPiiPseudonymizationService', 'pseudonymize', conversationId);
                    }

                } else if (!fieldTypesAlreadyLogged.contains(fieldType)) {

                    // [8] No usable rule - log it once for this field type
                    fieldTypesAlreadyLogged.add(fieldType);
                    AIPlatformLogManager.logCustomMessage('No usable Substitute From List masking rule for PII field type "' + fieldType + '". A generic redacted value was used.', null, 'AIPiiPseudonymizationService', 'pseudonymize', null);
                }

                // [9] Fall back to a REDACTED value with a random suffix, so distinct real values never share one fake value
                if (String.isBlank(fakeValue)) {

                    String digits = '';

                    for (Integer digitIndex = 0; digitIndex < 10; digitIndex++) digits += String.valueOf(Integer.valueOf(Math.floor(Math.random() * 10)));

                    fakeValue = 'REDACTED-' + digits;
                    strategy = 'Redacted';
                }

                // [10] Remember the pairing
                AIPiiMappingService.addMapping(conversationId, realValue, fakeValue);
            }

            // [11] Count the value in the tally for its object and field
            String tallyKey = objectApiName + '.' + fieldApiName;
            MaskingTally tally = tallyByKey.get(tallyKey);

            if (tally == null) {

                tally = new MaskingTally();
                tally.sourceObject = objectApiName;
                tally.sourceField = fieldApiName;
                tally.piiFieldType = fieldType;
                tally.complianceGroup = complianceGroupByFieldType.get(fieldType);
                tally.maskingStrategy = strategy;
                tallyByKey.put(tallyKey, tally);
            }

            tally.valuesMasked++;

            // [12] Return the stand-in
            return fakeValue;

        } catch (Exception ex) {

            AIPlatformLogManager.logException(ex, 'AIPiiPseudonymizationService', 'pseudonymize');

            // [13] The value is withheld, but the request must not go as though masking had worked, so record a failed tally to stop it
            MaskingTally failedTally = new MaskingTally();
            failedTally.sourceObject = objectApiName;
            failedTally.sourceField = fieldApiName;
            failedTally.outcome = AIAssistApplicationConstants.MASKING_OUTCOME_FAILED;
            failedTally.valuesMasked = 0;
            tallyByKey.put('FAILED:' + objectApiName + '.' + fieldApiName, failedTally);

            return '';
        }
    }

    // Turns a stand-in back into the real value it was generated from, for restoring a reply before the user sees it. A value that is not a known stand-in comes back unchanged.
    public static String restore(Id conversationId, String fakeValue) {

        // [1] Nothing to restore
        if (String.isBlank(fakeValue)) return fakeValue;

        // [2] Return the real value, or the value as it came when it is not a known stand-in
        String realValue = AIPiiMappingService.getRealValue(conversationId, fakeValue);

        return realValue != null ? realValue : fakeValue;
    }

    // Returns what has been masked since the last call, one tally per object and field, and clears them. The caller attaches them to the step that sent the data.
    public static List<MaskingTally> takeTallies() {

        // [1] Hand over the tallies and start again with none
        List<MaskingTally> tallies = tallyByKey.values();
        tallyByKey = new Map<String, MaskingTally>();

        return tallies;
    }
}
