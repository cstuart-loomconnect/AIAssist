/*
Component Name: aiAssistSettings

=================================================================
=================================================================

Description: The AI Assist Settings tab: change AI Assist Settings and AI Assist UI Settings, and manage AI Usage Policies.

Step 1: Load every row of both settings from Apex
Step 2: Show one tab for AI Assist Settings, one for AI Assist UI Settings and one for AI Usage Policies
Step 3: Hand each of the two settings tabs to a panel, and show the usage policies in their own component
Step 4: Load the rows again whenever a panel saves or deletes one

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement } from "lwc";
import getSettingsPage from "@salesforce/apex/AIAssistSettingsController.getSettingsPage";
import { SETTINGS_NAME_ASSIST, SETTINGS_NAME_UI, TAB_ASSIST, TAB_UI, TAB_POLICY, ASSIST_GROUPS, UI_GROUPS, LABELS, NO_ERROR } from "./aiAssistSettingsSettings";
import { formatErrorMessage } from "./aiAssistSettingsHelper";

// The Settings tab. It loads both settings, shows one panel for each, and reloads when a panel saves or deletes a row.
export default class AiAssistSettings extends LightningElement {

  // Values the template reads
  labels = LABELS;
  assistSettingsName = SETTINGS_NAME_ASSIST;
  uiSettingsName = SETTINGS_NAME_UI;
  assistGroups = ASSIST_GROUPS;
  uiGroups = UI_GROUPS;
  assistTabValue = TAB_ASSIST;
  uiTabValue = TAB_UI;
  policyTabValue = TAB_POLICY;

  // State of the tab
  assistRows = [];
  uiRows = [];
  isFirstLoad = true;
  errorMessage = NO_ERROR;

  // Lifecycle methods
  connectedCallback() {

    // [1] Load the rows when the tab opens
    this.loadPage();
  }

  // Whether the last load failed.
  get hasError() {

    // [1] A message means the load failed
    const hasMessage = Boolean(this.errorMessage);

    return hasMessage;
  }

  // Whether the tabs should show: after the first load, and only when it worked.
  get showTabs() {

    // [1] Wait for the first load, and hide the tabs when it failed
    const isLoaded = !this.isFirstLoad;
    const isWorking = !this.hasError;

    return isLoaded && isWorking;
  }

  // Event handlers
  handleRefresh() {

    // [1] A panel saved or deleted a row, so load everything again
    this.loadPage();
  }

  // Private methods
  async loadPage() {

    try {

      // [1] Read every row of both settings
      const page = await getSettingsPage();
      this.assistRows = page.assistRows;
      this.uiRows = page.uiRows;
      this.errorMessage = NO_ERROR;

    } catch (error) {

      // [2] Show why the settings could not be read, such as a missing permission
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isFirstLoad = false;
    }
  }
}
