/*
Class Name: AIDataSourceDispatcherTest

=================================================================
=================================================================

Description: Testing utility for AIDataSourceDispatcher: running a data source for the model only if it is active and assigned to the agent, as the user, and returning masked results.

=================================================================
=================================================================
Applicable Classes:

AIDataSourceDispatcher
IAIDataSourceExecutor

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIDataSourceDispatcherTest {
  // testScenario1: A SOQL data source assigned to the agent runs and returns the flattened records.
  // testScenario2: A data source that is inactive, not assigned to this agent, or missing is refused with one message that reveals which.
  // testScenario3: A data source assigned to a different agent cannot be run by this one.
  // testScenario4: A bound data source needs the record the chat is about, and an unbound one runs without it.
  // testScenario5: An Apex data source runs only if the class implements IAIDataSourceExecutor, and one that does not, or does not exist, is refused before any of its code runs.
  // testScenario6: An Apex data source is refused when the plan does not include Apex data sources.
  // testScenario7: The row cap of the data source limits how many records reach the model.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  // Stands in for a subscriber's Apex data source.
  public class NoRecordsExecutor implements IAIDataSourceExecutor {
    public AIDataSourceResponse execute(AIDataSourceRequest request) {
      return new AIDataSourceResponse(new List<SObject>());
    }
  }

  // A class a subscriber named by mistake: it exists but is not an executor.
  public class NotAnExecutor {
    public NotAnExecutor() {
      AIDataSourceDispatcherTest.wasNotAnExecutorConstructed = true;
    }
  }

  private static Boolean wasNotAnExecutorConstructed = false;

  @IsTest
  static void testScenario1() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(
      1,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id, Name FROM Account WHERE Id = :recordId',
      true
    )[0];
    AIAssistTestDataFactory.createAIAgentDataSources(
      agent.Id,
      new List<AIDataSource__c>{ dataSource },
      true
    );
    Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];

    Test.startTest();
    List<Object> results = AIDataSourceDispatcher.runDataSource(
      dataSource.Id,
      agent.Id,
      account.Id,
      null,
      null
    );
    Test.stopTest();

    Assert.areEqual(1, results.size(), 'One record is returned.');
    Assert.areEqual(
      account.Id,
      ((Map<String, Object>) results[0]).get('Id'),
      'It is the account the chat is about.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    List<AIDataSource__c> dataSources = AIAssistTestDataFactory.createAIDataSources(
      2,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      true
    );
    AIAssistTestDataFactory.createAIAgentDataSources(
      agent.Id,
      new List<AIDataSource__c>{ dataSources[0] },
      true
    );
    dataSources[0].IsActive__c = false;
    update dataSources[0];
    Id deletedId = dataSources[1].Id;
    delete dataSources[1];
    List<String> messages = new List<String>();

    Test.startTest();
    for (Id dataSourceId : new List<Id>{ dataSources[0].Id, deletedId, null }) {
      try {
        AIDataSourceDispatcher.runDataSource(
          dataSourceId,
          agent.Id,
          null,
          null,
          null
        );
        Assert.fail('A data source that cannot be run should have thrown.');
      } catch (AIDataSourceDispatcher.AIDataSourceExecutorException ex) {
        messages.add(ex.getMessage());
      }
    }
    Test.stopTest();

    Assert.isTrue(
      messages[0].contains('not found, is not active, or is not assigned'),
      'An inactive source is refused without saying which of the three it is.'
    );
    Assert.areEqual(
      messages[0],
      messages[1],
      'A missing source gets the same message.'
    );
    Assert.isTrue(messages[2].contains('required'), 'A blank Id is refused.');
  }

  @IsTest
  static void testScenario3() {
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      2,
      model.Id,
      true
    );
    AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(
      1,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      true
    )[0];
    AIAssistTestDataFactory.createAIAgentDataSources(
      agents[0].Id,
      new List<AIDataSource__c>{ dataSource },
      true
    );

    Test.startTest();
    try {
      AIDataSourceDispatcher.runDataSource(
        dataSource.Id,
        agents[1].Id,
        null,
        null,
        null
      );
      Assert.fail('Another agents data source should have thrown.');
    } catch (AIDataSourceDispatcher.AIDataSourceExecutorException ex) {
      Assert.isTrue(
        ex.getMessage().contains('not assigned'),
        'The refusal covers assignment.'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    List<AIDataSource__c> dataSources = AIAssistTestDataFactory.createAIDataSources(
      2,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account LIMIT 1',
      false
    );
    dataSources[0]
      .BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
    dataSources[1]
      .BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
    insert dataSources;
    AIAssistTestDataFactory.createAIAgentDataSources(
      agent.Id,
      dataSources,
      true
    );
    AIAssistTestDataFactory.createAccounts(1, true);
    String boundMessage;
    List<Object> unboundResults;

    Test.startTest();
    try {
      AIDataSourceDispatcher.runDataSource(
        dataSources[0].Id,
        agent.Id,
        null,
        null,
        null
      );
      Assert.fail('A bound data source with no record should have thrown.');
    } catch (AIDataSourceDispatcher.AIDataSourceExecutorException ex) {
      boundMessage = ex.getMessage();
    }
    unboundResults = AIDataSourceDispatcher.runDataSource(
      dataSources[1].Id,
      agent.Id,
      null,
      null,
      null
    );
    Test.stopTest();

    Assert.isTrue(
      boundMessage.contains('needs the record'),
      'The bound source says what it needs.'
    );
    Assert.areEqual(
      1,
      unboundResults.size(),
      'The unbound source runs without a record.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    List<AIDataSource__c> dataSources = AIAssistTestDataFactory.createAIDataSources(
      1,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX,
      'AIDataSourceDispatcherTest.NoRecordsExecutor',
      false
    );
    dataSources.addAll(
      AIAssistTestDataFactory.createAIDataSources(
        1,
        AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX,
        'AIDataSourceDispatcherTest.NotAnExecutor',
        false
      )
    );
    dataSources.addAll(
      AIAssistTestDataFactory.createAIDataSources(
        1,
        AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX,
        'AIDataSourceDispatcherTest.DoesNotExist',
        false
      )
    );
    for (AIDataSource__c dataSource : dataSources)
      dataSource.BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
    insert dataSources;
    AIAssistTestDataFactory.createAIAgentDataSources(
      agent.Id,
      dataSources,
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      true
    );
    List<Object> goodResults;
    List<String> refusals = new List<String>();

    Test.startTest();
    goodResults = AIDataSourceDispatcher.runDataSource(
      dataSources[0].Id,
      agent.Id,
      null,
      null,
      null
    );

    for (Integer i = 1; i < 3; i++) {
      try {
        AIDataSourceDispatcher.runDataSource(
          dataSources[i].Id,
          agent.Id,
          null,
          null,
          null
        );
        Assert.fail('A class that is not an executor should have thrown.');
      } catch (AIDataSourceDispatcher.AIDataSourceExecutorException ex) {
        refusals.add(ex.getMessage());
      }
    }
    Test.stopTest();

    Assert.isTrue(
      goodResults.isEmpty(),
      'The executor ran and returned no records.'
    );
    Assert.isTrue(
      refusals[0].contains('does not implement IAIDataSourceExecutor'),
      'A class that does not implement the interface is refused.'
    );
    Assert.isTrue(
      refusals[1].contains('was not found or does not implement'),
      'A class that does not exist is refused the same way.'
    );
    Assert.isFalse(
      wasNotAnExecutorConstructed,
      'Not even the constructor of the refused class ran.'
    );
  }

  @IsTest
  static void testScenario6() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(
      1,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX,
      'AIDataSourceDispatcherTest.NoRecordsExecutor',
      false
    )[0];
    dataSource.BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
    insert dataSource;
    AIAssistTestDataFactory.createAIAgentDataSources(
      agent.Id,
      new List<AIDataSource__c>{ dataSource },
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      false
    );

    Test.startTest();
    try {
      AIDataSourceDispatcher.runDataSource(
        dataSource.Id,
        agent.Id,
        null,
        null,
        null
      );
      Assert.fail(
        'An Apex data source should be refused on a plan without it.'
      );
    } catch (AIDataSourceDispatcher.AIDataSourceExecutorException ex) {
      Assert.isTrue(
        ex.getMessage().contains('not included in the plan'),
        'The refusal names the plan.'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void testScenario7() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(
      1,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      false
    )[0];
    dataSource.BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
    dataSource.MaxRows__c = 5;
    insert dataSource;
    AIAssistTestDataFactory.createAIAgentDataSources(
      agent.Id,
      new List<AIDataSource__c>{ dataSource },
      true
    );
    AIAssistTestDataFactory.createAccounts(20, true);

    Test.startTest();
    List<Object> results = AIDataSourceDispatcher.runDataSource(
      dataSource.Id,
      agent.Id,
      null,
      null,
      null
    );
    Test.stopTest();

    Assert.areEqual(
      5,
      results.size(),
      'Only the first five records are given to the model.'
    );
  }
}
