/*
Class Name: AIPiiFieldRegistryTest

=================================================================
=================================================================

Description: Testing utility for AIPiiFieldRegistry: which fields are personal data, and of what type.

=================================================================
=================================================================
Applicable Classes:

AIPiiFieldRegistry

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIPiiFieldRegistryTest {
  // testScenario1: A field registered as PII returns its type and is reported as PII; an unregistered field and a field flagged not-PII are neither.
  // testScenario2: An object with no registry has no PII fields at all, so nothing is masked until a registry has been synced.
  // testScenario3: Blank object or field names return null, false and an empty map without a query.
  // testScenario4: The registry of an object is queried once and cached, however many fields are asked about.

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
    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      'Contact',
      true
    )[0];
    AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registry.Id,
      'Contact',
      'Email',
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      true
    );
    AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registry.Id,
      'Contact',
      'Title',
      null,
      true
    );

    Test.startTest();
    String emailType = AIPiiFieldRegistry.getFieldType('Contact', 'Email');
    Boolean isEmailPii = AIPiiFieldRegistry.isPii('Contact', 'Email');
    Boolean isTitlePii = AIPiiFieldRegistry.isPii('Contact', 'Title');
    String unknownType = AIPiiFieldRegistry.getFieldType(
      'Contact',
      'Department'
    );
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      emailType,
      'A registered PII field returns its type.'
    );
    Assert.isTrue(isEmailPii, 'A registered PII field is PII.');
    Assert.isFalse(isTitlePii, 'A field flagged not-PII is not PII.');
    Assert.isNull(unknownType, 'An unregistered field has no type.');
  }

  @IsTest
  static void testScenario2() {
    Test.startTest();
    Boolean isPii = AIPiiFieldRegistry.isPii('Account', 'Phone');
    Map<String, String> fieldTypes = AIPiiFieldRegistry.getFieldTypes(
      'Account'
    );
    Test.stopTest();

    Assert.isFalse(isPii, 'With no registry nothing is PII.');
    Assert.isTrue(fieldTypes.isEmpty(), 'And the map is empty.');
  }

  @IsTest
  static void testScenario3() {
    Integer queriesBefore = Limits.getQueries();

    Test.startTest();
    String type = AIPiiFieldRegistry.getFieldType('', 'Email');
    Boolean isPii = AIPiiFieldRegistry.isPii('Contact', null);
    Map<String, String> fieldTypes = AIPiiFieldRegistry.getFieldTypes(null);
    Integer queriesUsed = Limits.getQueries() - queriesBefore;
    Test.stopTest();

    Assert.isNull(type, 'No object, no type.');
    Assert.isFalse(isPii, 'No field, not PII.');
    Assert.isTrue(fieldTypes.isEmpty(), 'No object, no fields.');
    Assert.areEqual(0, queriesUsed, 'Blank input must not cost a query.');
  }

  @IsTest
  static void testScenario4() {
    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      'Lead',
      true
    )[0];
    AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registry.Id,
      'Lead',
      'Email',
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      true
    );
    AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registry.Id,
      'Lead',
      'Phone',
      AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE,
      true
    );
    Integer queriesBefore = Limits.getQueries();

    Test.startTest();
    for (Integer i = 0; i < 50; i++)
      AIPiiFieldRegistry.isPii('Lead', i < 25 ? 'Email' : 'Phone');
    Integer queriesUsed = Limits.getQueries() - queriesBefore;
    Test.stopTest();

    Assert.areEqual(
      1,
      queriesUsed,
      'Fifty lookups against one object cost one query.'
    );
  }
}
