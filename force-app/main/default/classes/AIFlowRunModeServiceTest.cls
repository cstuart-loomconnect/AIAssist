/*
Class Name: AIFlowRunModeServiceTest

=================================================================
=================================================================

Description: Testing utility for AIFlowRunModeService: which Flows may run as a Workflow Action.

=================================================================
=================================================================
Applicable Classes:

AIFlowRunModeService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIFlowRunModeServiceTest {
  // testScenario1: A Flow in the default mode or in system context with sharing is allowed; one in system context without sharing, a missing one and a blank name are not.
  // testScenario2: assertAllowed passes an allowed Flow and throws a failure for any other.
  // testScenario3: Without the test seam, the real lookup runs and a Flow that does not exist is not allowed.

  @IsTest
  static void testScenario1() {
    AIFlowRunModeService.setRunModeForTest('DefaultFlow', null);
    AIFlowRunModeService.setRunModeForTest(
      'SharingFlow',
      'SystemModeWithSharing'
    );
    AIFlowRunModeService.setRunModeForTest(
      'SystemFlow',
      AIFlowRunModeService.RUN_MODE_SYSTEM_WITHOUT_SHARING
    );

    Test.startTest();
    Map<String, Boolean> allowed = AIFlowRunModeService.getAllowedByFlowName(
      new Set<String>{
        'DefaultFlow',
        ' SharingFlow ',
        'SystemFlow',
        'MissingFlow',
        ''
      }
    );
    Test.stopTest();

    Assert.isTrue(allowed.get('DefaultFlow'), 'Default mode.');
    Assert.isTrue(
      allowed.get(' SharingFlow '),
      'With sharing; the name is trimmed.'
    );
    Assert.isFalse(allowed.get('SystemFlow'), 'Without sharing.');
    Assert.isFalse(allowed.get('MissingFlow'), 'Not found fails closed.');
    Assert.isFalse(allowed.get(''), 'A blank name is not a Flow.');
  }

  @IsTest
  static void testScenario2() {
    AIFlowRunModeService.setRunModeForTest('DefaultFlow', null);
    AIFlowRunModeService.setRunModeForTest(
      'SystemFlow',
      AIFlowRunModeService.RUN_MODE_SYSTEM_WITHOUT_SHARING
    );
    Boolean refused = false;

    Test.startTest();
    AIFlowRunModeService.assertAllowed('DefaultFlow');
    try {
      AIFlowRunModeService.assertAllowed('SystemFlow');
    } catch (AIMessagingException failure) {
      refused = !failure.isRefusal;
    }
    Test.stopTest();

    Assert.isTrue(refused, 'A failure, logged, not a user-facing refusal.');
  }

  @IsTest
  static void testScenario3() {
    Test.startTest();
    Map<String, Boolean> allowed = AIFlowRunModeService.getAllowedByFlowName(
      new Set<String>{ 'AIAssistNoSuchFlow', 'ns__AIAssistNoSuchFlow' }
    );
    Test.stopTest();

    Assert.isFalse(allowed.get('AIAssistNoSuchFlow'), 'No such Flow.');
    Assert.isFalse(
      allowed.get('ns__AIAssistNoSuchFlow'),
      'No such namespaced Flow.'
    );
  }
}
