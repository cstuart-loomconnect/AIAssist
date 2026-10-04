/*
Class Name: AIWorkflowActionRequestTest

=================================================================
=================================================================

Description: Testing utility for AIWorkflowActionRequest: a request can be built from outside the class, as a subscriber's test must to call its own action.

=================================================================
=================================================================
Applicable Classes:

AIWorkflowActionRequest

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIWorkflowActionRequestTest {
  // testScenario1: A request built with the no-argument constructor starts with an empty input map and carries what is set on it.

  @IsTest
  static void testScenario1() {
    Test.startTest();
    AIWorkflowActionRequest request = new AIWorkflowActionRequest();
    Integer inputsAtStart = request.inputParameters.size();
    request.recordId = UserInfo.getUserId();
    request.userId = UserInfo.getUserId();
    request.actionName = 'Example';
    request.inputParameters.put('x', 1);
    Test.stopTest();

    Assert.areEqual(0, inputsAtStart, 'The input map is never null.');
    Assert.areEqual(UserInfo.getUserId(), request.recordId, 'Record kept.');
    Assert.areEqual(UserInfo.getUserId(), request.userId, 'User kept.');
    Assert.areEqual('Example', request.actionName, 'Name kept.');
    Assert.areEqual(1, request.inputParameters.get('x'), 'Input kept.');
  }
}
