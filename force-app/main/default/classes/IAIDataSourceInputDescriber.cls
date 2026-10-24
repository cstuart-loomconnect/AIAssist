/*
Class Name: IAIDataSourceInputDescriber

=================================================================
=================================================================

Description: Optional contract for an Apex data source class (IAIDataSourceExecutor) that wants to describe its own inputs, so the AI Tools tab can fill in the Inputs step for the admin. It is part of the package's permanent API: after release the method cannot be changed or removed, only added to.

Step 1: The AI Tools tab finds classes that implement this interface next to IAIDataSourceExecutor
Step 2: The tab calls describeInputs on a new instance of the class
Step 3: The class returns its inputs as an input schema in the same JSON format the tab saves to AIDataSource__c.InputSchema__c

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

global interface IAIDataSourceInputDescriber {

    String describeInputs();
}
