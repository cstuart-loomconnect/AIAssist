/*
Component Name: aiPolicies

=================================================================
=================================================================

Description: The AI Policies tab: create and change usage policies and choose who each one applies to.

Step 1: Load every policy with its assignments and show them as a list
Step 2: Show the chosen policy with a Settings tab and an Assignments tab
Step 3: Save the policy, create a new one, or delete one after asking where its people move to
Step 4: Add, switch on or off and remove assignments, and keep the list up to date

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getPolicies from "@salesforce/apex/AIPoliciesController.getPolicies";
import savePolicy from "@salesforce/apex/AIPoliciesController.savePolicy";
import deletePolicy from "@salesforce/apex/AIPoliciesController.deletePolicy";
import addAssignment from "@salesforce/apex/AIPoliciesController.addAssignment";
import setAssignmentActive from "@salesforce/apex/AIPoliciesController.setAssignmentActive";
import removeAssignment from "@salesforce/apex/AIPoliciesController.removeAssignment";
import {
  NEW_POLICY_KEY,
  NEW_POLICY_VALUES,
  FIELD_NAME,
  FORM_KEY_SEPARATOR,
  TAB_SETTINGS,
  TAB_ASSIGNMENTS,
  ASSIGNEE_TYPE_USER,
  NO_TEXT,
  TOAST_VARIANT_SUCCESS,
  TOAST_VARIANT_ERROR,
  LABELS
} from "./aiPoliciesSettings";
import {
  buildPolicyItems,
  replacePolicy,
  formatErrorMessage
} from "./aiPoliciesHelper";

// The AI Policies tab. It lists the policies, shows the chosen one and runs every Apex call.
export default class AiPolicies extends LightningElement {
  // Values the template reads
  labels = LABELS;
  settingsTabValue = TAB_SETTINGS;
  assignmentsTabValue = TAB_ASSIGNMENTS;

  // State of the tab
  policies = [];
  selectedKey = null;
  activeTab = TAB_SETTINGS;
  isBusy = true;
  isSaving = false;
  errorMessage = NO_TEXT;
  formVersion = 0;

  // State of the dialogs
  isAssignOpen = false;
  assignErrorMessage = NO_TEXT;
  isDeleteOpen = false;
  deleteErrorMessage = NO_TEXT;

  // Lifecycle methods
  connectedCallback() {
    // [1] Load the policies when the tab opens
    this.loadPolicies();
  }

  // The policies turned into list items.
  get policyItems() {
    // [1] Hand the work to the helper
    const policyItems = buildPolicyItems(
      this.policies,
      this.selectedKey,
      this.isNewPolicy
    );

    return policyItems;
  }

  get showNoPolicies() {
    // [1] Say so when the load is done and nothing is listed
    const showNoPolicies = !this.isBusy && this.policyItems.length === 0;

    return showNoPolicies;
  }

  get isNewPolicy() {
    // [1] The new policy has its own key
    const isNewPolicy = this.selectedKey === NEW_POLICY_KEY;

    return isNewPolicy;
  }

  get selectedPolicy() {
    // [1] Find the saved policy the admin picked
    const selectedPolicy = this.policies.find(
      (policy) => policy.policyId === this.selectedKey
    );

    return selectedPolicy;
  }

  get hasSelection() {
    // [1] Something is picked when it is the new policy or a saved one
    const hasSelectedPolicy = Boolean(this.selectedPolicy);

    return this.isNewPolicy || hasSelectedPolicy;
  }

  get isSavedPolicy() {
    // [1] A saved policy has tabs and can be deleted
    const isSavedPolicy = Boolean(this.selectedPolicy);

    return isSavedPolicy;
  }

  get showChooseOne() {
    // [1] Ask the admin to pick a policy when the load is done and none is picked
    const showChooseOne = !this.isBusy && !this.hasSelection;

    return showChooseOne;
  }

  get selectedName() {
    // [1] The new policy has a fixed name
    if (this.isNewPolicy) return LABELS.newPolicyName;

    // [2] A saved policy has its own name
    const policy = this.selectedPolicy;
    const selectedName = policy ? policy.name : NO_TEXT;

    return selectedName;
  }

  get assignmentsTabLabel() {
    // [1] The tab says how many assignments the policy has
    const policy = this.selectedPolicy;
    const assignmentCount = policy ? policy.assignments.length : 0;
    const assignmentsTabLabel =
      LABELS.assignmentsTab + " (" + assignmentCount + ")";

    return assignmentsTabLabel;
  }

  get selectedAssignments() {
    // [1] The assignments of the chosen policy
    const policy = this.selectedPolicy;
    const selectedAssignments = policy ? policy.assignments : [];

    return selectedAssignments;
  }

  get formValues() {
    // [1] The new policy starts from the default values
    if (this.isNewPolicy) return { ...NEW_POLICY_VALUES };

    // [2] A saved policy fills the form with its values and its name
    const policy = this.selectedPolicy;
    const formValues = policy
      ? { ...policy.values, [FIELD_NAME]: policy.name }
      : {};

    return formValues;
  }

  // One item, so the form is built again whenever the policy or the saved values change.
  get formKeyItems() {
    // [1] The key changes with the chosen policy and the saved version
    const key = this.selectedKey + FORM_KEY_SEPARATOR + this.formVersion;

    return [{ key }];
  }

  // One item, so the assignments are built again whenever another policy is chosen.
  get assignmentsKeyItems() {
    // [1] The key is the chosen policy
    const key = this.selectedKey;

    return [{ key }];
  }

  // Event handlers
  handlePolicySelect(event) {
    // [1] Show the policy the admin picked, on the Settings tab
    this.selectedKey = event.currentTarget.dataset.key;
    this.activeTab = TAB_SETTINGS;
    this.errorMessage = NO_TEXT;
    this.formVersion = this.formVersion + 1;
  }

  handleNewPolicy() {
    // [1] Show an empty form that is saved as a new policy
    this.selectedKey = NEW_POLICY_KEY;
    this.activeTab = TAB_SETTINGS;
    this.errorMessage = NO_TEXT;
    this.formVersion = this.formVersion + 1;
  }

  handleTabActive(event) {
    // [1] Remember the tab, so it stays when the policy is saved
    this.activeTab = event.target.value;
  }

  async handleSave(event) {
    // [1] Save the values, creating the policy when it is new
    this.isSaving = true;
    this.errorMessage = NO_TEXT;

    try {
      const policyId = this.isNewPolicy ? null : this.selectedKey;
      const values = event.detail.values;
      const savedPolicy = await savePolicy({ policyId, values });

      // [2] Show the saved policy, which is now the chosen one
      this.policies = replacePolicy(this.policies, savedPolicy);
      this.selectedKey = savedPolicy.policyId;
      this.formVersion = this.formVersion + 1;
      this.showToast(LABELS.saved, TOAST_VARIANT_SUCCESS);
    } catch (error) {
      // [3] Show the reason inside the form
      this.errorMessage = formatErrorMessage(error);
    } finally {
      this.isSaving = false;
    }
  }

  handleCancel() {
    // [1] A new policy that is cancelled goes away, a saved one goes back to its saved values
    if (this.isNewPolicy) this.selectedKey = null;
    this.errorMessage = NO_TEXT;
    this.formVersion = this.formVersion + 1;
  }

  handleDeleteRequest() {
    // [1] Open the dialog that asks where the people move to
    this.deleteErrorMessage = NO_TEXT;
    this.isDeleteOpen = true;
  }

  handleDeleteCancel() {
    // [1] Close the dialog
    this.isDeleteOpen = false;
  }

  async handleDeleteConfirm(event) {
    // [1] Delete the policy, moving its people first
    this.isBusy = true;
    this.deleteErrorMessage = NO_TEXT;

    try {
      const policyId = this.selectedKey;
      const moveToPolicyId = event.detail.moveToPolicyId;
      this.policies = await deletePolicy({ policyId, moveToPolicyId });

      // [2] Close the dialog and show the list again
      this.isDeleteOpen = false;
      this.selectedKey = null;
      this.showToast(LABELS.deleted, TOAST_VARIANT_SUCCESS);
    } catch (error) {
      // [3] Show the reason inside the dialog
      this.deleteErrorMessage = formatErrorMessage(error);
    } finally {
      this.isBusy = false;
    }
  }

  handleAddRequest() {
    // [1] Open the dialog that picks who gets the policy
    this.assignErrorMessage = NO_TEXT;
    this.isAssignOpen = true;
  }

  handleAddCancel() {
    // [1] Close the dialog
    this.isAssignOpen = false;
  }

  async handleAddConfirm(event) {
    // [1] Assign the policy to the user or permission set that was picked
    this.isBusy = true;
    this.assignErrorMessage = NO_TEXT;

    try {
      const { assigneeType, assigneeId } = event.detail;
      const savedPolicy = await addAssignment({
        policyId: this.selectedKey,
        assigneeType,
        assigneeId
      });

      // [2] Show the policy as saved and close the dialog
      this.policies = replacePolicy(this.policies, savedPolicy);
      this.isAssignOpen = false;
      this.showToast(LABELS.assigned, TOAST_VARIANT_SUCCESS);
      this.refreshCheck();
    } catch (error) {
      // [3] Show the reason inside the dialog
      this.assignErrorMessage = formatErrorMessage(error);
    } finally {
      this.isBusy = false;
    }
  }

  async handleAssignmentActive(event) {
    // [1] Save the new state of the assignment
    this.isBusy = true;

    try {
      const { assignmentId, isActive } = event.detail;
      const savedPolicy = await setAssignmentActive({ assignmentId, isActive });
      this.policies = replacePolicy(this.policies, savedPolicy);
      this.refreshCheck();
      this.isBusy = false;
    } catch (error) {
      // [2] Show the reason and read the policies again, so the switch goes back to what is saved
      this.showToast(formatErrorMessage(error), TOAST_VARIANT_ERROR);
      await this.loadPolicies();
    }
  }

  async handleAssignmentRemove(event) {
    // [1] Remove the assignment
    this.isBusy = true;

    try {
      const assignmentId = event.detail.assignmentId;
      const savedPolicy = await removeAssignment({ assignmentId });

      // [2] Show the policy as saved
      this.policies = replacePolicy(this.policies, savedPolicy);
      this.showToast(LABELS.removed, TOAST_VARIANT_SUCCESS);
      this.refreshCheck();
    } catch (error) {
      // [3] Show the reason
      this.showToast(formatErrorMessage(error), TOAST_VARIANT_ERROR);
    } finally {
      this.isBusy = false;
    }
  }

  async handleAssignUser(event) {
    // [1] Give the user the policy the check said was ignored
    this.isBusy = true;

    try {
      const { policyId, userId } = event.detail;
      const savedPolicy = await addAssignment({
        policyId,
        assigneeType: ASSIGNEE_TYPE_USER,
        assigneeId: userId
      });

      // [2] Show the policy as saved and check the user again
      this.policies = replacePolicy(this.policies, savedPolicy);
      this.showToast(LABELS.assigned, TOAST_VARIANT_SUCCESS);
      this.refreshCheck();
    } catch (error) {
      // [3] Show the reason
      this.showToast(formatErrorMessage(error), TOAST_VARIANT_ERROR);
    } finally {
      this.isBusy = false;
    }
  }

  // Private methods
  async loadPolicies() {
    this.isBusy = true;

    try {
      // [1] Read every policy with its assignments
      this.policies = await getPolicies();
    } catch (error) {
      // [2] Show the reason
      this.showToast(formatErrorMessage(error), TOAST_VARIANT_ERROR);
    } finally {
      this.isBusy = false;
    }
  }

  refreshCheck() {
    // [1] Ask the Check a user box to work out its answer again, when it is on screen
    const assignments = this.template.querySelector(
      "c-ai-policies-assignments"
    );
    if (assignments) assignments.refreshCheck();
  }

  showToast(message, variant) {
    // [1] Show the message at the top of the page
    const toastEvent = new ShowToastEvent({ message, variant });
    this.dispatchEvent(toastEvent);
  }
}
