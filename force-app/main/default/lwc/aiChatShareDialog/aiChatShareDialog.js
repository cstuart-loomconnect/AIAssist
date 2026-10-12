/*
Component Name: aiChatShareDialog

=================================================================
=================================================================

Description: The dialog for sharing a conversation, read-only, with individual users: a search box, the people who already have access and a way to remove them.

Step 1: Show the people the conversation is shared with
Step 2: Let the user search for a person, waiting until they stop typing, and tell the parent what was typed
Step 3: Tell the parent which person the user chose to share with or to remove
Step 4: Tell the parent when the user closes the dialog, or presses Escape

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, MIN_SEARCH_LENGTH, SEARCH_DELAY_MS, KEY_ESCAPE, EVENT_SEARCH, EVENT_SHARE, EVENT_UNSHARE, EVENT_CLOSE } from "./aiChatShareDialogSettings";
import { buildRecipientViews, buildResultViews } from "./aiChatShareDialogHelper";

// aiAssistChat opens this dialog from the header menu and makes every Apex call itself: it loads the people, runs each search, shares and removes.
export default class AiChatShareDialog extends LightningElement {

  // Values passed in by the parent component
  @api recipients = []; // [{ userId, name, subtitle }] The people the conversation is shared with
  @api results = []; // [{ userId, name, subtitle }] The people the last search found
  @api isLoading = false; // true while the people with access are loading
  @api isSearching = false; // true while a search is running
  @api isBusy = false; // true turns the buttons off while a share or a removal is running
  @api errorMessage; // The reason the last step failed. When empty, nothing is shown.

  // Values the template reads
  labels = LABELS;

  // Tracked state
  searchText = ""; // What the user has typed
  searchedText = ""; // The text the last search was sent for
  searchTimer; // Waits for the user to stop typing before searching

  // Stops a search that has not been sent yet.
  disconnectedCallback() {

    // [1] Clear the timer
    clearTimeout(this.searchTimer);
  }

  // The people with access, as rows.
  get recipientViews() {

    // [1] Hand the work to the helper
    return buildRecipientViews(this.recipients);
  }

  // The search results, as rows.
  get resultViews() {

    // [1] Hand the work to the helper
    return buildResultViews(this.results);
  }

  // True when the conversation is shared with anyone.
  get hasRecipients() {

    return this.recipientViews.length > 0;
  }

  // True when the search found anyone.
  get hasResults() {

    return this.resultViews.length > 0;
  }

  // True when the user has typed something but not enough to search.
  get showSearchMore() {

    // [1] Something typed, but too short
    const typedLength = this.searchText.trim().length;

    return typedLength > 0 && typedLength < MIN_SEARCH_LENGTH;
  }

  // True when the search for what the user typed finished and found no one.
  get showNoResults() {

    // [1] The search must be for the text now in the box, and have finished
    const isSearchCurrent = this.searchedText === this.searchText.trim() && this.searchedText.length >= MIN_SEARCH_LENGTH;

    return isSearchCurrent && !this.isSearching && !this.hasResults;
  }

  // Waits until the user stops typing, then tells the parent what to search for.
  handleSearchInput(event) {

    // [1] Remember what was typed and restart the wait
    this.searchText = event.target.value;
    clearTimeout(this.searchTimer);

    // [2] Search after a short pause. A timer is the only way to wait for the user to stop typing.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = setTimeout(() => this.sendSearch(), SEARCH_DELAY_MS);
  }

  // Tells the parent which person the user chose to share with.
  handleShare(event) {

    // [1] Read the person from the button that was clicked
    const userId = event.currentTarget.dataset.userid;

    // [2] Send the choice
    const shareEvent = new CustomEvent(EVENT_SHARE, { detail: { userId } });
    this.dispatchEvent(shareEvent);
  }

  // Tells the parent which person the user chose to remove.
  handleUnshare(event) {

    // [1] Read the person from the button that was clicked
    const userId = event.currentTarget.dataset.userid;

    // [2] Send the choice
    const unshareEvent = new CustomEvent(EVENT_UNSHARE, { detail: { userId } });
    this.dispatchEvent(unshareEvent);
  }

  // Tells the parent the user is done.
  handleClose() {

    // [1] Send the close event
    const closeEvent = new CustomEvent(EVENT_CLOSE);
    this.dispatchEvent(closeEvent);
  }

  // Closes when the user presses Escape.
  handleKeyDown(event) {

    // [1] Close on Escape only
    if (event.key === KEY_ESCAPE) this.handleClose();
  }

  // Tells the parent what to search for.
  sendSearch() {

    // [1] Keep the text the search is sent for, so a late answer can be matched to it
    const text = this.searchText.trim();
    this.searchedText = text;

    // [2] Send it
    const searchEvent = new CustomEvent(EVENT_SEARCH, { detail: { text } });
    this.dispatchEvent(searchEvent);
  }
}
