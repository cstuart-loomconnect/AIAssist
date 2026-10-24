/*
Class Name: AIDataSourceTestStub

=================================================================
=================================================================

Description: Stands in for a subscriber's Apex data source in tests: it implements the executor and the input describer so the AI Tools tab can find it, and returns no records.

Step 1: The AI Tools tab finds this class as an executor
Step 2: The tab asks it to describe its inputs
Step 3: Running it returns no records

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public class AIDataSourceTestStub implements IAIDataSourceExecutor, IAIDataSourceInputDescriber {

    public AIDataSourceResponse execute(AIDataSourceRequest request) {

        return new AIDataSourceResponse(new List<SObject>());
    }

    public String describeInputs() {

        return '{"type":"object","properties":{"recordId":{"type":"string","x-source":"page"},"includeCommitments":{"type":"boolean"}}}';
    }
}
