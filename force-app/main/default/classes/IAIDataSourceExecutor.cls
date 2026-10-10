/*
Class Name: IAIDataSourceExecutor

=================================================================
=================================================================

Description: Contract for the Apex class named in AIDataSource__c.ApexClassName__c when
SourceType__c is Apex. An implementing class retrieves and returns, in an AIDataSourceResponse, the records for that data
source, scoped to AIDataSource__c.TargetObject__c. The AIDataSourceRequest carries the record, the model's inputs and who is asking.

The dispatcher only calls a class that implements this interface; a class name entered by a
subscriber that does not is refused before anything in it runs. The implementing class owns its
own security context: it should run its queries in user mode, because what it returns goes to
an AI model.

Global: this is part of the package's permanent API. Once a version is released the method cannot
be changed or removed, only added to.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Global, so a class in the subscriber's org can implement it. A public interface is visible only inside the package's namespace.
3.0          Chandler Stuart          One request and one response class instead of loose arguments and a list, so what is passed in and returned can grow after release.
*/

global interface IAIDataSourceExecutor {
  AIDataSourceResponse execute(AIDataSourceRequest request);
}
