/*
Script Name: 05-custom-metadata.apex

=================================================================
=================================================================

Description: Custom metadata: PII compliance groups, masking rules, field types and chat commands.

Custom metadata cannot be inserted, so the records are deployed (Metadata.Operations) and land a few
seconds after the script ends. Setup > Deployment Status shows the result. On its own because a
deployment cannot be queued in a transaction that also writes records or settings.

Safe to run again: the records are overwritten with the values here. Run it after 02-agents.apex
for the /deal-risks command to be limited to the sample sales agent.

Part of the sample data set: run scripts/load-sample-data.sh <org alias> to load all five parts in
order, or this part alone with sf apex run --file.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public class SampleDataLoader {
  // =============================================================
  // Options
  // =============================================================

  Boolean isProductionAllowed = false; // The script refuses to run outside a sandbox or scratch org unless this is set.

  // =============================================================

  final String PREFIX = 'Sample - ';
  List<String> summary = new List<String>();
  List<String> problems = new List<String>();
  Id runningUserId = UserInfo.getUserId();

  public void run() {
    if (
      !isProductionAllowed &&
      ![SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox
    )
      problems.add('Not a sandbox or scratch org. Nothing was loaded.');
    else
      load();

    System.debug(
      LoggingLevel.ERROR,
      'SAMPLE DATA: 05-custom-metadata.apex\n  ' +
        String.join(summary, '\n  ') +
        (problems.isEmpty()
          ? '\nNo problems.'
          : '\nPROBLEMS (' +
            problems.size() +
            ')\n  ' +
            String.join(problems, '\n  '))
    );
  }

  void load() {
    Metadata.DeployContainer container = new Metadata.DeployContainer();
    Integer recordCount = 0;

    // ---------- Compliance groups. The label is what Data Classification calls the group.
    Map<String, String> groupDescriptionByName = new Map<String, String>{
      'PII' => 'Personally identifiable information.',
      'GDPR' => 'Personal data under the UK and EU General Data Protection Regulation.',
      'HIPAA' => 'Protected health information under the US Health Insurance Portability and Accountability Act.',
      'PCI' => 'Cardholder data under the Payment Card Industry Data Security Standard.',
      'CCPA' => 'Personal information under the California Consumer Privacy Act.',
      'COPPA' => 'Personal information of children under the US Children\'s Online Privacy Protection Act.'
    };
    for (String groupName : groupDescriptionByName.keySet()) {
      container.addMetadata(
        metadataRecord(
          AIPiiComplianceGroup__mdt.SObjectType,
          groupName,
          groupName,
          new Map<Schema.SObjectField, Object>{
            AIPiiComplianceGroup__mdt.Description__c => groupDescriptionByName.get(
              groupName
            ),
            AIPiiComplianceGroup__mdt.IsActive__c => groupName != 'COPPA'
          }
        )
      );
      recordCount++;
    }

    // ---------- Masking rules. Developer name, label, strategy, substitute values, replacement pattern, character count, redact.
    List<List<Object>> ruleRows = new List<List<Object>>{
      new List<Object>{ 'Person_Names', 'Person Names', 'SubstituteFromList', 'Jamie Carter,Sam Patel,Morgan Reid,Taylor Brooks,Jordan Ellis,Casey Flynn,Riley Hart,Avery Quinn,Robin Shaw,Drew Lawson,Quinn Mercer,Hayden Cole,Rowan Blake,Skyler Dunn,Emery Vale,Finley Rhodes,Harper Lane,Kendall Frost,Logan Pryce,Parker Wynn', null, null, false },
      new List<Object>{ 'Email_Addresses', 'Email Addresses', 'SubstituteFromList', 'jamie.carter@example.com,sam.patel@example.com,morgan.reid@example.com,taylor.brooks@example.com,jordan.ellis@example.com,casey.flynn@example.com,riley.hart@example.com,avery.quinn@example.com,robin.shaw@example.com,drew.lawson@example.com,quinn.mercer@example.com,hayden.cole@example.com', null, null, false },
      new List<Object>{ 'Phone_Numbers', 'Phone Numbers', 'SubstituteFromList', '020 7946 0958,020 7946 0112,020 7946 0733,0161 496 0281,0161 496 0645,0113 496 0377,0113 496 0820,0117 496 0149,0141 496 0562,0131 496 0904', null, null, false },
      new List<Object>{ 'Postal_Addresses', 'Postal Addresses', 'SubstituteFromList', '12 Orchard Lane Leeds LS1 4AB,7 Mill Road Bristol BS1 5TR,48 Kings Court Manchester M2 3HQ,3 Harbour View Cardiff CF10 4PL,91 Elm Avenue Edinburgh EH2 1JD,25 Station Street York YO1 6HT,6 Castle Row Norwich NR1 3DN,134 Park Crescent Bath BA1 2NQ', null, null, false },
      new List<Object>{ 'Dates_Of_Birth', 'Dates Of Birth', 'SubstituteFromList', '1980-01-15,1975-06-02,1991-11-23,1968-03-30,1985-09-08,1994-12-19,1972-07-04,1988-02-27', null, null, false },
      new List<Object>{ 'Usernames', 'Usernames', 'SubstituteFromList', 'user.alpha,user.bravo,user.charlie,user.delta,user.echo,user.foxtrot,user.golf,user.hotel', null, null, false },
      new List<Object>{ 'Social_Security_Numbers', 'Social Security Numbers', 'RandomizeByPattern', null, '###-##-####', null, false },
      new List<Object>{ 'National_Insurance_Numbers', 'National Insurance Numbers', 'RandomizeByPattern', null, 'AA######A', null, false },
      new List<Object>{ 'NHS_Numbers', 'NHS Numbers', 'RandomizeByPattern', null, '### ### ####', null, false },
      new List<Object>{ 'Card_Numbers', 'Card Numbers', 'RandomizeByPattern', null, '#### #### #### ####', null, false },
      new List<Object>{ 'Bank_Account_Numbers', 'Bank Account Numbers', 'RandomizeByPattern', null, '########', null, false },
      new List<Object>{ 'IP_Addresses', 'IP Addresses', 'RandomizeByPattern', null, '10.###.###.###', null, false },
      new List<Object>{ 'Identifiers', 'Identifiers', 'RandomizeByPattern', null, 'ID-########', 8, false },
      new List<Object>{ 'Secrets', 'Secrets', 'RandomizeByPattern', null, '********', 8, true },
      new List<Object>{ 'Generic_Redaction', 'Generic Redaction', 'RandomizeByPattern', null, '[REDACTED]', null, true },
      new List<Object>{ 'Retired_Rule', 'Retired Rule', 'SubstituteFromList', 'Value One,Value Two', null, null, false }
    };
    for (List<Object> ruleRow : ruleRows) {
      container.addMetadata(
        metadataRecord(
          AIPiiDataMaskingRule__mdt.SObjectType,
          (String) ruleRow[0],
          (String) ruleRow[1],
          new Map<Schema.SObjectField, Object>{
            AIPiiDataMaskingRule__mdt.Strategy__c => ruleRow[2],
            AIPiiDataMaskingRule__mdt.SubstituteValues__c => ruleRow[3],
            AIPiiDataMaskingRule__mdt.ReplacementPattern__c => ruleRow[4],
            AIPiiDataMaskingRule__mdt.ReplacementCharacterCount__c => ruleRow[5],
            AIPiiDataMaskingRule__mdt.Redact__c => ruleRow[6],
            AIPiiDataMaskingRule__mdt.IsActive__c => ruleRow[0] != 'Retired_Rule'
          }
        )
      );
      recordCount++;
    }

    // ---------- Field types, most specific first. Developer name, PII field type, match field, keywords, masking rule, compliance group, fallback for the group.
    List<List<Object>> typeRows = new List<List<Object>>{
      new List<Object>{ 'National_Insurance_Number', 'National Insurance Number', 'NameOrLabelContains', 'national insurance,ni number,nino', 'National_Insurance_Numbers', 'GDPR', false },
      new List<Object>{ 'NHS_Number', 'NHS Number', 'NameOrLabelContains', 'nhs number,nhs no', 'NHS_Numbers', 'GDPR', false },
      new List<Object>{ 'SSN', 'SSN', 'NameOrLabelContains', 'ssn,social security', 'Social_Security_Numbers', 'PII', false },
      new List<Object>{ 'Credit_Card', 'Credit Card', 'NameOrLabelContains', 'credit card,card number,cardnumber', 'Card_Numbers', 'PCI', true },
      new List<Object>{ 'Bank_Account', 'Bank Account', 'NameOrLabelContains', 'bank account,account number,iban,sort code,routing number', 'Bank_Account_Numbers', 'PCI', false },
      new List<Object>{ 'VAT_Number', 'VAT Number', 'NameOrLabelContains', 'vat number,vat registration', 'Identifiers', null, false },
      new List<Object>{ 'Medical_Record_Number', 'Medical Record Number', 'NameOrLabelContains', 'medical record,patient number,mrn', 'Identifiers', 'HIPAA', true },
      new List<Object>{ 'Vehicle_Registration', 'Vehicle Registration', 'NameOrLabelContains', 'vehicle registration,number plate,licence plate,license plate', 'Identifiers', null, false },
      new List<Object>{ 'Government_ID', 'Government ID', 'NameOrLabelContains', 'passport,driving licence,driver license,national id,tax id', 'Identifiers', 'PII', false },
      new List<Object>{ 'Date_of_Birth', 'Date of Birth', 'NameOrLabelContains', 'birthdate,date of birth,dob', 'Dates_Of_Birth', 'PII', false },
      new List<Object>{ 'IP_Address', 'IP Address', 'NameOrLabelContains', 'ip address,ipaddress', 'IP_Addresses', 'GDPR', false },
      new List<Object>{ 'Password', 'Password', 'NameOrLabelContains', 'password,passcode,security answer', 'Secrets', null, false },
      new List<Object>{ 'Username', 'Username', 'NameOrLabelContains', 'username,user name,login name', 'Usernames', null, false },
      new List<Object>{ 'Email_By_Data_Type', 'Email', 'DataTypeContains', 'email', 'Email_Addresses', 'PII', false },
      new List<Object>{ 'Email_By_Name', 'Email', 'NameOrLabelContains', 'email', 'Email_Addresses', 'PII', false },
      new List<Object>{ 'Phone_By_Data_Type', 'Phone', 'DataTypeContains', 'phone', 'Phone_Numbers', 'PII', false },
      new List<Object>{ 'Phone_By_Name', 'Phone', 'NameOrLabelContains', 'phone,mobile,fax', 'Phone_Numbers', 'PII', false },
      new List<Object>{ 'Address_By_Data_Type', 'Address', 'DataTypeContains', 'address', 'Postal_Addresses', 'PII', false },
      new List<Object>{ 'Address_By_Name', 'Address', 'NameOrLabelContains', 'street,city,postal code,postcode,zip', 'Postal_Addresses', 'PII', false },
      new List<Object>{ 'Name_By_Api_Name', 'Name', 'ApiNameExact', 'name,firstname,lastname,middlename', 'Person_Names', 'PII', false },
      new List<Object>{ 'Name_By_Label', 'Name', 'NameOrLabelContains', 'first name,last name,full name,middle name', 'Person_Names', 'PII', false },
      new List<Object>{ 'Other_PII', 'Other', 'ApiNameExact', 'aiassistsampleotherfield', 'Generic_Redaction', 'PII', true },
      new List<Object>{ 'Other_GDPR', 'Other', 'ApiNameExact', 'aiassistsamplegdprfield', 'Generic_Redaction', 'GDPR', true }
    };
    for (Integer typeIndex = 0; typeIndex < typeRows.size(); typeIndex++) {
      List<Object> typeRow = typeRows[typeIndex];
      container.addMetadata(
        metadataRecord(
          AIPiiFieldType__mdt.SObjectType,
          (String) typeRow[0],
          ((String) typeRow[0]).replace('_', ' '),
          new Map<Schema.SObjectField, Object>{
            AIPiiFieldType__mdt.PIIFieldType__c => typeRow[1],
            AIPiiFieldType__mdt.MatchField__c => typeRow[2],
            AIPiiFieldType__mdt.Keyword__c => typeRow[3],
            AIPiiFieldType__mdt.MaskingRule__c => typeRow[4],
            AIPiiFieldType__mdt.ComplianceGroup__c => typeRow[5],
            AIPiiFieldType__mdt.IsComplianceGroupFallback__c => typeRow[6],
            AIPiiFieldType__mdt.DisplayOrder__c => (typeIndex + 1) * 10,
            AIPiiFieldType__mdt.IsActive__c => true
          }
        )
      );
      recordCount++;
    }

    // ---------- Chat commands. Developer name, command, description, prompt, available to, object, order, active. One is limited to the sample sales agent when it exists.
    List<AIAgent__c> salesAgents = [
      SELECT DeveloperName__c
      FROM AIAgent__c
      WHERE Name = :(PREFIX + 'Sales Assistant')
      LIMIT 1
    ];
    String salesAgentName = salesAgents.isEmpty()
      ? null
      : salesAgents[0].DeveloperName__c;
    List<List<Object>> commandRows = new List<List<Object>>{
      new List<Object>{ 'Summarise', '/summarise', 'Summarise this record or conversation.', 'Summarise the record in five bullet points or fewer. Lead with what matters most to someone picking it up for the first time.', 'All Users', null, 10, true, null },
      new List<Object>{ 'Next_Steps', '/next-steps', 'Suggest what to do next.', 'List up to three concrete next steps for this record, each with who should do it and by when. Base them only on the data you have.', 'All Users', null, 20, true, null },
      new List<Object>{ 'Draft_Email', '/draft-email', 'Draft a follow-up email.', 'Draft a short, polite follow-up email to the main contact. Plain text, under 120 words, with a clear ask in the last line.', 'All Users', null, 30, true, null },
      new List<Object>{ 'Explain', '/explain', 'Explain the last answer in simpler terms.', 'Explain your previous answer again in plain English, as if to someone new to the business. Keep it under 100 words.', 'All Users', null, 40, true, null },
      new List<Object>{ 'Account_Brief', '/account-brief', 'A briefing on this account before a meeting.', 'Write a pre-meeting briefing for this account: who they are, open opportunities, open cases, and one risk to raise.', 'All Users', 'Account', 50, true, null },
      new List<Object>{ 'Deal_Risks', '/deal-risks', 'What could stop this deal closing.', 'List the risks to this opportunity closing on its close date, most serious first, with the evidence for each.', 'Super Users and Admins', 'Opportunity', 60, true, salesAgentName },
      new List<Object>{ 'Case_Recap', '/case-recap', 'A recap of this case for a handover.', 'Write a handover note for this case: the problem, what has been tried, what the customer is waiting for.', 'All Users', 'Case', 70, true, null },
      new List<Object>{ 'Debug', '/debug', 'Show what was sent to the model for the last answer.', 'List the data sources you used for the previous answer, the objects and number of records each returned, and anything that was masked.', 'Admins Only', null, 90, true, null },
      new List<Object>{ 'Translate', '/translate', 'Retired: translate the last answer.', 'Translate your previous answer into French.', 'All Users', null, 100, false, null }
    };
    for (List<Object> commandRow : commandRows) {
      container.addMetadata(
        metadataRecord(
          AIChatCommand__mdt.SObjectType,
          (String) commandRow[0],
          ((String) commandRow[0]).replace('_', ' '),
          new Map<Schema.SObjectField, Object>{
            AIChatCommand__mdt.Command__c => commandRow[1],
            AIChatCommand__mdt.Description__c => commandRow[2],
            AIChatCommand__mdt.PromptText__c => commandRow[3],
            AIChatCommand__mdt.AvailableTo__c => commandRow[4],
            AIChatCommand__mdt.ObjectAPIName__c => commandRow[5],
            AIChatCommand__mdt.DisplayOrder__c => commandRow[6],
            AIChatCommand__mdt.IsActive__c => commandRow[7],
            AIChatCommand__mdt.AgentDeveloperName__c => commandRow[8]
          }
        )
      );
      recordCount++;
    }

    try {
      Id deploymentId = Metadata.Operations.enqueueDeployment(container, null);
      summary.add(
        'Custom metadata: ' +
          recordCount +
          ' records queued for deployment ' +
          deploymentId +
          ' (Setup > Deployment Status)'
      );
    } catch (Exception caughtException) {
      problems.add('Custom metadata: ' + caughtException.getMessage());
    }
  }

  // Type and field names come from describe, so they carry the namespace when the org has one.
  Metadata.CustomMetadata metadataRecord(
    Schema.SObjectType metadataType,
    String developerName,
    String label,
    Map<Schema.SObjectField, Object> valueByField
  ) {
    Metadata.CustomMetadata record = new Metadata.CustomMetadata();
    record.fullName =
      metadataType.getDescribe().getName().removeEnd('__mdt') +
      '.' +
      developerName;
    record.label = label;

    for (Schema.SObjectField field : valueByField.keySet()) {
      Metadata.CustomMetadataValue fieldValue = new Metadata.CustomMetadataValue();
      fieldValue.field = field.getDescribe().getName();
      fieldValue.value = valueByField.get(field);
      record.values.add(fieldValue);
    }

    return record;
  }
}

new SampleDataLoader().run();
