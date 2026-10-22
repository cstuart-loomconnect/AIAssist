/*
Class Name: AIDataSourceInputBinderTest

=================================================================
=================================================================

Description: Testing utility for AIDataSourceInputBinder: the values a data source may use, and the schema the model is shown.

=================================================================
=================================================================
Applicable Classes:

AIDataSourceInputBinder: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIDataSourceInputBinderTest {

    // testScenario1: A data source with no input schema is bound -> every value is kept.
    // testScenario2: Every kind of declared input is supplied with an undeclared one and a page input -> each is the declared type and the others are dropped.
    // testScenario3: A required input is missing, a date is not a date and an optional input is left out -> the first two are refused and the third is bound as null.
    // testScenario4: The model schema is built from a schema with a page input -> the page input is gone from the properties and the required list.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the values the model supplied and no schema
            Map<String, Object> supplied = new Map<String, Object>{'anything' => 'goes'};

            // [2] Bind them
            Test.startTest();
                Map<String, Object> blankSchemaValues = AIDataSourceInputBinder.getBindValues(null, supplied);
                Map<String, Object> noValues = AIDataSourceInputBinder.getBindValues(null, null);
            Test.stopTest();

            // [3] Check a data source with no schema keeps what it is given
            Assert.areEqual('goes', blankSchemaValues.get('anything'), 'A blank schema keeps every value.');
            Assert.isTrue(noValues.isEmpty(), 'No values give no binds.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Declare a page input, a date, an integer, a number, a true or false and a date time, and supply them with one the schema does not declare
            String schema = '{"type":"object","properties":{"recordId":{"type":"string","x-source":"page"},"closeBefore":{"type":"string","format":"date"},"howMany":{"type":"integer"},"minAmount":{"type":"number"},"isOpen":{"type":"boolean"},"since":{"type":"string","format":"date-time"},"note":{"type":"string"}},"required":["recordId","closeBefore"]}';
            Map<String, Object> supplied = new Map<String, Object>{
                'recordId' => '001000000000000AAA',
                'closeBefore' => '2026-12-31',
                'howMany' => '3',
                'minAmount' => '10.5',
                'isOpen' => 'true',
                'since' => '2026-01-02T03:04:05.000Z',
                'note' => 'hello',
                'sneaky' => 'dropped'
            };

            // [2] Bind them
            Test.startTest();
                Map<String, Object> bindValues = AIDataSourceInputBinder.getBindValues(schema, supplied);
            Test.stopTest();

            // [3] Check each value has the declared type and the others are dropped
            Assert.isFalse(bindValues.containsKey('recordId'), 'The model cannot supply an input the page fills in.');
            Assert.isFalse(bindValues.containsKey('sneaky'), 'An undeclared value is dropped.');
            Assert.areEqual(Date.newInstance(2026, 12, 31), bindValues.get('closeBefore'), 'A date input becomes a Date.');
            Assert.areEqual(3, bindValues.get('howMany'), 'An integer input becomes an Integer.');
            Assert.areEqual(10.5, bindValues.get('minAmount'), 'A number input becomes a Decimal.');
            Assert.areEqual(true, bindValues.get('isOpen'), 'A boolean input becomes a Boolean.');
            Assert.isTrue(bindValues.get('since') instanceof Datetime, 'A date-time input becomes a Datetime.');
            Assert.areEqual('hello', bindValues.get('note'), 'A text input stays text.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Declare a required date and an optional text input
            String schema = '{"type":"object","properties":{"closeBefore":{"type":"string","format":"date"},"note":{"type":"string"}},"required":["closeBefore"]}';
            String missingRequired;
            String badDate;
            Map<String, Object> bindValues;

            // [2] Bind with the required input missing, with a bad date, and with only the required input
            Test.startTest();
                try {

                    AIDataSourceInputBinder.getBindValues(schema, new Map<String, Object>());
                } catch (Exception ex) {

                    missingRequired = ex.getMessage();
                }

                try {

                    AIDataSourceInputBinder.getBindValues(schema, new Map<String, Object>{'closeBefore' => 'next week'});
                } catch (Exception ex) {

                    badDate = ex.getMessage();
                }

                bindValues = AIDataSourceInputBinder.getBindValues(schema, new Map<String, Object>{'closeBefore' => '2026-01-01'});
            Test.stopTest();

            // [3] Check each refusal and that an optional input left out is bound as null
            Assert.areEqual('The input "closeBefore" is required.', missingRequired, 'A missing required input is refused.');
            Assert.areEqual('The input "closeBefore" is not a valid date.', badDate, 'A value that is not a date is refused.');
            Assert.isTrue(bindValues.containsKey('note'), 'An optional input that was left out is still bound.');
            Assert.isNull(bindValues.get('note'), 'An optional input that was left out is bound as null.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Declare a page input and an agent input, both required
            String schema = '{"type":"object","properties":{"recordId":{"type":"string","x-source":"page"},"closeBefore":{"type":"string","format":"date","description":"When"}},"required":["recordId","closeBefore"]}';

            // [2] Build the schema the model sees, and the one for a blank schema
            Test.startTest();
                Map<String, Object> modelSchema = AIDataSourceInputBinder.getModelInputSchema(schema);
                Map<String, Object> blankSchema = AIDataSourceInputBinder.getModelInputSchema(null);
            Test.stopTest();

            // [3] Check the page input is gone from the properties and the required list
            Map<String, Object> properties = (Map<String, Object>) modelSchema.get('properties');
            List<Object> required = (List<Object>) modelSchema.get('required');
            Assert.isFalse(properties.containsKey('recordId'), 'The model is not asked for the input the page fills in.');
            Assert.isTrue(properties.containsKey('closeBefore'), 'The model is asked for the agent input.');
            Assert.areEqual(new List<Object>{'closeBefore'}, required, 'Only the agent input is required.');
            Assert.areEqual('object', blankSchema.get('type'), 'A blank schema asks for nothing.');
        }
    }
}
