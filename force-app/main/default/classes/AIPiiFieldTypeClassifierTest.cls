/*
Class Name: AIPiiFieldTypeClassifierTest

=================================================================
=================================================================

Description: Testing utility for AIPiiFieldTypeClassifier: a field's PII type from its name, label, data type and compliance group, using rules supplied in memory because custom metadata cannot be inserted.

=================================================================
=================================================================
Applicable Classes:

AIPiiFieldTypeClassifier: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPiiFieldTypeClassifierTest {

    // testScenario1: A keyword in the name or label is classified, whatever the case or punctuation -> it matches the keyword rule.
    // testScenario2: An exact API name, a similar name and a data type are classified -> each matches its own rule.
    // testScenario3: A flagged field that matches no rule is classified -> it is Other, because Data Classification already marked it.
    // testScenario4: A missing name, label, type or compliance group is classified -> it is not classified.
    // testScenario5: The compliance group fallback is classified for its own group and another group -> it is used when its group matches and ignored when it does not.

    private static final String GDPR = 'GDPR';
    private static final String TEXT = 'Text';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Define the email, exact name and data type keyword rules
        AIPiiFieldType__mdt emailType = new AIPiiFieldType__mdt(Keyword__c = 'email, e-mail', MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS, PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, IsComplianceGroupFallback__c = false);

        AIPiiFieldType__mdt exactType = new AIPiiFieldType__mdt(Keyword__c = 'ssn__c', MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_API_NAME_EXACT, PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_SSN, IsComplianceGroupFallback__c = false);

        AIPiiFieldType__mdt typeType = new AIPiiFieldType__mdt(Keyword__c = 'phone', MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_DATA_TYPE_CONTAINS, PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE, IsComplianceGroupFallback__c = false);

        // [2] Load the rules into the classifier
        AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>{
            emailType,
            exactType,
            typeType
        };
        AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();

        String byName;
        String byLabel;

        // [3] Classify a field by its name and another by its label
        Test.startTest();
            byName = AIPiiFieldTypeClassifier.classify('Contact_E_Mail__c', 'Work', TEXT, GDPR);
            byLabel = AIPiiFieldTypeClassifier.classify('Field__c', 'Primary EMAIL Address', TEXT, GDPR);
        Test.stopTest();

        // [4] Check both match the email rule, whatever the case or punctuation
        Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, byLabel, 'By label, in any case.');
        Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, byName, 'By name, with its underscores ignored.');
    }

    @IsTest static void testScenario2() {

        // [1] Define the email, exact name and data type keyword rules
        AIPiiFieldType__mdt emailType = new AIPiiFieldType__mdt(Keyword__c = 'email, e-mail', MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS, PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, IsComplianceGroupFallback__c = false);

        AIPiiFieldType__mdt exactType = new AIPiiFieldType__mdt(Keyword__c = 'ssn__c', MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_API_NAME_EXACT, PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_SSN, IsComplianceGroupFallback__c = false);

        AIPiiFieldType__mdt typeType = new AIPiiFieldType__mdt(Keyword__c = 'phone', MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_DATA_TYPE_CONTAINS, PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE, IsComplianceGroupFallback__c = false);

        // [2] Load the rules into the classifier
        AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>{
            emailType,
            exactType,
            typeType
        };
        AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();

        String exact;
        String notExact;
        String byType;

        // [3] Classify an exact name, a similar name and a data type
        Test.startTest();
            exact = AIPiiFieldTypeClassifier.classify('SSN__c', 'Tax Id', TEXT, GDPR);
            notExact = AIPiiFieldTypeClassifier.classify('SSN_Copy__c', 'Tax Id', TEXT, GDPR);
            byType = AIPiiFieldTypeClassifier.classify('Mobile__c', 'Mobile', 'Phone', GDPR);
        Test.stopTest();

        // [4] Check each matches its own rule
        Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_SSN, exact, 'Exact name.');
        Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER, notExact, 'A similar name is not exact.');
        Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE, byType, 'By data type.');
    }

    @IsTest static void testScenario3() {

        // [1] Define the email, exact name and data type keyword rules
        AIPiiFieldType__mdt emailType = new AIPiiFieldType__mdt(Keyword__c = 'email, e-mail', MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS, PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, IsComplianceGroupFallback__c = false);

        AIPiiFieldType__mdt exactType = new AIPiiFieldType__mdt(Keyword__c = 'ssn__c', MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_API_NAME_EXACT, PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_SSN, IsComplianceGroupFallback__c = false);

        AIPiiFieldType__mdt typeType = new AIPiiFieldType__mdt(Keyword__c = 'phone', MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_DATA_TYPE_CONTAINS, PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE, IsComplianceGroupFallback__c = false);

        // [2] Load the rules into the classifier
        AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>{
            emailType,
            exactType,
            typeType
        };
        AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();

        String result;

        // [3] Classify a field that matches no rule
        Test.startTest();
            result = AIPiiFieldTypeClassifier.classify('Favourite_Colour__c', 'Favourite Colour', TEXT, GDPR);
        Test.stopTest();

        // [4] Check it is Other
        Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER, result, 'Treated as PII.');
    }

    @IsTest static void testScenario4() {

        // [1] Define the email, exact name and data type keyword rules
        AIPiiFieldType__mdt emailType = new AIPiiFieldType__mdt(Keyword__c = 'email, e-mail', MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_NAME_OR_LABEL_CONTAINS, PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, IsComplianceGroupFallback__c = false);

        AIPiiFieldType__mdt exactType = new AIPiiFieldType__mdt(Keyword__c = 'ssn__c', MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_API_NAME_EXACT, PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_SSN, IsComplianceGroupFallback__c = false);

        AIPiiFieldType__mdt typeType = new AIPiiFieldType__mdt(Keyword__c = 'phone', MatchField__c = AIAssistApplicationConstants.PII_MATCH_FIELD_DATA_TYPE_CONTAINS, PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE, IsComplianceGroupFallback__c = false);

        // [2] Load the rules into the classifier
        AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>{
            emailType,
            exactType,
            typeType
        };
        AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();

        String noName;
        String noLabel;
        String noType;
        String noGroup;

        // [3] Classify with a missing name, label, type and compliance group
        Test.startTest();
            noName = AIPiiFieldTypeClassifier.classify(null, 'L', TEXT, GDPR);
            noLabel = AIPiiFieldTypeClassifier.classify('F__c', ' ', TEXT, GDPR);
            noType = AIPiiFieldTypeClassifier.classify('F__c', 'L', null, GDPR);
            noGroup = AIPiiFieldTypeClassifier.classify('F__c', 'L', TEXT, null);
        Test.stopTest();

        // [4] Check none is classified
        Assert.isTrue(noName == null && noLabel == null && noType == null && noGroup == null, 'Nothing to classify with.');
    }

    @IsTest static void testScenario5() {

        // [1] Define a HIPAA compliance group and a fallback rule for it
        AIPiiFieldType__mdt fallback = new AIPiiFieldType__mdt(Keyword__c = null, PIIFieldType__c = AIAssistApplicationConstants.PII_FIELD_TYPE_MEDICAL_RECORD, IsComplianceGroupFallback__c = true);
        AIPiiComplianceGroup__mdt hipaa = (AIPiiComplianceGroup__mdt) JSON.deserialize('{"attributes":{"type":"LoomConnect__AIPiiComplianceGroup__mdt"},"Id":"m01000000000001AAA","MasterLabel":"HIPAA","LoomConnect__IsActive__c":true}', AIPiiComplianceGroup__mdt.class);
        fallback = (AIPiiFieldType__mdt) JSON.deserialize('{"attributes":{"type":"LoomConnect__AIPiiFieldType__mdt"},"LoomConnect__PIIFieldType__c":"' + AIAssistApplicationConstants.PII_FIELD_TYPE_MEDICAL_RECORD + '","LoomConnect__IsComplianceGroupFallback__c":true,"LoomConnect__ComplianceGroup__c":"m01000000000001AAA"}', AIPiiFieldType__mdt.class);

        // [2] Load the rule and group into the classifier
        AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>{
            fallback
        };
        AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>{
            hipaa.Id => hipaa
        };

        String matched;
        String unmatched;

        // [3] Classify a field for the HIPAA group and for another group
        Test.startTest();
            matched = AIPiiFieldTypeClassifier.classify('Chart__c', 'Chart', TEXT, 'hipaa');
            unmatched = AIPiiFieldTypeClassifier.classify('Chart__c', 'Chart', TEXT, GDPR);
        Test.stopTest();

        // [4] Check the fallback applies to its own group only
        Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_MEDICAL_RECORD, matched, 'The fallback for its own group, in any case.');
        Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER, unmatched, 'Not for another group.');
    }
}
