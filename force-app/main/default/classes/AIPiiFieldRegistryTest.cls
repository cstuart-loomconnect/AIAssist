/*
Class Name: AIPiiFieldRegistryTest

=================================================================
=================================================================

Description: Testing utility for AIPiiFieldRegistry: which fields are personal data, and of what type.

=================================================================
=================================================================
Applicable Classes:

AIPiiFieldRegistry: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIPiiFieldRegistryTest {
  // testScenario1: A field registered as PII returns its type and is reported as PII; an unregistered field and a field flagged not-PII are neither.
  // testScenario2: An object with no registry has no PII fields at all, so nothing is masked until a registry has been synced.
  // testScenario3: Blank object or field names return null, false and an empty map without a query.
  // testScenario4: The registry of an object is queried once and cached, however many fields are asked about.

  private static final String CONTACT = 'Contact';
  private static final String LEAD = 'Lead';
  private static final String EMAIL = 'Email';

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
    // [1] Create a registry with a PII email field and a not-PII title field
    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      CONTACT,
      true
    )[0];
    AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registry.Id,
      CONTACT,
      EMAIL,
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      true
    );
    AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registry.Id,
      CONTACT,
      'Title',
      null,
      true
    );

    String emailType;
    Boolean isEmailPii;
    Boolean isTitlePii;
    String unknownType;

    // [2] Look up the types and PII flags of three fields
    Test.startTest();
    emailType = AIPiiFieldRegistry.getFieldType(CONTACT, EMAIL);
    isEmailPii = AIPiiFieldRegistry.isPii(CONTACT, EMAIL);

    isTitlePii = AIPiiFieldRegistry.isPii(CONTACT, 'Title');
    unknownType = AIPiiFieldRegistry.getFieldType(CONTACT, 'Department');
    Test.stopTest();

    // [3] Check the email is PII and the other two are not
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
    // [1] Declare what the test reads back
    Boolean isPii;
    Map<String, String> fieldTypes;

    // [2] Ask about an object that has no registry
    Test.startTest();
    isPii = AIPiiFieldRegistry.isPii('Account', 'Phone');
    fieldTypes = AIPiiFieldRegistry.getFieldTypes('Account');
    Test.stopTest();

    // [3] Check nothing is PII and the map is empty
    Assert.isFalse(isPii, 'With no registry nothing is PII.');
    Assert.isTrue(fieldTypes.isEmpty(), 'And the map is empty.');
  }

  @IsTest
  static void testScenario3() {
    // [1] Note the query count before the calls
    Integer queriesBefore = Limits.getQueries();
    String fieldType;
    Boolean isPii;
    Map<String, String> fieldTypes;
    Integer queriesUsed;

    // [2] Ask with blank object and field names
    Test.startTest();
    fieldType = AIPiiFieldRegistry.getFieldType('', EMAIL);
    isPii = AIPiiFieldRegistry.isPii(CONTACT, null);
    fieldTypes = AIPiiFieldRegistry.getFieldTypes(null);

    queriesUsed = Limits.getQueries() - queriesBefore;
    Test.stopTest();

    // [3] Check null, false, an empty map and no queries
    Assert.isNull(fieldType, 'No object, no type.');
    Assert.isFalse(isPii, 'No field, not PII.');
    Assert.isTrue(fieldTypes.isEmpty(), 'No object, no fields.');

    Assert.areEqual(0, queriesUsed, 'Blank input must not cost a query.');
  }

  @IsTest
  static void testScenario4() {
    // [1] Create a registry with two PII fields for Lead
    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      LEAD,
      true
    )[0];
    AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registry.Id,
      LEAD,
      EMAIL,
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      true
    );
    AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registry.Id,
      LEAD,
      'Phone',
      AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE,
      true
    );

    // [2] Note the query count before the lookups
    Integer queriesBefore = Limits.getQueries();
    Integer queriesUsed;

    // [3] Look up fifty fields on the same object
    Test.startTest();
    for (Integer i = 0; i < 50; i++)
      AIPiiFieldRegistry.isPii(LEAD, i < 25 ? EMAIL : 'Phone');
    queriesUsed = Limits.getQueries() - queriesBefore;
    Test.stopTest();

    // [4] Check the registry was queried once
    Assert.areEqual(
      1,
      queriesUsed,
      'Fifty lookups against one object cost one query.'
    );
  }
}
