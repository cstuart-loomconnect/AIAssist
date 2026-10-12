/*
Component Name: aiChatMessageList

=================================================================
=================================================================

Description: The scrolling conversation: earlier messages, each message with its day separator, the working indicator and the failed-reply card.

Step 1: Show the messages the parent passes in
Step 2: Remember whether the user is reading near the newest message
Step 3: Let aiAssistChat scroll to the bottom and keep the same message in view when older ones load
Step 4: Show a Jump to latest button when the user is away from the newest message, and say when a new reply arrived there
Step 5: Tell the parent when the user asks for earlier messages or a retry

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, NEAR_BOTTOM_PX, SCROLL_SELECTOR, CLASS_SCROLL, CLASS_SCROLL_DIMMED, CLASS_JUMP, CLASS_JUMP_NEW, SCROLL_BEHAVIOR_SMOOTH, SCROLL_BEHAVIOR_INSTANT, REDUCED_MOTION_QUERY, EVENT_LOAD_EARLIER, EVENT_RETRY } from "./aiChatMessageListSettings";

// aiAssistChat drives the scroll position through the @api methods.
export default class AiChatMessageList extends LightningElement {

  // Values passed in by the parent component
  @api items = []; // [{ id, separatorLabel, ...message view }]
  @api hasMore = false; // true shows the "Show earlier messages" button
  @api isLoadingEarlier = false; // true turns that button off while older messages load
  @api working; // { mode, label, elapsedLabel, steps }. When empty, the working indicator is hidden.
  @api errorTurn; // { reference, debugDetail, isRetrying, retryError }. When empty, the error card is hidden.
  @api dimmed = false; // true fades the list, for example while another conversation loads

  // Values the template reads
  labels = LABELS;

  // Tracked state
  savedDistanceFromBottom = null; // Where the user was before older messages were added
  isNearBottom = true; // true while the user is reading the newest messages
  hasUnseenMessages = false; // true when a new message arrived while the user was reading older ones

  // The class for the scrolling area: faded when dimmed.
  get scrollClass() {

    // [1] Pick the class for the current state
    const scrollClass = this.dimmed ? CLASS_SCROLL_DIMMED : CLASS_SCROLL;

    return scrollClass;
  }

  // True when the Jump to latest button shows: the user has scrolled away from the newest message.
  get showJump() {

    // [1] The button is the opposite of reading near the bottom
    return !this.isNearBottom;
  }

  // The class for the Jump to latest button: stands out when a new reply arrived out of view.
  get jumpClass() {

    // [1] Pick the class for the current state
    const jumpClass = this.hasUnseenMessages ? CLASS_JUMP_NEW : CLASS_JUMP;

    return jumpClass;
  }

  // The text of the Jump to latest button: says when a new reply is waiting.
  get jumpLabel() {

    // [1] Pick the text for the current state
    const jumpLabel = this.hasUnseenMessages ? LABELS.newReply : LABELS.jumpToLatest;

    return jumpLabel;
  }

  // The scrolling area in the template.
  get scroller() {

    // [1] Find it
    return this.template.querySelector(SCROLL_SELECTOR);
  }

  // Jumps to the newest message. force = false only scrolls if the user was already near the bottom, so reading older messages isn't interrupted.
  @api
  scrollToBottom(force = true) {

    // [1] Find the scrolling area
    const scroller = this.scroller;

    // [2] Scroll when forced or when the user was already near the bottom
    const canScroll = scroller && (force || this.isNearBottom);

    if (canScroll) {
      scroller.scrollTop = scroller.scrollHeight;
      this.isNearBottom = true;
      this.hasUnseenMessages = false;
    } else if (scroller) {

      // [3] The user is reading older messages, so leave them there and say a new one arrived
      this.hasUnseenMessages = true;
    }
  }

  // Called before older messages are prepended, then restoreScrollPosition after they render - keeps the same message in view.
  @api
  captureScrollPosition() {

    // [1] Find the scrolling area
    const scroller = this.scroller;

    // [2] Remember how far from the bottom the user is
    this.savedDistanceFromBottom = scroller ? scroller.scrollHeight - scroller.scrollTop : null;
  }

  // Puts the user back at the same distance from the bottom after older messages render.
  @api
  restoreScrollPosition() {

    // [1] Find the scrolling area
    const scroller = this.scroller;

    // [2] Scroll back to the saved distance
    const hasSavedDistance = this.savedDistanceFromBottom !== null;

    if (scroller && hasSavedDistance) {
      scroller.scrollTop = scroller.scrollHeight - this.savedDistanceFromBottom;
    }

    // [3] Forget the saved distance
    this.savedDistanceFromBottom = null;
  }

  // Remembers whether the user is near the bottom each time they scroll.
  handleScroll() {

    // [1] Find the scrolling area
    const scroller = this.scroller;

    if (scroller) {

      // [2] Work out how far the user is from the bottom
      const distanceFromBottom = scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight;
      this.isNearBottom = distanceFromBottom < NEAR_BOTTOM_PX;

      // [3] Reaching the bottom means the new message has been seen
      if (this.isNearBottom) {
        this.hasUnseenMessages = false;
      }
    }
  }

  // Scrolls to the newest message when the user presses the Jump to latest button.
  handleJump() {

    // [1] Find the scrolling area
    const scroller = this.scroller;

    if (!scroller) return;

    // [2] Scroll at once when the user asked for less motion, smoothly otherwise
    const prefersReducedMotion = window.matchMedia(REDUCED_MOTION_QUERY).matches;
    const behavior = prefersReducedMotion ? SCROLL_BEHAVIOR_INSTANT : SCROLL_BEHAVIOR_SMOOTH;

    // [3] Go to the newest message
    scroller.scrollTo({ top: scroller.scrollHeight, behavior });
    this.hasUnseenMessages = false;
  }

  // Tells the parent the user wants earlier messages.
  handleLoadEarlier() {

    // [1] Send the request
    const loadEarlierEvent = new CustomEvent(EVENT_LOAD_EARLIER);
    this.dispatchEvent(loadEarlierEvent);
  }

  // Tells the parent the user wants to try again.
  handleRetry() {

    // [1] Send the request
    const retryEvent = new CustomEvent(EVENT_RETRY);
    this.dispatchEvent(retryEvent);
  }
}
