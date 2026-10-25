/*
Class Name: IAIDataSourceExecutor

=================================================================
=================================================================

Description: Contract for the Apex class named in AIDataSource__c.ApexClassName__c when SourceType__c is Apex. It is part of the package's permanent API: after release the method cannot be changed or removed, only added to.

Step 1: The dispatcher checks the named class implements this interface, before any of its code runs
Step 2: The dispatcher calls execute with an AIDataSourceRequest
Step 3: The class returns the records for the data source in an AIDataSourceResponse

The class owns its own security context: it should run its queries in user mode, because what it returns goes to an AI model.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

global interface IAIDataSourceExecutor {

    AIDataSourceResponse execute(AIDataSourceRequest request);
}
