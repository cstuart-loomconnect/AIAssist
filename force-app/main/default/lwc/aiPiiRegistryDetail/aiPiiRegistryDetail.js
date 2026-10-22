/*
Component Name: aiPiiRegistryDetail

=================================================================
=================================================================

Description: The pane of one registered object: its header, its fields, why its last sync failed, and its masking test.

Step 1: Show the object's name, sync status, field limit, Active switch and Sync now button
Step 2: Show the Fields tab, or the failure, or a note that the sync is still running
Step 3: Show the Test masking tab
Step 4: Tell the tab when the admin switches the object, syncs it, overrides a field or opens the log

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, TAB_FIELDS, TAB_TEST, TAB_CLASS, TAB_SELECTED_CLASS, STATUS_NOT_SYNCED, STATUS_QUEUED, STATUS_IN_PROGRESS, STATUS_FAILED, EVENT_ACTIVE_CHANGE, EVENT_SYNC, EVENT_FIELD_OVERRIDE, EVENT_FIELD_RESET, EVENT_VIEW_LOG, NO_TEXT, ARIA_TRUE, ARIA_FALSE } from "./aiPiiRegistryDetailSettings";
import { buildChip, buildFailedMessage, buildRaiseLabel } from "./aiPiiRegistryDetailHelper";

// The pane of one registered object.
export default class AiPiiRegistryDetail extends LightningElement {

  // Values passed in by the parent component
  @api registry; // RegistryView from AIPiiRegistryController
  @api fields = []; // FieldView list for the Fields tab, empty until the pane has loaded
  @api typeOptions = []; // TypeOption list for the PII type boxes
  @api isFieldLimitReached = false; // True when the failed sync was cut short by Max Fields To Query
  @api suggestedMaxFields = null; // The next limit to try, blank when the limit is already the largest
  @api isLoading = false; // True while the fields load
  @api isSaving = false; // True while a change is being saved, so the controls wait
  @api errorMessage = NO_TEXT; // The message from the last failed change, or blank

  // Values the template reads
  labels = LABELS;

  // State of the pane
  activeTab = TAB_FIELDS;
  typedMaxFields = null;

  get objectName() {

    // [1] The API name of the object
    const objectName = this.registry.objectApiName;

    return objectName;
  }

  get chipLabel() {

    // [1] Hand the work to the helper
    const chipLabel = buildChip(this.registry).label;

    return chipLabel;
  }

  get chipClass() {

    // [1] Hand the work to the helper
    const chipClass = buildChip(this.registry).chipClass;

    return chipClass;
  }

  get maxFieldsText() {

    // [1] Join the parts
    const maxFieldsText = LABELS.maxFieldsBefore + this.registry.maxFieldsToQuery + LABELS.maxFieldsAfter;

    return maxFieldsText;
  }

  get isRunning() {

    // [1] A sync is waiting or under way
    const isRunning = this.registry.syncStatus === STATUS_QUEUED || this.registry.syncStatus === STATUS_IN_PROGRESS;

    return isRunning;
  }

  get isSyncDisabled() {

    // [1] A sync cannot start while one is waiting, or while a change is being saved
    const isSyncDisabled = this.isRunning || this.isSaving;

    return isSyncDisabled;
  }

  get isFailed() {

    // [1] The last sync failed
    const isFailed = this.registry.syncStatus === STATUS_FAILED;

    return isFailed;
  }

  get isNeverSynced() {

    // [1] The object has not been synced yet
    const isNeverSynced = this.registry.syncStatus === STATUS_NOT_SYNCED;

    return isNeverSynced;
  }

  get waitingText() {

    // [1] Say what the sync is doing
    const waitingText = this.registry.syncStatus === STATUS_QUEUED ? LABELS.waitingQueued : LABELS.waitingSyncing;

    return waitingText;
  }

  get showFields() {

    // [1] The fields show once a sync has finished well
    const showFields = !this.isRunning && !this.isFailed && !this.isNeverSynced;

    return showFields;
  }

  get isFieldsTab() {

    // [1] The Fields tab is chosen
    const isFieldsTab = this.activeTab === TAB_FIELDS;

    return isFieldsTab;
  }

  get isTestTab() {

    // [1] The Test masking tab is chosen
    const isTestTab = this.activeTab === TAB_TEST;

    return isTestTab;
  }

  get fieldsTabClass() {

    // [1] The chosen tab is marked
    const fieldsTabClass = this.isFieldsTab ? TAB_SELECTED_CLASS : TAB_CLASS;

    return fieldsTabClass;
  }

  get testTabClass() {

    // [1] The chosen tab is marked
    const testTabClass = this.isTestTab ? TAB_SELECTED_CLASS : TAB_CLASS;

    return testTabClass;
  }

  get fieldsTabSelected() {

    // [1] The aria text for a screen reader
    const fieldsTabSelected = this.isFieldsTab ? ARIA_TRUE : ARIA_FALSE;

    return fieldsTabSelected;
  }

  get testTabSelected() {

    // [1] The aria text for a screen reader
    const testTabSelected = this.isTestTab ? ARIA_TRUE : ARIA_FALSE;

    return testTabSelected;
  }

  get isInactive() {

    // [1] A switched off object is not masked
    const isInactive = !this.registry.isActive;

    return isInactive;
  }

  get inactiveText() {

    // [1] Join the parts
    const inactiveText = LABELS.switchedOffBefore + this.registry.objectApiName + LABELS.switchedOffAfter;

    return inactiveText;
  }

  get failedLead() {

    // [1] Hand the work to the helper
    const failedLead = buildFailedMessage(this.registry, this.isFieldLimitReached).lead;

    return failedLead;
  }

  get failedRest() {

    // [1] Hand the work to the helper
    const failedRest = buildFailedMessage(this.registry, this.isFieldLimitReached).rest;

    return failedRest;
  }

  get canRaiseLimit() {

    // [1] A limit can be raised when it was too small and a higher one is allowed
    const canRaiseLimit = this.isFieldLimitReached && Boolean(this.suggestedMaxFields);

    return canRaiseLimit;
  }

  get isLimitLargest() {

    // [1] The limit was too small but cannot go higher
    const isLimitLargest = this.isFieldLimitReached && !this.suggestedMaxFields;

    return isLimitLargest;
  }

  get raiseHint() {

    // [1] Join the parts
    const raiseHint = LABELS.raiseHintBefore + this.registry.objectApiName + LABELS.raiseHintAfter;

    return raiseHint;
  }

  get largestHint() {

    // [1] Join the parts
    const largestHint = LABELS.largestHintBefore + this.registry.maxFieldsToQuery + LABELS.largestHintAfter;

    return largestHint;
  }

  get raiseMaxFields() {

    // [1] The limit the admin typed, or the one suggested
    const raiseMaxFields = this.typedMaxFields === null ? this.suggestedMaxFields : this.typedMaxFields;

    return raiseMaxFields;
  }

  get raiseLabel() {

    // [1] Hand the work to the helper
    const raiseLabel = buildRaiseLabel(this.raiseMaxFields, this.registry.maxFieldsToQuery);

    return raiseLabel;
  }

  get unmaskedText() {

    // [1] Join the parts
    const objectName = this.registry.objectApiName;
    const unmaskedText = LABELS.unmaskedBefore + objectName + LABELS.unmaskedMiddle + objectName + LABELS.unmaskedAfter;

    return unmaskedText;
  }

  get hasErrorMessage() {

    // [1] Show the message box only when there is a message
    const hasErrorMessage = Boolean(this.errorMessage);

    return hasErrorMessage;
  }

  // Event handlers
  handleTabClick(event) {

    // [1] Show the tab the admin picked
    this.activeTab = event.currentTarget.dataset.tab;
  }

  handleActiveChange(event) {

    // [1] Tell the tab to switch the object on or off
    this.dispatchEvent(new CustomEvent(EVENT_ACTIVE_CHANGE, { detail: { isActive: event.target.checked } }));
  }

  handleSyncNow() {

    // [1] Tell the tab to sync with the limit as it is
    this.dispatchEvent(new CustomEvent(EVENT_SYNC, { detail: { maxFieldsToQuery: null } }));
  }

  handleMaxFieldsInput(event) {

    // [1] Keep the limit the admin typed, or go back to the suggestion when the box is cleared
    const typedText = event.target.value;
    this.typedMaxFields = typedText ? Number(typedText) : null;
  }

  handleRaiseAndSync() {

    // [1] Tell the tab to sync with the new limit, or with the same one when it is not higher
    const isHigher = this.raiseMaxFields && this.raiseMaxFields > this.registry.maxFieldsToQuery;
    const maxFieldsToQuery = isHigher ? this.raiseMaxFields : null;
    this.dispatchEvent(new CustomEvent(EVENT_SYNC, { detail: { maxFieldsToQuery } }));
  }

  handleViewLog() {

    // [1] Tell the tab to open the platform log
    this.dispatchEvent(new CustomEvent(EVENT_VIEW_LOG));
  }

  handleFieldOverride(event) {

    // [1] Pass the choice on to the tab
    this.dispatchEvent(new CustomEvent(EVENT_FIELD_OVERRIDE, { detail: event.detail }));
  }

  handleFieldReset(event) {

    // [1] Pass the choice on to the tab
    this.dispatchEvent(new CustomEvent(EVENT_FIELD_RESET, { detail: event.detail }));
  }
}
