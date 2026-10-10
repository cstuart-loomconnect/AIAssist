/*
Class Name: AIDataSourceRequest

=================================================================
=================================================================

Description: What the package hands to an Apex data source (IAIDataSourceExecutor.execute).

Step 1: The dispatcher builds the request from the chat and the data source definition
Step 2: The dispatcher passes it to the subscriber's IAIDataSourceExecutor class
Step 3: The subscriber's class reads what it needs and ignores the rest

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

global without sharing class AIDataSourceRequest {

    // The record the conversation is about. Null for an unbound data source.
    global Id recordId;

    // Values the model supplied for the parameters the data source declares.
    global Map<String, Object> inputParameters = new Map<String, Object>();

    // The conversation this request is part of, and the agent and user it is for.
    global Id conversationId;
    global Id agentId;
    global Id userId;

    // The Developer Name of the data source being run.
    global String dataSourceName;

    // The most rows the data source is set to return, or null when there is no cap. The package applies the cap again to what comes back.
    global Integer maxRows;

    // Explicit and global so a subscriber's test can build a request. The implicit constructor of a global class cannot be seen outside the package.
    global AIDataSourceRequest() {
    }
}
