/*
Component Name: aiAssistUsagePolicies

=================================================================
=================================================================

Description: The AI Usage Policies tab: create and change policies.

Step 1: Load every policy with its assignments and show them as a list
Step 2: Show the chosen policy in the form, in three groups that hold every field
Step 3: Save the policy, create a new one, or delete one after asking

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement } from "lwc";
import LightningConfirm from "lightning/confirm";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getPolicies from "@salesforce/apex/AIAssistSettingsController.getPolicies";
import savePolicy from "@salesforce/apex/AIAssistSettingsController.savePolicy";
import deletePolicy from "@salesforce/apex/AIAssistSettingsController.deletePolicy";
import { NEW_POLICY_KEY, NEW_POLICY_VALUES, FIELD_NAME, FORM_KEY_SEPARATOR, CONFIRM_VARIANT, NO_TEXT, TOAST_VARIANT_SUCCESS, TOAST_VARIANT_ERROR, LABELS, POLICY_GROUPS } from "./aiAssistUsagePoliciesSettings";
import { buildPolicyItems, replacePolicy, formatErrorMessage } from "./aiAssistUsagePoliciesHelper";

// The AI Usage Policies tab. It lists the policies, shows the chosen one in the form.
export default class AiAssistUsagePolicies extends LightningElement {

  // Values the template reads
  labels = LABELS;
  groups = POLICY_GROUPS;

  // State of the tab
  policies = [];
  selectedKey = null;
  isBusy = true;
  isSaving = false;
  errorMessage = NO_TEXT;
  formVersion = 0;

  // Lifecycle methods
  connectedCallback() {

    // [1] Load the policies when the tab opens
    this.loadPolicies();
  }

  // The policies turned into list items.
  get policyItems() {

    // [1] Hand the work to the helper
    const policyItems = buildPolicyItems(this.policies, this.selectedKey, this.isNewPolicy);

    return policyItems;
  }

  get hasPolicyItems() {

    // [1] The list has at least one item
    const hasPolicyItems = this.policyItems.length > 0;

    return hasPolicyItems;
  }

  get showNoPolicies() {

    // [1] Say so when the load is done and nothing is listed
    const showNoPolicies = !this.isBusy && !this.hasPolicyItems;

    return showNoPolicies;
  }

  get isNewPolicy() {

    // [1] The new policy has its own key
    const isNewPolicy = this.selectedKey === NEW_POLICY_KEY;

    return isNewPolicy;
  }

  get selectedPolicy() {

    // [1] Find the saved policy the admin picked
    const selectedPolicy = this.policies.find((policy) => policy.policyId === this.selectedKey);

    return selectedPolicy;
  }

  get hasSelection() {

    // [1] Something is picked when it is the new policy or a saved one
    const hasSelectedPolicy = Boolean(this.selectedPolicy);

    return this.isNewPolicy || hasSelectedPolicy;
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

  get formValues() {

    // [1] The new policy starts from the default values
    if (this.isNewPolicy) return { ...NEW_POLICY_VALUES };

    // [2] A saved policy fills the form with its values and its name
    const policy = this.selectedPolicy;
    const formValues = policy ? { ...policy.values, [FIELD_NAME]: policy.name } : {};

    return formValues;
  }

  // One item, so the form is built again whenever the policy or the saved values change.
  get formKeyItems() {

    // [1] The key changes with the chosen policy and the saved version
    const key = this.selectedKey + FORM_KEY_SEPARATOR + this.formVersion;

    return [{ key }];
  }

  get canDelete() {

    // [1] Only a saved policy can be deleted
    const canDelete = Boolean(this.selectedPolicy);

    return canDelete;
  }

  // Event handlers
  handlePolicySelect(event) {

    // [1] Show the policy the admin picked
    this.selectedKey = event.currentTarget.dataset.key;
    this.errorMessage = NO_TEXT;
    this.formVersion = this.formVersion + 1;
  }

  handleNewPolicy() {

    // [1] Show an empty form that is saved as a new policy
    this.selectedKey = NEW_POLICY_KEY;
    this.errorMessage = NO_TEXT;
    this.formVersion = this.formVersion + 1;
  }

  async handleSave(event) {

    // [1] Save the values, creating the policy when it is new
    this.isSaving = true;
    this.errorMessage = NO_TEXT;

    try {

      const policyId = this.isNewPolicy ? null : this.selectedKey;
      const values = event.detail.values;
      const savedPolicy = await savePolicy({ policyId, values });

      // [2] Show the saved policy, which may now be the chosen one
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

  async handleDeletePolicy() {

    // [1] Ask first, because the assignments go with the policy
    const confirmOptions = { message: LABELS.deleteMessage, label: LABELS.deleteTitle, variant: CONFIRM_VARIANT };
    const isConfirmed = await LightningConfirm.open(confirmOptions);
    if (!isConfirmed) return;

    this.isBusy = true;

    try {

      // [2] Delete the policy and take it out of the list
      const deletedKey = this.selectedKey;
      await deletePolicy({ policyId: deletedKey });
      this.policies = this.policies.filter((policy) => policy.policyId !== deletedKey);
      this.selectedKey = null;
      this.showToast(LABELS.deleted, TOAST_VARIANT_SUCCESS);

    } catch (error) {

      // [3] Show the reason
      const message = formatErrorMessage(error);
      this.showToast(message, TOAST_VARIANT_ERROR);

    } finally {

      this.isBusy = false;
    }
  }

  // Private methods
  async loadPolicies() {

    try {

      // [1] Read every policy with its assignments
      this.policies = await getPolicies();

    } catch (error) {

      // [2] Show the reason
      const message = formatErrorMessage(error);
      this.showToast(message, TOAST_VARIANT_ERROR);

    } finally {

      this.isBusy = false;
    }
  }

  showToast(message, variant) {

    // [1] Show the message at the top of the page
    const toastEvent = new ShowToastEvent({ message, variant });
    this.dispatchEvent(toastEvent);
  }
}
