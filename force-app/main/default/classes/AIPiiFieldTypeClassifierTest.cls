/*
Class Name: AIPiiFieldTypeClassifierTest

=================================================================
=================================================================

Description: Testing utility for AIPiiFieldTypeClassifier: a field's PII type from its name, label, data type and compliance group, using rules supplied in memory because custom metadata cannot be inserted.

=================================================================
=================================================================
Applicable Classes:

AIPiiFieldTypeClassifier

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIPiiFieldTypeClassifierTest {
  // testScenario1: A keyword in the name or label matches, whatever the case or punctuation.
  // testScenario2: An exact API name and a data type keyword match their own rules.
  // testScenario3: A flagged field that matches no rule is Other, because Data Classification already marked it.
  // testScenario4: A missing name, label, type or compliance group is not classified.
  // testScenario5: The compliance group fallback is used when its group matches and ignored when it does not.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  @IsTest
  static void testScenario1() {
    AIPiiFieldType__mdt emailType = new AIPiiFieldType__mdt(
      Keyword__c = 'email, e-mail',
      MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS,
      PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      IsComplianceGroupFallback__c = false
    );
    AIPiiFieldType__mdt exactType = new AIPiiFieldType__mdt(
      Keyword__c = 'ssn__c',
      MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_API_NAME_EXACT,
      PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_SSN,
      IsComplianceGroupFallback__c = false
    );
    AIPiiFieldType__mdt typeType = new AIPiiFieldType__mdt(
      Keyword__c = 'phone',
      MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_DATA_TYPE_CONTAINS,
      PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE,
      IsComplianceGroupFallback__c = false
    );
    AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>{
      emailType,
      exactType,
      typeType
    };
    AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();

    Test.startTest();
    String byName = AIPiiFieldTypeClassifier.classify(
      'Contact_E_Mail__c',
      'Work',
      'Text',
      'GDPR'
    );
    String byLabel = AIPiiFieldTypeClassifier.classify(
      'Field__c',
      'Primary EMAIL Address',
      'Text',
      'GDPR'
    );
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      byLabel,
      'By label, in any case.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      byName,
      'By name, with its underscores ignored.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIPiiFieldType__mdt emailType = new AIPiiFieldType__mdt(
      Keyword__c = 'email, e-mail',
      MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS,
      PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      IsComplianceGroupFallback__c = false
    );
    AIPiiFieldType__mdt exactType = new AIPiiFieldType__mdt(
      Keyword__c = 'ssn__c',
      MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_API_NAME_EXACT,
      PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_SSN,
      IsComplianceGroupFallback__c = false
    );
    AIPiiFieldType__mdt typeType = new AIPiiFieldType__mdt(
      Keyword__c = 'phone',
      MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_DATA_TYPE_CONTAINS,
      PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE,
      IsComplianceGroupFallback__c = false
    );
    AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>{
      emailType,
      exactType,
      typeType
    };
    AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();

    Test.startTest();
    String exact = AIPiiFieldTypeClassifier.classify(
      'SSN__c',
      'Tax Id',
      'Text',
      'GDPR'
    );
    String notExact = AIPiiFieldTypeClassifier.classify(
      'SSN_Copy__c',
      'Tax Id',
      'Text',
      'GDPR'
    );
    String byType = AIPiiFieldTypeClassifier.classify(
      'Mobile__c',
      'Mobile',
      'Phone',
      'GDPR'
    );
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.PII_FIELD_TYPE_SSN,
      exact,
      'Exact name.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER,
      notExact,
      'A similar name is not exact.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE,
      byType,
      'By data type.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIPiiFieldType__mdt emailType = new AIPiiFieldType__mdt(
      Keyword__c = 'email, e-mail',
      MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS,
      PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      IsComplianceGroupFallback__c = false
    );
    AIPiiFieldType__mdt exactType = new AIPiiFieldType__mdt(
      Keyword__c = 'ssn__c',
      MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_API_NAME_EXACT,
      PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_SSN,
      IsComplianceGroupFallback__c = false
    );
    AIPiiFieldType__mdt typeType = new AIPiiFieldType__mdt(
      Keyword__c = 'phone',
      MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_DATA_TYPE_CONTAINS,
      PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE,
      IsComplianceGroupFallback__c = false
    );
    AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>{
      emailType,
      exactType,
      typeType
    };
    AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();

    Test.startTest();
    String result = AIPiiFieldTypeClassifier.classify(
      'Favourite_Colour__c',
      'Favourite Colour',
      'Text',
      'GDPR'
    );
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER,
      result,
      'Treated as PII.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIPiiFieldType__mdt emailType = new AIPiiFieldType__mdt(
      Keyword__c = 'email, e-mail',
      MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS,
      PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      IsComplianceGroupFallback__c = false
    );
    AIPiiFieldType__mdt exactType = new AIPiiFieldType__mdt(
      Keyword__c = 'ssn__c',
      MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_API_NAME_EXACT,
      PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_SSN,
      IsComplianceGroupFallback__c = false
    );
    AIPiiFieldType__mdt typeType = new AIPiiFieldType__mdt(
      Keyword__c = 'phone',
      MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_DATA_TYPE_CONTAINS,
      PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE,
      IsComplianceGroupFallback__c = false
    );
    AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>{
      emailType,
      exactType,
      typeType
    };
    AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();

    Test.startTest();
    String noName = AIPiiFieldTypeClassifier.classify(
      null,
      'L',
      'Text',
      'GDPR'
    );
    String noLabel = AIPiiFieldTypeClassifier.classify(
      'F__c',
      ' ',
      'Text',
      'GDPR'
    );
    String noType = AIPiiFieldTypeClassifier.classify(
      'F__c',
      'L',
      null,
      'GDPR'
    );
    String noGroup = AIPiiFieldTypeClassifier.classify(
      'F__c',
      'L',
      'Text',
      null
    );
    Test.stopTest();

    Assert.isTrue(
      noName == null && noLabel == null && noType == null && noGroup == null,
      'Nothing to classify with.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIPiiFieldType__mdt fallback = new AIPiiFieldType__mdt(
      Keyword__c = null,
      PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_MEDICAL_RECORD,
      IsComplianceGroupFallback__c = true
    );
    AIPiiComplianceGroup__mdt hipaa = (AIPiiComplianceGroup__mdt) JSON.deserialize(
      '{"attributes":{"type":"LoomConnect__AIPiiComplianceGroup__mdt"},"Id":"m01000000000001AAA","MasterLabel":"HIPAA","LoomConnect__Active__c":true}',
      AIPiiComplianceGroup__mdt.class
    );
    fallback = (AIPiiFieldType__mdt) JSON.deserialize(
      '{"attributes":{"type":"LoomConnect__AIPiiFieldType__mdt"},"LoomConnect__PIIFieldType__c":"' +
        AIAssistApplicationConstants.PII_FIELD_TYPE_MEDICAL_RECORD +
        '","LoomConnect__IsComplianceGroupFallback__c":true,"LoomConnect__ComplianceGroup__c":"m01000000000001AAA"}',
      AIPiiFieldType__mdt.class
    );
    AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>{
      fallback
    };
    AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>{
      hipaa.Id => hipaa
    };

    Test.startTest();
    String matched = AIPiiFieldTypeClassifier.classify(
      'Chart__c',
      'Chart',
      'Text',
      'hipaa'
    );
    String unmatched = AIPiiFieldTypeClassifier.classify(
      'Chart__c',
      'Chart',
      'Text',
      'GDPR'
    );
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.PII_FIELD_TYPE_MEDICAL_RECORD,
      matched,
      'The fallback for its own group, in any case.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER,
      unmatched,
      'Not for another group.'
    );
  }
}
