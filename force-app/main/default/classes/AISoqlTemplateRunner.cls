/*
Class Name: AISoqlTemplateRunner

=================================================================
=================================================================

Description: Runs the SOQL template of a SOQL data source for the user, in user mode, so the model can only be given what the user could have read themselves.

Step 1: Return nothing to run when the template is blank
Step 2: Work out the row cap and add a LIMIT when the template has none
Step 3: Run the query in user mode with the bound values
Step 4: Cut the result to the row cap and return it

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AISoqlTemplateRunner {

    public class AISoqlTemplateRunnerException extends Exception {}

    // Runs the template in user mode (sharing, object permissions and field-level security all apply). The template is administrator configuration; values from the model are only ever bound, never concatenated. The result is cut to the data source's Max Rows so a broad template cannot fill the prompt or the heap. A failure throws rather than returning an empty list, because an empty list reads to the model as "no records found" and it would stop looking.
    public static List<SObject> runTemplate(String soqlTemplate, Map<String, Object> bindValues, Integer maxRows) {

        try {

            // [1] Nothing to run - no template
            if (String.isBlank(soqlTemplate)) return new List<SObject>();

            // [2] Work out the row cap, falling back to 20 when there is none
            Integer rowCap = maxRows == null || maxRows < 1 ? 20 : maxRows;
            String soql = soqlTemplate.trim().removeEnd(';');

            // [3] Add a LIMIT when the template has none
            if (!Pattern.compile('(?i)\\bLIMIT\\b').matcher(soql).find()) soql += ' LIMIT ' + rowCap;

            // [4] Run the query in user mode with the bound values
            List<SObject> queriedRows = Database.queryWithBinds(soql, bindValues == null ? new Map<String, Object>() : bindValues, AccessLevel.USER_MODE);

            // [5] Keep only the first rows up to the cap, even if the template had a larger LIMIT of its own
            List<SObject> cappedRows = new List<SObject>();

            for (Integer rowIndex = 0; rowIndex < Math.min(queriedRows.size(), rowCap); rowIndex++) {

                cappedRows.add(queriedRows[rowIndex]);
            }

            // [6] Return the capped rows
            return cappedRows;

        } catch (Exception ex) {
            // AIAgentManager logs it once.
            throw new AISoqlTemplateRunnerException('Failed to run SOQL template: ' + ex.getMessage(), ex);
        }
    }
}
