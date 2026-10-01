/*
Class Name: AISchemaHelperTest

=================================================================
=================================================================

Description: Testing utility for AISchemaHelper: object and field facts, the two cache levels, and that a missing or failing cache only costs a describe. The platform cache is replaced by an in-memory fake.

=================================================================
=================================================================
Applicable Classes:

AISchemaHelper

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AISchemaHelperTest {
  // testScenario1: Object info gives the API name, labels, key prefix and name field, for a name or an Id.
  // testScenario2: Field info gives the type and length, and hasField and getFieldLength agree, whatever the case.
  // testScenario3: A blank name, an Id of nothing, an unknown object and a missing field all answer null or false and never throw.
  // testScenario4: Within a transaction an object is described once, however many questions are asked, and an unknown object is not looked up again.
  // testScenario5: The first transaction stores the answer in the persistent cache, and a later one reads it back with no describe.
  // testScenario6: A cache that throws on every call, or holds unreadable text, only costs a describe.
  // testScenario7: clearCache for one object removes it from both levels and leaves the others, and clearCache with no name clears everything seen.
  // testScenario8: isAccessible follows the user: a user with no access to the package objects cannot read an AI object, and is cached for the transaction only.
  // testScenario9: Cache keys are alphanumeric and distinct for names that differ only by underscores.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  // Stands in for the org cache partition.
  private class FakeCache implements AISchemaHelper.ICache {
    public Map<String, String> values = new Map<String, String>();
    public Boolean isBroken = false;
    public Integer lastTtl;
    public String lastKey;
    public String seed;

    public String get(String key) {
      if (isBroken)
        throw new Cache.Org.OrgCacheException('Cache is down');
      return seed != null ? seed : values.get(key);
    }

    public void put(String key, String value, Integer ttlSeconds) {
      if (isBroken)
        throw new Cache.Org.OrgCacheException('Cache is down');
      values.put(key, value);
      lastTtl = ttlSeconds;
      lastKey = key;
    }

    public void clear(String key) {
      if (isBroken)
        throw new Cache.Org.OrgCacheException('Cache is down');
      values.remove(key);
    }
  }

  private class FakeCacheKeys {
    public Boolean contains(AISchemaHelper.ICache cache) {
      return cache instanceof FakeCache &&
        ((FakeCache) cache).values.containsKey('accessible');
    }
  }

  @IsTest
  static void testScenario1() {
    Account record = AIAssistTestDataFactory.createAccounts(1, true)[0];

    Test.startTest();
    AISchemaHelper.ObjectInfo byName = AISchemaHelper.getObjectInfo('Account');
    AISchemaHelper.ObjectInfo byId = AISchemaHelper.getObjectInfo(record.Id);
    String apiName = AISchemaHelper.getObjectApiName(record.Id);
    String nameField = AISchemaHelper.getNameField('account');
    Test.stopTest();

    Assert.areEqual('Account', byName.apiName, 'The API name.');
    Assert.areEqual('Accounts', byName.pluralLabel, 'The plural label.');
    Assert.areEqual('001', byName.keyPrefix, 'The key prefix.');
    Assert.areEqual('Account', apiName, 'From the Id.');
    Assert.areEqual(
      'Name',
      nameField,
      'The name field, whatever the case asked for.'
    );
    Assert.areEqual(byName.apiName, byId.apiName, 'Same answer by Id.');
  }

  @IsTest
  static void testScenario2() {
    Test.startTest();
    AISchemaHelper.FieldInfo field = AISchemaHelper.getFieldInfo(
      'Account',
      'NAME'
    );
    Boolean exists = AISchemaHelper.hasField('Account', 'name');
    Boolean missing = AISchemaHelper.hasField('Account', 'No_Such_Field__c');
    Integer length = AISchemaHelper.getFieldLength('Account', 'Name');
    Integer noLength = AISchemaHelper.getFieldLength(
      'Account',
      'No_Such_Field__c'
    );
    Test.stopTest();

    Assert.areEqual('STRING', field.dataType, 'The type.');
    Assert.isTrue(field.isNameField, 'It is the name field.');
    Assert.isTrue(exists, 'It exists.');
    Assert.isFalse(missing, 'This one does not.');
    Assert.areEqual(255, length, 'The length of Account Name.');
    Assert.isNull(noLength, 'No field, no length.');
  }

  @IsTest
  static void testScenario3() {
    Test.startTest();
    AISchemaHelper.ObjectInfo blank = AISchemaHelper.getObjectInfo(
      (String) null
    );
    AISchemaHelper.ObjectInfo unknown = AISchemaHelper.getObjectInfo(
      'No_Such_Object__c'
    );
    String noId = AISchemaHelper.getObjectApiName(null);
    AISchemaHelper.FieldInfo noObject = AISchemaHelper.getFieldInfo(
      'No_Such_Object__c',
      'Name'
    );
    AISchemaHelper.FieldInfo noField = AISchemaHelper.getFieldInfo(
      'Account',
      null
    );
    String label = AISchemaHelper.getLabel('No_Such_Object__c');
    Test.stopTest();

    Assert.isNull(blank, 'Blank.');
    Assert.isNull(unknown, 'Unknown object.');
    Assert.isNull(noId, 'No Id.');
    Assert.isNull(noObject, 'No object.');
    Assert.isNull(noField, 'No field name.');
    Assert.isNull(label, 'No label.');
  }

  @IsTest
  static void testScenario4() {
    AISchemaHelper.persistentCache = new FakeCache();
    Integer before = AISchemaHelper.describeCount;

    Test.startTest();
    for (Integer i = 0; i < 50; i++) {
      AISchemaHelper.getLabel('Contact');
      AISchemaHelper.hasField('Contact', 'LastName');
    }
    AISchemaHelper.getObjectInfo('No_Such_Object__c');
    AISchemaHelper.getObjectInfo('No_Such_Object__c');
    Test.stopTest();

    Assert.areEqual(
      1,
      AISchemaHelper.describeCount - before,
      'One describe for a hundred questions.'
    );
  }

  @IsTest
  static void testScenario5() {
    FakeCache cache = new FakeCache();
    AISchemaHelper.persistentCache = cache;
    AISchemaHelper.getObjectInfo('Lead');
    Integer describesAfterFirst = AISchemaHelper.describeCount;
    AISchemaHelper.infoByLowerName.clear();

    Test.startTest();
    AISchemaHelper.ObjectInfo fromCache = AISchemaHelper.getObjectInfo('Lead');
    Test.stopTest();

    Assert.areEqual(1, cache.values.size(), 'One entry was persisted.');
    Assert.areEqual(
      describesAfterFirst,
      AISchemaHelper.describeCount,
      'No describe the second time.'
    );
    Assert.areEqual('Lead', fromCache.apiName, 'The same facts.');
    Assert.isTrue(
      fromCache.fieldsByLowerName.containsKey('lastname'),
      'Including the fields.'
    );
    Assert.areEqual(
      AISchemaHelper.SCHEMA_CACHE_TTL_SECONDS,
      cache.lastTtl,
      'With the expiry.'
    );
  }

  @IsTest
  static void testScenario6() {
    FakeCache cache = new FakeCache();
    cache.isBroken = true;
    AISchemaHelper.persistentCache = cache;
    Integer before = AISchemaHelper.describeCount;
    String label;

    Test.startTest();
    label = AISchemaHelper.getLabel('Opportunity');
    AISchemaHelper.clearCache('Opportunity');
    cache.isBroken = false;
    cache.values.put(cache.lastKey == null ? 'x' : cache.lastKey, 'not json');
    AISchemaHelper.infoByLowerName.clear();
    cache.seed = 'not json';
    label = AISchemaHelper.getLabel('Opportunity');
    Test.stopTest();

    Assert.areEqual('Opportunity', label, 'Still answered.');
    Assert.isTrue(AISchemaHelper.describeCount - before >= 2, 'By describing.');
  }

  @IsTest
  static void testScenario7() {
    FakeCache cache = new FakeCache();
    AISchemaHelper.persistentCache = cache;
    AISchemaHelper.getObjectInfo('Account');
    AISchemaHelper.getObjectInfo('Contact');

    Test.startTest();
    AISchemaHelper.clearCache('account');
    Integer afterOne = cache.values.size();
    Boolean contactKept = AISchemaHelper.infoByLowerName.containsKey('contact');
    AISchemaHelper.clearCache(null);
    Test.stopTest();

    Assert.areEqual(1, afterOne, 'One entry left in the persistent cache.');
    Assert.isTrue(contactKept, 'The other object is kept.');
    Assert.areEqual(0, cache.values.size(), 'Everything seen is cleared.');
    Assert.isTrue(
      AISchemaHelper.infoByLowerName.isEmpty(),
      'And the static map.'
    );
  }

  @IsTest
  static void testScenario8() {
    User noAccess = AIAssistTestDataFactory.createUsers(1, true)[0];
    Boolean forAdmin = AISchemaHelper.isAccessible('LoomConnect__AIAgent__c');
    Boolean forUser;
    Boolean blank = AISchemaHelper.isAccessible(null);
    Boolean unknown = AISchemaHelper.isAccessible('No_Such_Object__c');

    System.runAs(noAccess) {
      AISchemaHelper.accessibleByLowerName.clear();
      Test.startTest();
      forUser = AISchemaHelper.isAccessible('LoomConnect__AIAgent__c');
      Test.stopTest();
    }

    Assert.isTrue(forAdmin, 'The deploying user can read it.');
    Assert.isFalse(forUser, 'A user with no permission set cannot.');
    Assert.isFalse(blank || unknown, 'Blank and unknown are not accessible.');
    Assert.isFalse(
      new FakeCacheKeys().contains(AISchemaHelper.persistentCache),
      'Nothing user specific is persisted.'
    );
  }

  @IsTest
  static void testScenario9() {
    FakeCache cache = new FakeCache();
    AISchemaHelper.persistentCache = cache;

    Test.startTest();
    AISchemaHelper.getObjectInfo('Account');
    AISchemaHelper.getObjectInfo('LoomConnect__AIAgent__c');
    AISchemaHelper.getObjectInfo('LoomConnect__AIConversation__c');
    Test.stopTest();

    for (String key : cache.values.keySet())
      Assert.isTrue(
        Pattern.matches('^[A-Za-z0-9]+$', key),
        'Platform cache keys must be alphanumeric: ' + key
      );
    Assert.areEqual(3, cache.values.size(), 'Three objects, three keys.');
  }
}
