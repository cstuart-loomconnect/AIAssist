/*
Component Name: aiChatHistory

=================================================================
=================================================================

Description: Lists the user's past conversations, grouped by day, so they can search them, filter them and open one.

Step 1: The parent (aiAssistChat) loads the conversations and passes them in with the filter that is selected
Step 2: The component groups them under Today, Yesterday, Earlier this week and Older
Step 3: The user can search by title or agent here, and switch the filter, which the parent reloads
Step 4: Opening a conversation, going back and starting a new one are reported to the parent as events

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, HISTORY_FILTER_RECORD, HISTORY_FILTER_ALL, HISTORY_FILTER_SHARED, ARIA_TRUE, ARIA_FALSE, EVENT_FILTER_CHANGE, EVENT_OPEN, EVENT_BACK, EVENT_NEW_CONVERSATION } from "./aiChatHistorySettings";
import { buildFilteredConversations, buildGroupViews } from "./aiChatHistoryHelper";

// The user's past conversations, grouped by day, searchable by title, filtered to this record, all records, or the conversations other people started that this user may read (read-only). aiAssistChat loads the list (AIChatController.getConversationHistory) whenever the filter changes; search runs here over what is loaded.
export default class AiChatHistory extends LightningElement {

  // Values passed in by the parent component
  @api conversations = []; // [{ id, title, agentName, ownerName, status, closeReason, messageCount, lastActivity }]
  @api isLoading = false; // True while the list is being loaded
  @api errorMessage; // Text to show instead of the list when it could not be loaded
  @api filter = HISTORY_FILTER_RECORD; // 'record' | 'all' | 'shared'
  @api hasRecord = false; // True when the window is on a record, so "This record" is offered
  @api hasShared = false; // True when conversations are shared with the user, so "Shared with me" is offered
  @api currentConversationId; // The Id of the conversation that is open in the chat, which is highlighted
  @api newDisabled = false; // True to disable the New button

  // Values the template reads
  labels = LABELS;

  // Tracked state
  searchTerm = "";

  // Tells a screen reader whether the This record filter is pressed.
  get thisRecordPressed() {

    return this.filter === HISTORY_FILTER_RECORD ? ARIA_TRUE : ARIA_FALSE;
  }

  // Tells a screen reader whether the All records filter is pressed.
  get allRecordsPressed() {

    return this.filter === HISTORY_FILTER_ALL ? ARIA_TRUE : ARIA_FALSE;
  }

  // Tells a screen reader whether the Shared with me filter is pressed.
  get sharedPressed() {

    return this.filter === HISTORY_FILTER_SHARED ? ARIA_TRUE : ARIA_FALSE;
  }

  // True when there is more than one scope to choose from.
  get showScope() {

    return this.hasRecord || this.hasShared;
  }

  // The conversations that match what the user typed in the search.
  get filteredConversations() {

    // [1] Hand the work to the helper
    return buildFilteredConversations(this.conversations, this.searchTerm);
  }

  // The groups the template shows.
  get groups() {

    // [1] Hand the work to the helper
    return buildGroupViews(this.filteredConversations, this.currentConversationId);
  }

  // True when there is at least one conversation to show.
  get hasGroups() {

    return this.groups.length > 0;
  }

  // What to say when there is nothing to show.
  get emptyMessage() {

    // [1] A search with no matches
    if (this.searchTerm.trim()) return LABELS.noSearchResults;

    // [2] The shared list is empty, or the user has no conversations
    return this.filter === HISTORY_FILTER_SHARED ? LABELS.noSharedConversations : LABELS.noConversations;
  }

  // The user typed in the search box.
  handleSearch(event) {

    this.searchTerm = event.target.value || "";
  }

  // The user chose a different filter.
  handleFilter(event) {

    // [1] Read the filter they chose
    const filter = event.currentTarget.dataset.filter;

    // [2] Tell the parent only when it is a different filter
    if (filter !== this.filter) this.dispatchEvent(new CustomEvent(EVENT_FILTER_CHANGE, { detail: { filter } }));
  }

  // The user chose a conversation.
  handleOpen(event) {

    // [1] Tell the parent which one
    const conversationId = event.currentTarget.dataset.id;

    this.dispatchEvent(new CustomEvent(EVENT_OPEN, { detail: { conversationId } }));
  }

  // The user clicked the back button.
  handleBack() {

    this.dispatchEvent(new CustomEvent(EVENT_BACK));
  }

  // The user clicked the New button.
  handleNew() {

    this.dispatchEvent(new CustomEvent(EVENT_NEW_CONVERSATION));
  }
}
