/*
Component Name: aiChatMessage

=================================================================
=================================================================

Description: One item in the conversation: a user bubble, an AI reply with its toolbar, or a centred notice.

Step 1: Show the message the parent passes in
Step 2: Let the user copy, rate, regenerate and save an AI reply to its record
Step 3: Show feedback, suggested action and debug trace when the message asks for them
Step 4: Report everything it cannot do alone to aiAssistChat as one bubbling "messageaction" event

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, FEEDBACK_RATING, ACTION, EVENT_MESSAGE_ACTION, CLASS_USER_BUBBLE, CLASS_USER_BUBBLE_SENDING, CLASS_TOOL, CLASS_TOOL_HELPFUL, CLASS_TOOL_NOT_HELPFUL, ARIA_PRESSED_TRUE, ARIA_PRESSED_FALSE, FILL_SELECTED, FILL_UNSELECTED, SAVE_OPTIONS, ARIA_EXPANDED_TRUE, ARIA_EXPANDED_FALSE, KEY_ESCAPE, SAVE_WRAP_SELECTOR } from "./aiChatMessageSettings";
import { copyToClipboard, getCopyLabel, getCopyIcon } from "./aiChatMessageHelper";

// One item in the conversation - a user bubble (sent or sending), an AI reply with its toolbar, feedback, suggested action and debug trace, or a centred notice.
export default class AiChatMessage extends LightningElement {

  // Values passed in by the parent component
  @api message; // The message view built by aiAssistChat: { id, isUser, isNotice, displayText, isHelpful, isNotHelpful, ... }

  // Values the template reads
  labels = LABELS;

  // Tracked state
  isCopied = false; // true right after the user copies the reply
  isSaveMenuOpen = false; // true while the Save to record menu is open

  // The class for the user bubble: dimmed while the message is still sending.
  get userBubbleClass() {

    // [1] Pick the class for the current state
    const isSending = this.message.isSending;
    const bubbleClass = isSending ? CLASS_USER_BUBBLE_SENDING : CLASS_USER_BUBBLE;

    return bubbleClass;
  }

  // The class for the thumbs up button: highlighted when the user rated the reply helpful.
  get helpfulClass() {

    // [1] Pick the class for the current state
    const isHelpful = this.message.isHelpful;
    const buttonClass = isHelpful ? CLASS_TOOL_HELPFUL : CLASS_TOOL;

    return buttonClass;
  }

  // The class for the thumbs down button: highlighted when the user rated the reply not helpful.
  get notHelpfulClass() {

    // [1] Pick the class for the current state
    const isNotHelpful = this.message.isNotHelpful;
    const buttonClass = isNotHelpful ? CLASS_TOOL_NOT_HELPFUL : CLASS_TOOL;

    return buttonClass;
  }

  // The aria-pressed value for the thumbs up button.
  get helpfulPressed() {

    // [1] aria-pressed needs the text "true" or "false"
    const isHelpful = this.message.isHelpful;
    const pressed = isHelpful ? ARIA_PRESSED_TRUE : ARIA_PRESSED_FALSE;

    return pressed;
  }

  // The aria-pressed value for the thumbs down button.
  get notHelpfulPressed() {

    // [1] aria-pressed needs the text "true" or "false"
    const isNotHelpful = this.message.isNotHelpful;
    const pressed = isNotHelpful ? ARIA_PRESSED_TRUE : ARIA_PRESSED_FALSE;

    return pressed;
  }

  // The fill for the thumbs up icon: solid when selected.
  get helpfulFill() {

    // [1] Pick the fill for the current state
    const isHelpful = this.message.isHelpful;
    const fill = isHelpful ? FILL_SELECTED : FILL_UNSELECTED;

    return fill;
  }

  // The fill for the thumbs down icon: solid when selected.
  get notHelpfulFill() {

    // [1] Pick the fill for the current state
    const isNotHelpful = this.message.isNotHelpful;
    const fill = isNotHelpful ? FILL_SELECTED : FILL_UNSELECTED;

    return fill;
  }

  // The copy button label.
  get copyLabel() {

    // [1] Hand the work to the helper
    return getCopyLabel(this.isCopied);
  }

  // The copy button icon.
  get copyIcon() {

    // [1] Hand the work to the helper
    return getCopyIcon(this.isCopied);
  }

  // The places the reply can be saved to, one row each in the Save to record menu.
  get saveOptions() {

    // [1] The rows are the same for every reply
    return SAVE_OPTIONS;
  }

  // The aria-expanded value for the Save to record button.
  get saveMenuExpanded() {

    // [1] aria-expanded needs the text "true" or "false"
    const expanded = this.isSaveMenuOpen ? ARIA_EXPANDED_TRUE : ARIA_EXPANDED_FALSE;

    return expanded;
  }

  // Copies the reply text and remembers whether it worked.
  async handleCopy() {

    // [1] Copy the text and keep the result
    this.isCopied = await copyToClipboard(this.message.displayText);
  }

  // Tells aiAssistChat the user rated the reply helpful.
  handleHelpful() {

    // [1] Send the rating
    this.sendMessageAction(ACTION.RATE, { rating: FEEDBACK_RATING.HELPFUL });
  }

  // Tells aiAssistChat the user rated the reply not helpful.
  handleNotHelpful() {

    // [1] Send the rating
    this.sendMessageAction(ACTION.RATE, { rating: FEEDBACK_RATING.NOT_HELPFUL });
  }

  // Tells aiAssistChat the user sent the feedback panel.
  handleFeedbackSubmit(event) {

    // [1] Read the reason and comment from the panel
    const reason = event.detail.reason;
    const comment = event.detail.comment;

    // [2] Send them on
    this.sendMessageAction(ACTION.SUBMIT_FEEDBACK, { reason, comment });
  }

  // Tells aiAssistChat the user closed the feedback panel.
  handleFeedbackSkip() {

    // [1] Send the close
    this.sendMessageAction(ACTION.CLOSE_FEEDBACK);
  }

  // Tells aiAssistChat the user wants the reply written again.
  handleRegenerate() {

    // [1] Send the request
    this.sendMessageAction(ACTION.REGENERATE);
  }

  // Tells aiAssistChat the user ran the suggested action.
  handleRunAction(event) {

    // [1] Read the inputs from the action card
    const inputs = event.detail.inputs;

    // [2] Send them on
    this.sendMessageAction(ACTION.RUN_ACTION, { inputs });
  }

  // Tells aiAssistChat the user dismissed the suggested action.
  handleDismissAction() {

    // [1] Send the dismissal
    this.sendMessageAction(ACTION.DISMISS_ACTION);
  }

  // Tells aiAssistChat the user declined the suggested action.
  handleDeclineAction() {

    // [1] Send the decline
    this.sendMessageAction(ACTION.DECLINE_ACTION);
  }

  // Tells aiAssistChat the user wants to see the request trace.
  handleLoadTrace() {

    // [1] Send the request
    this.sendMessageAction(ACTION.LOAD_TRACE);
  }

  // Tells aiAssistChat the user closed the request trace.
  handleCloseTrace() {

    // [1] Send the close
    this.sendMessageAction(ACTION.CLOSE_TRACE);
  }

  // Opens or closes the Save to record menu.
  handleToggleSaveMenu() {

    // [1] Flip it
    this.isSaveMenuOpen = !this.isSaveMenuOpen;
  }

  // Stops a press on the menu from taking focus off the button, which would close the menu before the click lands (Safari does not focus buttons on click).
  handleSaveMenuMouseDown(event) {

    // [1] Keep focus where it is
    event.preventDefault();
  }

  // Closes the Save to record menu once focus leaves it entirely.
  handleSaveMenuFocusOut(event) {

    // [1] Stay open while focus moves inside the menu and its button
    const wrapper = this.template.querySelector(SAVE_WRAP_SELECTOR);
    const isFocusInside = !!(wrapper && event.relatedTarget && wrapper.contains(event.relatedTarget));

    if (isFocusInside) return;

    // [2] Close it
    this.isSaveMenuOpen = false;
  }

  // Closes the Save to record menu when the user presses Escape.
  handleSaveMenuKeyDown(event) {

    // [1] Close on Escape only
    if (event.key === KEY_ESCAPE) this.isSaveMenuOpen = false;
  }

  // Tells aiAssistChat where the user chose to save the reply, then closes the menu.
  handleSaveTarget(event) {

    // [1] Read the row they chose
    const target = event.currentTarget.dataset.target;

    // [2] Close the menu and send the choice
    this.isSaveMenuOpen = false;
    this.sendMessageAction(ACTION.SAVE_TO_RECORD, { target });
  }

  // Sends the one bubbling event aiAssistChat listens for, with the action, this message's id and any extra detail.
  sendMessageAction(action, extra = {}) {

    // [1] Build the event detail
    const messageId = this.message.id;
    const detail = { action, messageId, ...extra };

    // [2] Send it up through the page
    const messageActionEvent = new CustomEvent(EVENT_MESSAGE_ACTION, { bubbles: true, composed: true, detail });
    this.dispatchEvent(messageActionEvent);
  }
}
