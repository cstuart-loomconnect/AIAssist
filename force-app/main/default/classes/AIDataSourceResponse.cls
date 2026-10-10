/*
Class Name: AIDataSourceResponse

=================================================================
=================================================================

Description: What an Apex data source (IAIDataSourceExecutor.execute) returns: the records to put in front of the model. It is part of the package's permanent API: after release a field can be added, never changed or removed.

Step 1: The subscriber's class puts the records it found on the response
Step 2: The dispatcher takes the records from the response
Step 3: The package masks personal data and applies the row cap before the model sees anything

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

global without sharing class AIDataSourceResponse {
  global List<SObject> records = new List<SObject>();

  global AIDataSourceResponse() {
  }

  // A null list is treated as no records.
  global AIDataSourceResponse(List<SObject> records) {
    // [1] Keep the records, or an empty list when none were given
    this.records = records == null ? new List<SObject>() : records;
  }
}
