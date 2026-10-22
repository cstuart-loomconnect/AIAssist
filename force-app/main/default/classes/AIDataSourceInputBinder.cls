/*
Class Name: AIDataSourceInputBinder

=================================================================
=================================================================

Description: Turns the values the model supplied for a data source into the values the data source may use, by the inputs the data source declares.

Step 1: Read the inputs from the data source's input schema
Step 2: Drop every value the data source did not declare, and every input the page fills in
Step 3: Turn each value into the type the schema says, such as a date, a number or a true or false
Step 4: Refuse a required input that is missing
Step 5: Give the model a copy of the schema without the inputs the page fills in

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIDataSourceInputBinder {

    public class AIDataSourceInputBinderException extends Exception {}

    private static final String SCHEMA_PROPERTIES = 'properties';
    private static final String SCHEMA_REQUIRED = 'required';
    private static final String SCHEMA_TYPE = 'type';
    private static final String SCHEMA_FORMAT = 'format';
    private static final String TYPE_OBJECT = 'object';
    private static final String TYPE_INTEGER = 'integer';
    private static final String TYPE_NUMBER = 'number';
    private static final String TYPE_BOOLEAN = 'boolean';
    private static final String FORMAT_DATE = 'date';
    private static final String FORMAT_DATE_TIME = 'date-time';

    // The values the data source may use. A data source with no input schema keeps whatever it was given, as it always has.
    public static Map<String, Object> getBindValues(String inputSchema, Map<String, Object> suppliedValues) {

        try {

            // [1] Start from what the model supplied
            Map<String, Object> supplied = suppliedValues == null ? new Map<String, Object>() : suppliedValues;
            if (String.isBlank(inputSchema)) return new Map<String, Object>(supplied);

            // [2] Read the inputs the schema declares
            Map<String, Object> schema = (Map<String, Object>) JSON.deserializeUntyped(inputSchema);
            Map<String, Object> properties = getProperties(schema);
            Set<String> requiredNames = getRequiredNames(schema);
            Map<String, Object> bindValues = new Map<String, Object>();

            // [3] Keep only the declared inputs the page does not fill in, in the type the schema says
            for (String inputName : properties.keySet()) {

                Map<String, Object> property = (Map<String, Object>) properties.get(inputName);
                if (isPageInput(property)) continue;

                // [4] Refuse a required input the model left out
                Object suppliedValue = supplied.get(inputName);
                if (suppliedValue == null && requiredNames.contains(inputName)) throw new AIDataSourceInputBinderException('The input "' + inputName + '" is required.');

                bindValues.put(inputName, suppliedValue == null ? null : getTypedValue(inputName, suppliedValue, property));
            }

            return bindValues;

        } catch (AIDataSourceInputBinderException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AIDataSourceInputBinderException('Failed to read the inputs of the data source: ' + ex.getMessage(), ex);
        }
    }

    // The input schema the model is shown: the same schema without the inputs the page fills in, because the model must not be asked for them.
    public static Map<String, Object> getModelInputSchema(String inputSchema) {

        try {

            // [1] A blank schema asks the model for nothing
            Map<String, Object> emptySchema = new Map<String, Object>{SCHEMA_TYPE => TYPE_OBJECT, SCHEMA_PROPERTIES => new Map<String, Object>()};
            if (String.isBlank(inputSchema)) return emptySchema;

            // [2] Copy the declared inputs the page does not fill in
            Map<String, Object> schema = (Map<String, Object>) JSON.deserializeUntyped(inputSchema);
            Map<String, Object> properties = getProperties(schema);
            Map<String, Object> modelProperties = new Map<String, Object>();

            for (String inputName : properties.keySet()) {

                Map<String, Object> property = (Map<String, Object>) properties.get(inputName);
                if (!isPageInput(property)) modelProperties.put(inputName, property);
            }

            // [3] Keep the required list to the inputs that are left
            List<Object> modelRequired = new List<Object>();

            for (String requiredName : getRequiredNames(schema)) {

                if (modelProperties.containsKey(requiredName)) modelRequired.add(requiredName);
            }

            schema.put(SCHEMA_PROPERTIES, modelProperties);
            if (modelRequired.isEmpty()) schema.remove(SCHEMA_REQUIRED);
            else schema.put(SCHEMA_REQUIRED, modelRequired);

            return schema;

        } catch (Exception ex) {
            throw new AIDataSourceInputBinderException('Failed to read the inputs of the data source: ' + ex.getMessage(), ex);
        }
    }

    // The declared inputs by name.
    private static Map<String, Object> getProperties(Map<String, Object> schema) {

        // [1] A schema with no inputs declares none
        Object properties = schema.get(SCHEMA_PROPERTIES);

        return properties instanceof Map<String, Object> ? (Map<String, Object>) properties : new Map<String, Object>();
    }

    // The names of the required inputs.
    private static Set<String> getRequiredNames(Map<String, Object> schema) {

        // [1] Read the list, if there is one
        Set<String> requiredNames = new Set<String>();
        Object required = schema.get(SCHEMA_REQUIRED);
        if (!(required instanceof List<Object>)) return requiredNames;

        for (Object requiredName : (List<Object>) required) requiredNames.add(String.valueOf(requiredName));

        return requiredNames;
    }

    // True when the page fills in the input, so the model may not.
    private static Boolean isPageInput(Map<String, Object> property) {

        // [1] The input says who fills it in
        return property.get(AIAssistApplicationConstants.TOOLS_INPUT_SOURCE_KEY) == AIAssistApplicationConstants.TOOLS_INPUT_SOURCE_PAGE;
    }

    // Turns one value into the type the schema says.
    private static Object getTypedValue(String inputName, Object suppliedValue, Map<String, Object> property) {

        // [1] Read what the schema says about the type
        String inputType = String.valueOf(property.get(SCHEMA_TYPE));
        String inputFormat = String.valueOf(property.get(SCHEMA_FORMAT));
        String suppliedText = String.valueOf(suppliedValue).trim();

        try {

            // [2] Turn the value into that type
            if (inputType == TYPE_INTEGER) return Integer.valueOf(suppliedText);
            if (inputType == TYPE_NUMBER) return Decimal.valueOf(suppliedText);
            if (inputType == TYPE_BOOLEAN) return Boolean.valueOf(suppliedText);
            if (inputFormat == FORMAT_DATE) return Date.valueOf(suppliedText.left(10));
            if (inputFormat == FORMAT_DATE_TIME) return (Datetime) JSON.deserialize('"' + suppliedText + '"', Datetime.class);

            return suppliedValue;

        } catch (Exception ex) {
            throw new AIDataSourceInputBinderException('The input "' + inputName + '" is not a valid ' + (String.isBlank(inputFormat) || inputFormat == 'null' ? inputType : inputFormat) + '.', ex);
        }
    }
}
