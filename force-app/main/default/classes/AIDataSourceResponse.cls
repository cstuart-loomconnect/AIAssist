/*
Class Name: AIDataSourceResponse

=================================================================
=================================================================

Description: What an Apex data source (IAIDataSourceExecutor.execute) returns: the records to put in front
of the model. The package masks personal data and applies the row cap to them before the model sees
anything, whatever the class returned.

Global: part of the package's permanent API. After release a field can be added, never changed or
removed.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

global class AIDataSourceResponse {
  global List<SObject> records = new List<SObject>();

  global AIDataSourceResponse() {
  }

  global AIDataSourceResponse(List<SObject> records) {
    this.records = records == null ? new List<SObject>() : records;
  }
}
