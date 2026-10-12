/*
Component Name: aiChatComposer

=================================================================
=================================================================

Description: The message box at the bottom of the chat: typing, the slash-command menu, Send and Stop, and the footnote with today's token usage.

Step 1: The parent (aiAssistChat) passes in the commands, the usage meters and whether the box is disabled or working
Step 2: The user types; a command being typed opens the slash-command menu
Step 3: Enter sends the message (Shift+Enter adds a line); while the menu is open the arrow keys move and Enter or Tab picks
Step 4: The footnote shows how much of today's token allowance is used, and the parent hears about every send, stop and menu change

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, DEFAULT_MAX_LENGTH, KEY, STEP_DOWN, STEP_UP, ARIA_TRUE, ARIA_FALSE, BOX_CLASS, BOX_CLASS_DISABLED, BOX_CLASS_FOCUSED, SLASH_CLASS, SLASH_CLASS_ACTIVE, SEND_CLASS, SEND_CLASS_DISABLED, INPUT_SELECTOR, COMMAND_PREFIX, TOKEN_CLASS_PREFIX, EVENT_SEND, EVENT_STOP, EVENT_MENU_TOGGLE } from "./aiChatComposerSettings";
import { buildCommandMatches, buildMatchViews, isTypingCommand, buildOptionId, getSteppedIndex, findTokenPercent, getTokenTone, buildTokenDash } from "./aiChatComposerHelper";

// The message box. Enter sends, Shift+Enter adds a line; while the command menu is open the arrow keys move and Enter or Tab picks.
export default class AiChatComposer extends LightningElement {

  // Values passed in by the parent component
  @api commands = []; // [{ id, command, description, scope }]: the slash commands the user can pick
  @api disabled = false; // True to stop the user typing or sending
  @api isWorking = false; // True while the agent is answering, which swaps Send for Stop
  @api placeholder = LABELS.composerPlaceholder; // The hint shown in the empty box
  @api footerText = LABELS.disclaimer; // The note at the left of the footnote
  @api usageMeters = []; // [{ limitType, used, max }]: the user's usage limits; only the token one shows here
  @api errorText; // A message shown under the box; empty for none
  @api maxLength = DEFAULT_MAX_LENGTH; // The most characters the box accepts

  // Values the template reads
  labels = LABELS;

  // Tracked state
  text = "";
  activeIndex = 0;
  isMenuDismissed = false;

  // The parent puts text in the box (Edit message, a suggested command) and the box takes focus.
  @api
  setText(value) {

    // [1] Keep the text and reset the menu
    this.text = value || "";
    this.isMenuDismissed = false;
    this.activeIndex = 0;

    // [2] Show it in the box, focus it and put the cursor at the end
    const input = this.input;

    if (input) {

      input.value = this.text;
      input.focus();
      input.setSelectionRange(this.text.length, this.text.length);
    }

    // [3] Tell the parent whether the menu is open
    this.notifyMenu();
  }

  // The parent empties the box.
  @api
  clear() {

    this.setText("");
  }

  // The parent puts the cursor in the box.
  @api
  focus() {

    if (this.input) this.input.focus();
  }

  // The text box in the template.
  get input() {

    return this.template.querySelector(INPUT_SELECTOR);
  }

  // How full today's token allowance is, or null when the policy sets none.
  get tokenPercent() {

    return findTokenPercent(this.usageMeters);
  }

  // True when there is a token percentage to show.
  get hasTokenUsage() {

    return this.tokenPercent !== null;
  }

  // The words beside the ring, such as "50% of today's allowance used".
  get tokenLabel() {

    return `${this.tokenPercent}${LABELS.tokenUsed}`;
  }

  // The hint when the mouse is over the token readout.
  get tokenTitle() {

    return LABELS.tokenTitle;
  }

  // The classes of the token readout, which carry its colour.
  get tokenClass() {

    const tone = getTokenTone(this.tokenPercent);

    return `${TOKEN_CLASS_PREFIX}${tone}`;
  }

  // How much of the token ring is filled.
  get tokenDash() {

    return buildTokenDash(this.tokenPercent);
  }

  // True when the parent offered any commands.
  get hasCommands() {

    return Array.isArray(this.commands) && this.commands.length > 0;
  }

  // The commands that match what the user has typed.
  get matches() {

    return buildCommandMatches(this.commands, this.text);
  }

  // True when at least one command matches.
  get hasMatches() {

    return this.matches.length > 0;
  }

  // True while the command menu shows: commands exist, the user is typing one and the box is usable.
  get isMenuOpen() {

    // [1] The menu needs commands, a box that is on and a command being typed
    const isTyping = isTypingCommand(this.text);

    return this.hasCommands && !this.isMenuDismissed && !this.isInputDisabled && isTyping;
  }

  // Tells a screen reader whether the command menu is open.
  get menuExpanded() {

    return this.isMenuOpen ? ARIA_TRUE : ARIA_FALSE;
  }

  // The matching commands, with the highlighted one marked.
  get matchViews() {

    return buildMatchViews(this.matches, this.activeIndex);
  }

  // The id of the highlighted menu row, for a screen reader. LWC scopes dynamic ids and the aria idrefs that point at them the same way, so the plain id matches.
  get activeOptionId() {

    // [1] Only an open menu with matches has a highlighted row
    const hasActiveOption = this.isMenuOpen && this.hasMatches;

    return hasActiveOption ? buildOptionId(this.activeIndex) : null;
  }

  // True when the user cannot type: the box is off, or the agent is answering.
  get isInputDisabled() {

    return this.disabled || this.isWorking;
  }

  // True when Send cannot be pressed: the box is unusable or empty.
  get isSendDisabled() {

    return this.isInputDisabled || !this.text.trim();
  }

  // The hint in the empty box, which changes while the agent is answering.
  get effectivePlaceholder() {

    return this.isWorking ? LABELS.composerPlaceholderWorking : this.placeholder;
  }

  // The classes of the box: greyed when off, outlined while the menu is open.
  get boxClass() {

    // [1] Off or working
    if (this.isWorking || this.disabled) return BOX_CLASS_DISABLED;

    // [2] Menu open, otherwise plain
    return this.isMenuOpen ? BOX_CLASS_FOCUSED : BOX_CLASS;
  }

  // The classes of the slash button, highlighted while the menu is open.
  get slashClass() {

    return this.isMenuOpen ? SLASH_CLASS_ACTIVE : SLASH_CLASS;
  }

  // The classes of the Send button, greyed when it cannot be pressed.
  get sendClass() {

    return this.isSendDisabled ? SEND_CLASS_DISABLED : SEND_CLASS;
  }

  // The user typed in the box.
  handleInput(event) {

    // [1] Keep what they typed and reset the menu
    this.text = event.target.value;
    this.isMenuDismissed = false;
    this.activeIndex = 0;

    // [2] Tell the parent whether the menu is open
    this.notifyMenu();
  }

  // The user pressed a key in the box.
  handleKeyDown(event) {

    // [1] While the menu is open, the arrow keys, Enter and Tab work on it
    const isMenuUsable = this.isMenuOpen && this.hasMatches;

    if (isMenuUsable && this.handleMenuKey(event)) return;

    // [2] Escape closes the menu
    if (this.isMenuOpen && event.key === KEY.ESCAPE) {

      event.preventDefault();
      this.isMenuDismissed = true;
      this.notifyMenu();
      return;
    }

    // [3] Enter sends; Shift+Enter adds a line, and Enter while composing text for another script is left alone
    const isSendKey = event.key === KEY.ENTER && !event.shiftKey && !event.isComposing;

    if (!isSendKey) return;

    event.preventDefault();
    this.send();
  }

  // The box lost focus, so the menu closes.
  handleBlur() {

    this.isMenuDismissed = true;
    this.notifyMenu();
  }

  // Keeps focus in the text box while the user clicks inside the menu.
  preventBlur(event) {

    event.preventDefault();
  }

  // The user clicked a command in the menu.
  handleCommandClick(event) {

    const index = Number(event.currentTarget.dataset.index);

    this.pickCommand(this.matches[index]);
  }

  // The mouse is over a command in the menu.
  handleCommandHover(event) {

    this.activeIndex = Number(event.currentTarget.dataset.index);
  }

  // The user clicked the slash button, which starts a command.
  handleSlash() {

    // [1] Put a slash in front of what is there, unless it already starts with one
    const hasText = !!this.text;
    const needsSlash = hasText && !this.text.startsWith(COMMAND_PREFIX);

    if (needsSlash) this.setText(`${COMMAND_PREFIX}${this.text}`);
    else this.setText(this.text || COMMAND_PREFIX);
  }

  // The user clicked Send.
  handleSendClick() {

    this.send();
  }

  // The user clicked Stop.
  handleStop() {

    this.dispatchEvent(new CustomEvent(EVENT_STOP));
  }

  // Handles a key that works on the open menu. Returns true when the key was used.
  handleMenuKey(event) {

    // [1] Down and up move the highlighted row
    if (event.key === KEY.ARROW_DOWN || event.key === KEY.ARROW_UP) {

      const step = event.key === KEY.ARROW_DOWN ? STEP_DOWN : STEP_UP;

      event.preventDefault();
      this.activeIndex = getSteppedIndex(this.activeIndex, step, this.matches.length);
      return true;
    }

    // [2] Enter or Tab picks the highlighted command; Shift+Enter is left for a new line
    const isEnterPick = event.key === KEY.ENTER && !event.shiftKey;

    if (isEnterPick || event.key === KEY.TAB) {

      event.preventDefault();
      this.pickCommand(this.matches[this.activeIndex]);
      return true;
    }

    return false;
  }

  // Puts the chosen command in the box, ready for the user to add to it.
  pickCommand(command) {

    if (command) this.setText(`${command.command} `);
  }

  // Tells the parent to send what is in the box.
  send() {

    // [1] Nothing to send from an empty or unusable box
    const text = this.text.trim();

    if (!text || this.isInputDisabled) return;

    // [2] Tell the parent
    this.dispatchEvent(new CustomEvent(EVENT_SEND, { detail: { text } }));
  }

  // Tells the parent whether the command menu is open.
  notifyMenu() {

    this.dispatchEvent(new CustomEvent(EVENT_MENU_TOGGLE, { detail: { open: this.isMenuOpen } }));
  }
}
