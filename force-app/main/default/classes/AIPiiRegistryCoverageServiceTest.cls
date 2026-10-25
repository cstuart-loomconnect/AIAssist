/*
Class Name: AIPiiRegistryCoverageServiceTest

=================================================================
=================================================================

Description: Testing utility for AIPiiRegistryCoverageService: the objects agents read without cover, and the object search of the Add object dialog.

=================================================================
=================================================================
Applicable Classes:

AIPiiRegistryCoverageService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPiiRegistryCoverageServiceTest {

    // testScenario1: Active data sources read objects the registry does not cover -> each object is listed once, in name order, with its data sources and the plain fields their queries select.
    // testScenario2: A data source is inactive, an Apex one, or reads an object that has a registry -> inactive and covered ones are left out, and an Apex one has no fields.
    // testScenario3: A manager searches for an object -> matches by label or API name come back with field and data source counts, without registered, history or sharing objects.
    // testScenario4: The search text is too short or matches nothing -> nothing comes back.
    // testScenario5: A user without the Manage Settings permission calls the service -> the access label is shown.

    private static final String CONTACT = 'Contact';
    private static final String SELECT_CASE = 'SELECT Id, Subject, Account.Name, toLabel(Status), COUNT(Id), (SELECT Id FROM CaseComments) FROM Case LIMIT 5';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two data sources that read Case and one that reads EmailMessage
            List<AIDataSource__c> caseSources = AIAssistTestDataFactory.createAIDataSources(2, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SELECT_CASE, false);
            caseSources[0].TargetObject__c = 'Case';
            caseSources[1].TargetObject__c = 'Case';
            caseSources[1].SOQLTemplate__c = 'SELECT Id, Subject, Description FROM Case LIMIT 5';
            List<AIDataSource__c> emailSources = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT FromAddress FROM EmailMessage LIMIT 5', false);
            emailSources[0].TargetObject__c = 'EmailMessage';
            insert new List<AIDataSource__c>{ caseSources[0], caseSources[1], emailSources[0] };

            // [2] Find the objects without cover
            Test.startTest();
                List<AIPiiRegistryDataStructure.UnprotectedObject> unprotectedObjects = AIPiiRegistryCoverageService.getUnprotectedObjects();
            Test.stopTest();

            // [3] Check the objects, their sources and their fields
            Assert.areEqual(2, unprotectedObjects.size(), 'Case and EmailMessage.');
            Assert.areEqual('Case', unprotectedObjects[0].objectApiName, 'In name order.');
            Assert.areEqual(2, unprotectedObjects[0].dataSourceNames.size(), 'Both Case sources.');
            Assert.areEqual(new List<String>{ 'Id', 'Subject', 'Account.Name', 'Description' }, unprotectedObjects[0].fieldsSent, 'Plain fields once each, without functions, subqueries or aliases.');
            Assert.areEqual(new List<String>{ 'FromAddress' }, unprotectedObjects[1].fieldsSent, 'The EmailMessage field.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an inactive Case source, an Apex Lead source, and a Contact source that has a registry
            List<AIDataSource__c> inactiveSources = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SELECT_CASE, false);
            inactiveSources[0].TargetObject__c = 'Case';
            inactiveSources[0].IsActive__c = false;
            List<AIDataSource__c> apexSources = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX, 'SomeClass', false);
            apexSources[0].TargetObject__c = 'Lead';
            List<AIDataSource__c> coveredSources = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Email FROM Contact LIMIT 5', false);
            coveredSources[0].TargetObject__c = 'contact';
            insert new List<AIDataSource__c>{ inactiveSources[0], apexSources[0], coveredSources[0] };
            AIAssistTestDataFactory.createAIPIIRegistries(1, CONTACT, true);

            // [2] Find the objects without cover
            Test.startTest();
                List<AIPiiRegistryDataStructure.UnprotectedObject> unprotectedObjects = AIPiiRegistryCoverageService.getUnprotectedObjects();
            Test.stopTest();

            // [3] Check only the Apex source's object is left
            Assert.areEqual(1, unprotectedObjects.size(), 'Only Lead is uncovered: Case is inactive and Contact is registered whatever its case.');
            Assert.areEqual('Lead', unprotectedObjects[0].objectApiName, 'It is Lead.');
            Assert.isTrue(unprotectedObjects[0].fieldsSent.isEmpty(), 'An Apex source sets its own fields.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Register Contact, and create a data source that reads Opportunity
            AIAssistTestDataFactory.createAIPIIRegistries(1, CONTACT, true);
            List<AIDataSource__c> sources = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Name FROM Opportunity LIMIT 5', false);
            sources[0].TargetObject__c = 'Opportunity';
            insert sources;

            // [2] Search for Opportunity by part of its name, and for Contact, which is registered
            Test.startTest();
                List<AIPiiRegistryDataStructure.ObjectOption> opportunityOptions = AIPiiRegistryCoverageService.getObjectOptions('  OPPORTUN ');
                List<AIPiiRegistryDataStructure.ObjectOption> contactOptions = AIPiiRegistryCoverageService.getObjectOptions('contact');
            Test.stopTest();

            // [3] Find Opportunity in the first, and note any history or sharing object
            AIPiiRegistryDataStructure.ObjectOption opportunityOption;
            Boolean hasHistoryObject = false;

            for (AIPiiRegistryDataStructure.ObjectOption option : opportunityOptions) {

                if (option.objectApiName == 'Opportunity') opportunityOption = option;
                if (option.objectApiName.endsWith('History') || option.objectApiName.endsWith('Share')) hasHistoryObject = true;
            }

            Boolean hasContact = false;

            for (AIPiiRegistryDataStructure.ObjectOption option : contactOptions) {

                if (option.objectApiName == CONTACT) hasContact = true;
            }

            // [4] Check the match, its counts, and what was left out
            Assert.isNotNull(opportunityOption, 'Opportunity matches.');
            Assert.areEqual('Opportunity', opportunityOption.objectLabel, 'With its label.');
            Assert.isTrue(opportunityOption.fieldCount > 10, 'And its fields.');
            Assert.areEqual(1, opportunityOption.dataSourceCount, 'And the data source that reads it.');
            Assert.isFalse(hasHistoryObject, 'History and sharing objects are left out.');
            Assert.isFalse(hasContact, 'A registered object is left out.');
            Assert.isTrue(opportunityOptions.size() <= AIAssistApplicationConstants.PII_OBJECT_SEARCH_MAX_RESULTS, 'The list is capped.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Search with one letter, with nothing, and for an object that does not exist
            Test.startTest();
                List<AIPiiRegistryDataStructure.ObjectOption> shortOptions = AIPiiRegistryCoverageService.getObjectOptions('a');
                List<AIPiiRegistryDataStructure.ObjectOption> blankOptions = AIPiiRegistryCoverageService.getObjectOptions(null);
                List<AIPiiRegistryDataStructure.ObjectOption> noMatchOptions = AIPiiRegistryCoverageService.getObjectOptions('zzqqxx');
            Test.stopTest();

            // [2] Check nothing came back
            Assert.isTrue(shortOptions.isEmpty(), 'One letter is too short to search with.');
            Assert.isTrue(blankOptions.isEmpty(), 'No text is too short too.');
            Assert.isTrue(noMatchOptions.isEmpty(), 'Nothing matches.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            List<String> refusals = new List<String>();

            // [2] Call both methods as that user
            Test.startTest();
                System.runAs(users[0]) {
                    try {

                        AIPiiRegistryCoverageService.getUnprotectedObjects();
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIPiiRegistryCoverageService.getObjectOptions('contact');
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(2, refusals.size(), 'Both calls were refused.');
            Assert.areEqual(Label.AI_Settings_Error_Access, refusals[0], 'The access label is shown.');
        }
    }
}
