/*
Component Name: aiChatHeader

=================================================================
=================================================================

Description: The chat window's top bar: logo, title, agent picker, and the New and More controls (the More menu shows usage).

Step 1: The parent (aiAssistChat) passes in the title, the agents, the badge and the user's usage meters
Step 2: The header shows the logo, the title and, when there is more than one agent, a picker
Step 3: The New, End and More buttons follow; the More menu opens with the usage limits, then History and Export
Step 4: Every click is reported to the parent as an event; the header changes nothing itself

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, BADGE, MIN_AGENTS_TO_SWITCH, MENU_VALUE_END, ROW_KEY_HISTORY, ROW_KEY_USAGE, BUTTON_CLASS_MORE, BUTTON_CLASS_MORE_OPEN, LOGO_CLASS, LOGO_CLASS_MUTED, TITLE_CLASS, TITLE_CLASS_MUTED, ARIA_TRUE, ARIA_FALSE, KEY_ESCAPE, PICKER_SELECTOR, USAGE_BACK_SELECTOR, MENU_ROW_SELECTOR, EVENT_AGENT_SELECT, EVENT_NEW_CONVERSATION, EVENT_OPEN_HISTORY, EVENT_MENU_SELECT } from "./aiChatHeaderSettings";
import { getLogoStroke, getBadgeLabel, getBadgeClass, buildAgentOptions, hasEndItem, buildMenuRows } from "./aiChatHeaderHelper";

// The chat window's top bar. Purely presentational: every click is reported to aiAssistChat as an event.
export default class AiChatHeader extends LightningElement {

  // Values passed in by the parent component
  @api title = LABELS.appName; // The text beside the logo
  @api agentName; // The name of the agent in use
  @api agentId; // The Id of the agent in use
  @api agents = []; // [{ id, name, description }]: the agents the user can switch to
  @api showAgentLine = false; // True to show the agent under the title
  @api showNew = false; // True to show the New button
  @api newDisabled = false; // True to disable the New button
  @api showHistory = false; // True to show the History button
  @api menuItems = []; // [{ value, label, iconName }]: the items in the More menu
  @api badge; // 'debug' | 'maintenance' | 'off', or empty for no badge
  @api muted = false; // True to dim the logo and title when the window is off
  @api usageMeters = []; // [{ limitType, used, max }]: one for each of the three usage limits; max is empty when the policy sets no limit
  @api idleTimeoutMinutes; // Minutes without activity before a conversation stops counting as open; empty for never

  // Values the template reads
  labels = LABELS;

  // Tracked state
  isAgentMenuOpen = false;
  isMoreOpen = false;
  isEndConfirmOpen = false;
  focusAfterRender = null; // Selector of what to focus once the menu has swapped its contents
  isUsageOpen = false; // True when the More menu shows the usage limits in place of its rows

  // The classes of the logo, dimmed when the window is off.
  get logoClass() {

    return this.muted ? LOGO_CLASS_MUTED : LOGO_CLASS;
  }

  // The colour of the logo mark.
  get logoStroke() {

    return getLogoStroke(this.muted);
  }

  // The classes of the title, dimmed when the window is off.
  get titleClass() {

    return this.muted ? TITLE_CLASS_MUTED : TITLE_CLASS;
  }

  // True when there is more than one agent to switch between.
  get canSwitchAgent() {

    return Array.isArray(this.agents) && this.agents.length >= MIN_AGENTS_TO_SWITCH;
  }

  // The agents for the picker, with the one in use marked.
  get agentOptions() {

    return buildAgentOptions(this.agents, this.agentId);
  }

  // Tells a screen reader whether the agent menu is open.
  get agentMenuExpanded() {

    return this.isAgentMenuOpen ? ARIA_TRUE : ARIA_FALSE;
  }

  // The rows of the More menu: History, then Export when the user may export.
  get menuRows() {

    return buildMenuRows(this.menuItems, this.showHistory, this.hasUsage);
  }

  // True when the More menu has anything in it.
  get hasMenuRows() {

    return this.menuRows.length > 0;
  }

  // True when the user can end the conversation, so the End button shows.
  get showEnd() {

    return hasEndItem(this.menuItems);
  }

  // The classes of the More button, which is highlighted while its menu is open.
  get moreButtonClass() {

    return this.isMoreOpen ? BUTTON_CLASS_MORE_OPEN : BUTTON_CLASS_MORE;
  }

  // Tells a screen reader whether the More menu is open.
  get moreExpanded() {

    return this.isMoreOpen ? ARIA_TRUE : ARIA_FALSE;
  }

  // Tells a screen reader whether the End confirmation is open.
  get endExpanded() {

    return this.isEndConfirmOpen ? ARIA_TRUE : ARIA_FALSE;
  }

  // True when there are usage limits to show at the top of the More menu.
  get hasUsage() {

    return Array.isArray(this.usageMeters) && this.usageMeters.length > 0 && !this.muted;
  }

  // True when the More menu has anything in it: History, Usage or Export.
  get hasMenu() {

    return this.hasMenuRows;
  }

  // True when the menu shows its rows, false when it shows the usage limits.
  get showMenuRows() {

    return !this.isUsageOpen;
  }

  // The label of the New button, which says when it is disabled.
  get newLabel() {

    return this.newDisabled ? LABELS.newConversationDisabled : LABELS.newConversation;
  }

  // The text of the badge beside the title.
  get badgeLabel() {

    return getBadgeLabel(this.badge);
  }

  // The classes of the badge beside the title.
  get badgeClass() {

    return getBadgeClass(this.badge);
  }

  // True when the badge is the debug badge, which has an icon.
  get isDebugBadge() {

    return this.badge === BADGE.DEBUG;
  }

  // The user opened or closed the agent menu.
  handleToggleAgentMenu() {

    this.isAgentMenuOpen = !this.isAgentMenuOpen;
  }

  // Closes the agent menu once focus leaves the picker entirely.
  handlePickerFocusOut(event) {

    // [1] Stay open while focus moves inside the picker
    const picker = this.template.querySelector(PICKER_SELECTOR);
    const isFocusInside = !!(picker && event.relatedTarget && picker.contains(event.relatedTarget));

    if (isFocusInside) return;

    // [2] Close it
    this.isAgentMenuOpen = false;
  }

  // The user pressed a key in the agent picker.
  handlePickerKeyDown(event) {

    // [1] Close the menu on Escape only
    if (event.key === KEY_ESCAPE) this.isAgentMenuOpen = false;
  }

  // The user chose an agent.
  handleAgentSelect(event) {

    // [1] Read the agent they chose and close the menu
    const agentId = event.currentTarget.dataset.id;

    this.isAgentMenuOpen = false;

    // [2] Tell the parent only when it is a different agent
    if (agentId !== this.agentId) this.dispatchEvent(new CustomEvent(EVENT_AGENT_SELECT, { detail: { agentId } }));
  }

  // The user clicked the New button.
  handleNew() {

    this.dispatchEvent(new CustomEvent(EVENT_NEW_CONVERSATION));
  }

  // The user opened or closed the More menu.
  handleToggleMore() {

    this.isEndConfirmOpen = false;
    this.isUsageOpen = false;
    this.isMoreOpen = !this.isMoreOpen;
  }

  // The user clicked End, which asks them to confirm before the conversation ends.
  handleToggleEndConfirm() {

    this.isMoreOpen = false;
    this.isEndConfirmOpen = !this.isEndConfirmOpen;
  }

  // The user chose to keep the conversation open.
  handleKeepOpen() {

    this.isEndConfirmOpen = false;
  }

  // The user confirmed that the conversation should end.
  handleConfirmEnd() {

    // [1] Close the confirmation and tell the parent, the same way a menu item is chosen
    this.isEndConfirmOpen = false;

    this.dispatchEvent(new CustomEvent(EVENT_MENU_SELECT, { detail: { value: MENU_VALUE_END } }));
  }

  // The user chose a row in the More menu.
  handleMenuRowSelect(event) {

    // [1] Close the menu and read the row they chose
    const value = event.currentTarget.dataset.value;

    this.isMoreOpen = false;

    // [2] Usage opens in the menu itself, so it stays open; History has its own event; any other row is a menu item the parent handles
    if (value === ROW_KEY_USAGE) {

      this.isMoreOpen = true;
      this.isUsageOpen = true;
      this.focusAfterRender = USAGE_BACK_SELECTOR;
    } else if (value === ROW_KEY_HISTORY) this.dispatchEvent(new CustomEvent(EVENT_OPEN_HISTORY));
    else this.dispatchEvent(new CustomEvent(EVENT_MENU_SELECT, { detail: { value } }));
  }

  // The user went back from the usage limits to the menu rows.
  handleUsageBack() {

    this.isUsageOpen = false;
    this.focusAfterRender = MENU_ROW_SELECTOR;
  }

  // Puts focus back inside the menu once a swap has drawn, so the button that was clicked and removed does not make the menu think focus left it.
  renderedCallback() {

    if (!this.focusAfterRender) return;

    const target = this.template.querySelector(this.focusAfterRender);

    this.focusAfterRender = null;

    if (target) target.focus();
  }

  // Closes the More menu or the End confirmation once focus leaves it entirely.
  handlePopoverFocusOut(event) {

    // [1] Stay open while focus moves inside it, or while the menu swaps its contents and the clicked button is removed
    if (this.focusAfterRender) return;

    const isFocusInside = !!(event.relatedTarget && event.currentTarget.contains(event.relatedTarget));

    if (isFocusInside) return;

    // [2] Close both
    this.isMoreOpen = false;
    this.isEndConfirmOpen = false;
  }

  // The user pressed a key in the More menu or the End confirmation.
  handlePopoverKeyDown(event) {

    // [1] Close on Escape only
    if (event.key !== KEY_ESCAPE) return;

    this.isMoreOpen = false;
    this.isEndConfirmOpen = false;
  }
}
