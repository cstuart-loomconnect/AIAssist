/*
Class Name: AISoqlTemplateRunner

=================================================================
=================================================================

Description: Runs the SOQL template of a SOQL data source for the user, in user mode: sharing,
object permissions and field-level security all apply, so the model can only be given what the
user could have read themselves.

The template is administrator configuration; values from the model are only ever bound
(Database.queryWithBinds), never concatenated. The number of rows is cappedRows by the data
source's Max Rows: a template without its own LIMIT gets one added, and the result is cut to the
cap regardless, so a broad template cannot put thousands of records in the prompt or the heap.

A failure throws rather than returning an empty list: an empty list reads to the model as
"no records found", and it would stop looking.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Row cap from the data source. User mode is no longer a parameter.
*/

public inherited sharing class AISoqlTemplateRunner {
  public class AISoqlTemplateRunnerException extends Exception {
  }

  public static List<SObject> runTemplate(
    String soqlTemplate,
    Map<String, Object> bindValues,
    Integer maxRows
  ) {
    try {
      if (String.isBlank(soqlTemplate))
        return new List<SObject>();

      Integer rowCap = maxRows == null || maxRows < 1 ? 20 : maxRows;
      String soql = soqlTemplate.trim().removeEnd(';');

      if (!Pattern.compile('(?i)\\bLIMIT\\b').matcher(soql).find())
        soql += ' LIMIT ' + rowCap;

      List<SObject> queriedRows = Database.queryWithBinds(
        soql,
        bindValues == null ? new Map<String, Object>() : bindValues,
        AccessLevel.USER_MODE
      );

      List<SObject> cappedRows = new List<SObject>();
      for (
        Integer rowIndex = 0;
        rowIndex < Math.min(queriedRows.size(), rowCap);
        rowIndex++
      )
        cappedRows.add(queriedRows[rowIndex]);

      return cappedRows;
    } catch (Exception caughtException) {
      throw new AISoqlTemplateRunnerException(
        'Failed to run SOQL template: ' + caughtException.getMessage(),
        caughtException
      ); // AIAgentManager logs it once.
    }
  }
}
