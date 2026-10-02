/*
Class Name: AIPiiPseudonymizationService

=================================================================
=================================================================

Description: Masks personal data before it reaches the model and restores it after, using
AIPiiFieldRegistry (is this field PII, and of what type), AIPiiDataMaskingRule__mdt (what to
use instead) and AIPiiMappingService (which fake value stands in for which real one).

Only the SubstituteFromList strategy produces a stand-in. Any other strategy, a missing or
inactive rule, or a list whose every value is already used in the conversation falls back to a
generic REDACTED-<digits> value and says so in the platform log. Every stand-in is unique within
a conversation: two real values sharing one fake value could not be restored correctly.

It also keeps the evidence of what it did. For each object and field, a tally of how many
values were masked, by which strategy, under which compliance group. takeTallies() hands those to
the caller to attach to the execution step that sent the data, and resets them. Names and counts
only, never values.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Masking evidence tallies added. Single-use helpers inlined. Compliance group read with the rule.
*/

public inherited sharing class AIPiiPseudonymizationService {
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

  @TestVisible
  private static Map<String, AIPiiDataMaskingRule__mdt> ruleByFieldType; // Tests set these two instead of reading custom metadata, which cannot be inserted.
  @TestVisible
  private static Map<String, String> complianceGroupByFieldType;
  private static Map<String, MaskingTally> tallyByKey = new Map<String, MaskingTally>();

  // A field that is not PII comes back unchanged. Otherwise the stand-in already paired with this value in the conversation, or a new one that is remembered. Blank for invalid input.
  public static String pseudonymize(
    Id conversationId,
    String objectApiName,
    String fieldApiName,
    String realValue
  ) {
    try {
      if (
        conversationId == null ||
        conversationId.getSobjectType() != AIConversation__c.SObjectType ||
        String.isBlank(objectApiName) ||
        String.isBlank(fieldApiName) ||
        String.isBlank(realValue)
      )
        return '';

      String fieldType = AIPiiFieldRegistry.getFieldType(
        objectApiName,
        fieldApiName
      );
      if (String.isBlank(fieldType))
        return realValue;

      // Masking rules do not change mid-conversation, so they are read once per transaction.
      if (ruleByFieldType == null) {
        ruleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>();
        complianceGroupByFieldType = new Map<String, String>();
        for (AIPiiFieldType__mdt fieldTypeRule : [
          SELECT
            PIIFieldType__c,
            ComplianceGroup__r.MasterLabel,
            MaskingRule__r.Strategy__c,
            MaskingRule__r.SubstituteValues__c,
            MaskingRule__r.Active__c
          FROM AIPiiFieldType__mdt
          WHERE Active__c = TRUE AND MaskingRule__c != NULL
          WITH SYSTEM_MODE
        ]) {
          ruleByFieldType.put(
            fieldTypeRule.PIIFieldType__c,
            fieldTypeRule.MaskingRule__r
          );
          complianceGroupByFieldType.put(
            fieldTypeRule.PIIFieldType__c,
            fieldTypeRule.ComplianceGroup__r == null
              ? null
              : fieldTypeRule.ComplianceGroup__r.MasterLabel
          );
        }
      }

      AIPiiDataMaskingRule__mdt maskingRule = ruleByFieldType.get(fieldType);
      String strategy = maskingRule == null ? null : maskingRule.Strategy__c;

      String fakeValue = AIPiiMappingService.getFakeValue(
        conversationId,
        realValue
      );

      if (String.isBlank(fakeValue)) {
        if (
          maskingRule != null &&
          maskingRule.Active__c &&
          maskingRule.Strategy__c ==
          AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST
        ) {
          // Both sides of every pairing: reusing a fake value, or choosing one that is another record's real value, would make restoring ambiguous.
          Map<String, String> fakeByReal = AIPiiMappingService.getMapping(
            conversationId
          );
          Set<String> valuesInUse = new Set<String>(fakeByReal.values());
          valuesInUse.addAll(fakeByReal.keySet());

          List<String> candidates = new List<String>();
          for (
            String candidate : String.isBlank(maskingRule.SubstituteValues__c)
              ? new List<String>()
              : maskingRule.SubstituteValues__c.split(',')
          ) {
            if (
              String.isNotBlank(candidate) &&
              !valuesInUse.contains(candidate.trim())
            )
              candidates.add(candidate.trim());
          }

          if (!candidates.isEmpty()) {
            fakeValue = candidates[
              Integer.valueOf(Math.floor(Math.random() * candidates.size()))
            ];
          } else {
            AIPlatformLogManager.logCustomMessage(
              'Every substitute value for PII field type "' +
                fieldType +
                '" is already used in this conversation. A generic redacted value was used; add more values to the masking rule.',
              null,
              'AIPiiPseudonymizationService',
              'pseudonymize',
              conversationId
            );
          }
        } else {
          AIPlatformLogManager.logCustomMessage(
            'No usable Substitute From List masking rule for PII field type "' +
              fieldType +
              '". A generic redacted value was used.',
            null,
            'AIPiiPseudonymizationService',
            'pseudonymize',
            null
          );
        }

        if (String.isBlank(fakeValue)) {
          // A random suffix keeps each fallback unique, so distinct real values never collide on one fake value.
          String digits = '';
          for (Integer digitIndex = 0; digitIndex < 10; digitIndex++)
            digits += String.valueOf(
              Integer.valueOf(Math.floor(Math.random() * 10))
            );
          fakeValue = 'REDACTED-' + digits;
          strategy = 'Redacted';
        }

        AIPiiMappingService.addMapping(conversationId, realValue, fakeValue);
      }

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

      return fakeValue;
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIPiiPseudonymizationService',
        'pseudonymize'
      );

      // The value is withheld, but the request must not go as though masking had worked: the failed tally stops it.
      MaskingTally failedTally = new MaskingTally();
      failedTally.sourceObject = objectApiName;
      failedTally.sourceField = fieldApiName;
      failedTally.outcome = AIAssistApplicationConstants.MASKING_OUTCOME_FAILED;
      failedTally.valuesMasked = 0;
      tallyByKey.put(
        'FAILED:' + objectApiName + '.' + fieldApiName,
        failedTally
      );

      return '';
    }
  }

  // Turns a stand-in back into the real value it was generated from, for restoring a reply before the user sees it. A value that is not a known stand-in comes back unchanged.
  public static String restore(Id conversationId, String fakeValue) {
    if (String.isBlank(fakeValue))
      return fakeValue;

    String realValue = AIPiiMappingService.getRealValue(
      conversationId,
      fakeValue
    );

    return realValue != null ? realValue : fakeValue;
  }

  // What has been masked since the last call, one tally per object and field, and clears them. The caller attaches them to the step that sent the data.
  public static List<MaskingTally> takeTallies() {
    List<MaskingTally> tallies = tallyByKey.values();
    tallyByKey = new Map<String, MaskingTally>();

    return tallies;
  }
}
