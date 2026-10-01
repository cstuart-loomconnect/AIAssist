/*
Class Name: IAIDataSourceExecutor

=================================================================
=================================================================

Description: Contract for the Apex class named in AIDataSource__c.ApexClassName__c when
SourceType__c is Apex. An implementing class retrieves and returns the records for that data
source, scoped to AIDataSource__c.TargetObject__c.

The dispatcher only calls a class that implements this interface; a class name entered by a
subscriber that does not is refused before anything in it runs. The implementing class owns its
own security context: it should run its queries in user mode, because what it returns goes to
an AI model.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public interface IAIDataSourceExecutor {
  List<SObject> execute(Id recordId, Map<String, Object> inputParameters);
}
