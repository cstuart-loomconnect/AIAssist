/*
Class Name: AIPiiRegistryController

=================================================================
=================================================================

Description: The Apex controller behind the AI PII Registry tab.

Step 1: Read the registered objects, one object's fields and the objects to add
Step 2: Add an object, switch it on or off and queue a sync
Step 3: Override a field, hand it back to the automatic rules, and test the masking on a record
Step 4: Show an expected refusal as it is, and log anything unexpected once and show the generic label

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPiiRegistryController {

    public class AIPiiRegistryControllerException extends Exception {}

    // The registered objects, the limit, the PII types and the objects agents read without cover.
    @AuraEnabled
    public static AIPiiRegistryDataStructure.RegistryPage getRegistryPage() {

        try {

            // [1] Do the work
            return AIPiiRegistryEditorService.getRegistryPage();

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getRegistryPage');
        }
    }

    // One registered object with its fields.
    @AuraEnabled
    public static AIPiiRegistryDataStructure.RegistryDetail getRegistryDetail(Id registryId) {

        try {

            // [1] Do the work
            return AIPiiRegistryEditorService.getRegistryDetail(registryId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getRegistryDetail');
        }
    }

    // The registered objects as they are now, so the tab can follow a sync.
    @AuraEnabled
    public static List<AIPiiRegistryDataStructure.RegistryView> getRegistryViews() {

        try {

            // [1] Do the work
            return AIPiiRegistryEditorService.getRegistryViews();

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getRegistryViews');
        }
    }

    // The objects whose label or API name contains the text and that are not in the registry yet.
    @AuraEnabled
    public static List<AIPiiRegistryDataStructure.ObjectOption> getObjectOptions(String searchText) {

        try {

            // [1] Do the work
            return AIPiiRegistryCoverageService.getObjectOptions(searchText);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getObjectOptions');
        }
    }

    // Adds an object and queues its first sync.
    @AuraEnabled
    public static AIPiiRegistryDataStructure.RegistryView addRegistryObject(String objectApiName, Integer maxFieldsToQuery) {

        try {

            // [1] Do the work
            return AIPiiRegistryEditorService.addRegistryObject(objectApiName, maxFieldsToQuery);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'addRegistryObject');
        }
    }

    // Switches an object on or off.
    @AuraEnabled
    public static AIPiiRegistryDataStructure.RegistryView setRegistryActive(Id registryId, Boolean isActive) {

        try {

            // [1] Do the work
            return AIPiiRegistryEditorService.setRegistryActive(registryId, isActive);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'setRegistryActive');
        }
    }

    // Queues a sync of an object, with a new field limit when one is given.
    @AuraEnabled
    public static AIPiiRegistryDataStructure.RegistryView syncRegistry(Id registryId, Integer maxFieldsToQuery) {

        try {

            // [1] Do the work
            return AIPiiRegistryEditorService.syncRegistry(registryId, maxFieldsToQuery);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'syncRegistry');
        }
    }

    // Sets by hand whether a field is PII, and its type.
    @AuraEnabled
    public static AIPiiRegistryDataStructure.FieldView saveFieldOverride(Id fieldId, Boolean isPii, String piiFieldType) {

        try {

            // [1] Do the work
            return AIPiiRegistryEditorService.saveFieldOverride(fieldId, isPii, piiFieldType);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'saveFieldOverride');
        }
    }

    // Hands a field back to the automatic rules.
    @AuraEnabled
    public static AIPiiRegistryDataStructure.FieldView resetFieldOverride(Id fieldId) {

        try {

            // [1] Do the work
            return AIPiiRegistryEditorService.resetFieldOverride(fieldId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'resetFieldOverride');
        }
    }

    // Shows what would be sent to the provider for a record of the object.
    @AuraEnabled
    public static AIPiiRegistryDataStructure.MaskingTestResult runMaskingTest(Id registryId, Id recordId) {

        try {

            // [1] Do the work
            return AIPiiRegistryMaskingTestService.runMaskingTest(registryId, recordId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'runMaskingTest');
        }
    }

    // Shows a package refusal as it is, which is already a Custom Label, and logs anything else once so the tab gets the generic label.
    private static AuraHandledException buildAuraException(Exception ex, String methodName) {

        // [1] Choose the text
        String errorText = Label.AI_Error_Generic;
        if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
        else AIPlatformLogManager.logException(ex, 'AIPiiRegistryController', methodName);

        // [2] Build the exception the tab can read
        AuraHandledException auraException = new AuraHandledException(errorText);
        auraException.setMessage(errorText);

        return auraException;
    }
}
