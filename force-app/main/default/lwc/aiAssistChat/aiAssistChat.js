/*
Component Name: aiAssistChat

=================================================================
=================================================================

Description: The AI Assist chat window. It is the only component that talks to Apex (AIChatController); every child is presentational and reports clicks back as events.

Step 1: Open the window: ask Apex for the chat context and show the state it names (ready, off, maintenance, no access, channel not allowed, terms, no agent)
Step 2: Send a message, show it at once, then poll for the reply only while one is being worked on
Step 3: Show each message with its feedback, suggested action and debug trace, and pass the user's clicks on to Apex
Step 4: Open the history, open, resume, end and export conversations, and start a new one
Step 5: Keep the utility bar, the page record and the window width in step with what the user is doing
Step 6: Save a reply to its record as a note or a task, and share the conversation, read-only, with individual users

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import AiChatScreenFlowModal from "c/aiChatScreenFlowModal";
import { EnclosingUtilityId, setUtilityHighlighted } from "lightning/platformUtilityBarApi";

import getChatContext from "@salesforce/apex/AIChatController.getChatContext";
import getEarlierMessages from "@salesforce/apex/AIChatController.getEarlierMessages";
import getConversationUpdate from "@salesforce/apex/AIChatController.getConversationUpdate";
import sendMessage from "@salesforce/apex/AIChatController.sendMessage";
import retryLatestMessage from "@salesforce/apex/AIChatController.retryLatestMessage";
import closeConversation from "@salesforce/apex/AIChatController.closeConversation";
import openConversation from "@salesforce/apex/AIChatController.openConversation";
import resumeConversation from "@salesforce/apex/AIChatController.resumeConversation";
import getConversationHistory from "@salesforce/apex/AIChatController.getConversationHistory";
import getSharedConversationHistory from "@salesforce/apex/AIChatController.getSharedConversationHistory";
import submitFeedback from "@salesforce/apex/AIChatController.submitFeedback";
import acknowledgeTerms from "@salesforce/apex/AIChatController.acknowledgeTerms";
import runSuggestedAction from "@salesforce/apex/AIChatController.runSuggestedAction";
import declineSuggestedAction from "@salesforce/apex/AIChatController.declineSuggestedAction";
import launchScreenFlowAction from "@salesforce/apex/AIChatController.launchScreenFlowAction";
import recordScreenFlowOutcome from "@salesforce/apex/AIChatController.recordScreenFlowOutcome";
import getDebugTrace from "@salesforce/apex/AIChatController.getDebugTrace";
import getFailureDetail from "@salesforce/apex/AIChatController.getFailureDetail";
import exportConversation from "@salesforce/apex/AIChatController.exportConversation";
import saveReplyToRecord from "@salesforce/apex/AIChatController.saveReplyToRecord";
import getConversationShares from "@salesforce/apex/AIChatController.getConversationShares";
import searchShareableUsers from "@salesforce/apex/AIChatController.searchShareableUsers";
import shareConversation from "@salesforce/apex/AIChatController.shareConversation";
import unshareConversation from "@salesforce/apex/AIChatController.unshareConversation";

import { LABELS, CHAT_STATE, SEND_STATUS, CHANNEL, FEEDBACK_RATING, HISTORY_FILTER, VIEW, SCROLL_REQUEST, MESSAGE_SENDER, HEADER_BADGE, BLOCKED_STATE, USAGE_LIMIT_TYPE, ACTION_STATUS, MESSAGE_ACTION, FLOW_OUTCOME, CONVERSATION_STATUS, MENU, LIST_METHOD, COMPOSER_METHOD, SELECTOR_MESSAGE_LIST, SELECTOR_COMPOSER, PAGE_TYPE_RECORD, ID_PREFIX_NOTICE, SCREEN_FLOW_MODAL_SIZE, TOAST_VARIANT_ERROR, TOAST_VARIANT_SUCCESS, SHARE_MIN_SEARCH_LENGTH, DEFAULT_ACCENT, DEFAULT_HEIGHT_PX, COMMAND_PATTERN, POLL_PROCESSING_CEILING_MS, POLL_HELD_CEILING_MS, ELAPSED_TICK_MS, PROCESSING_GRACE_SECONDS, MS_PER_SECOND, EVENT_VISIBILITY_CHANGE, MIN_CHAT_WIDTH_PX } from "./aiAssistChatSettings";
import { formatLabel, buildShellStyle, getPollDelay, isSavedAgentMessage, buildServerMessage, buildDraftMessage, buildNoticeMessage, buildConversationFromView, buildStartedConversation, findFreshMessages, buildHeaderMenuItems, buildWorkingView, buildMessageItems, getErrorMessage, isSameId, downloadTextFile, buildTranscriptFileName, buildLocalId, findLastIndex } from "./aiAssistChatHelper";

// The AI Assist chat window. Lives in the utility bar or on a record page. Replies are found by polling AIChatController.getConversationUpdate, and only while a reply is being worked on: every 2s, 4s, 8s... up to 8s while it is processing, and up to 60s while the message is held waiting for a free place. Polling is paused while the browser tab is hidden. The call is always made imperatively, never as a @wire, because it can start a held message.
export default class AiAssistChat extends LightningElement {

  // Values passed in by the parent component
  @api recordId; // The record page's record Id (set by the page; the utility bar finds its own)
  @api objectApiName; // The record page's object API name
  @api channel = CHANNEL.RECORD_PAGE; // 'Utility Bar' | 'Record Page Chat'
  @api agentKey; // An agent Id or Developer Name to open with; the first agent offered when blank
  @api height = DEFAULT_HEIGHT_PX; // The height in pixels on a record page
  @api accentColor = DEFAULT_ACCENT; // A hex colour such as #3040C4

  // Values the template reads
  labels = LABELS;

  // What Apex said about the window, and whether it is loading
  context;
  isLoading = true;
  loadError;
  view = VIEW.CHAT;

  // The open conversation and its messages
  conversation = null;
  readOnlyOwner = null; // Set while viewing a conversation someone else started.
  messages = [];
  hasMoreMessages = false;
  isLoadingEarlier = false;

  // Sending and waiting for the reply
  waiting = null; // { startedAt, elapsedSeconds, isHeld, replacesId }
  errorTurn = null; // { reference, debugDetail, isRetrying, retryError }
  isSending = false;
  composerError;
  isCommandMenuOpen = false;

  // The terms the user has to accept
  isAcknowledging = false;
  termsError;

  // The history view
  history = [];
  sharedHistory = [];
  historyFilter = HISTORY_FILTER.RECORD;
  isHistoryLoading = false;
  historyError;
  historySequence = 0;

  // What the user has done to each message
  feedbackStates = {}; // messageId -> { open, submitting, thanks }
  actionStates = {}; // messageId -> { status, message }
  debugTraces = {}; // messageId -> { trace, error }

  // The Save to record dialog
  saveDialog = null; // { messageId, target, text }. When empty, the dialog is closed.
  isSavingToRecord = false;
  saveError;

  // The Share dialog
  isShareOpen = false;
  shareRecipients = [];
  shareResults = [];
  isShareLoading = false;
  isShareSearching = false;
  isShareBusy = false;
  shareError;
  shareSequence = 0; // Counts searches, so a late answer to an older search is ignored

  // The page and the window around the chat
  isTooNarrow = false;
  selectedAgentKey;
  pageRecordId;
  pageObjectApiName;
  isUtilityHighlighted = false;
  hasConnected = false;
  resizeObserver;

  // Timers and counters that keep the polling going
  pollTimer;
  pollAttempt = 0;
  elapsedTimer;
  isRefreshing = false;
  scrollRequest = null; // 'bottom' | 'soft' | 'restore'
  loadSequence = 0;

  // The id of the utility this window sits in, when it is in the utility bar
  @wire(EnclosingUtilityId) utilityId;

  // In the utility bar the record comes from the page the user is on, and follows them as they navigate.
  @wire(CurrentPageReference) handlePageReference(pageReference) {

    // [1] Only the utility bar follows the page
    if (!this.isUtilityBar) return;

    // [2] Read the record from the page, when it is a record page
    const isRecordPage = !!pageReference && pageReference.type === PAGE_TYPE_RECORD;
    const attributes = (pageReference && pageReference.attributes) || {};
    const recordId = isRecordPage ? attributes.recordId : null;

    // [3] Nothing to do when the user is still on the same record
    if (recordId === this.pageRecordId && this.context) return;

    // [4] Keep the new record, and load the window for it once it is connected
    this.pageRecordId = recordId;
    this.pageObjectApiName = isRecordPage ? attributes.objectApiName : null;

    if (this.hasConnected) this.loadContext();
  }

  // Opens the window: starts listening for the tab being shown or hidden, and loads the context.
  connectedCallback() {

    // [1] Listen for the tab being shown or hidden
    this.hasConnected = true;
    document.addEventListener(EVENT_VISIBILITY_CHANGE, this.handleVisibilityChange);

    // [2] Load what the window shows
    this.loadContext();
  }

  // Closes the window: stops the timers and the listeners.
  disconnectedCallback() {

    // [1] Stop polling and the clock
    this.stopWaiting();

    // [2] Stop listening
    document.removeEventListener(EVENT_VISIBILITY_CHANGE, this.handleVisibilityChange);

    if (this.resizeObserver) this.resizeObserver.disconnect();

    this.resizeObserver = null;
  }

  // After every render: watch the width, and scroll the message list when a change asked for it.
  renderedCallback() {

    // [1] Watch the width
    this.observeWidth();

    // [2] Nothing to scroll unless a change asked for it and the list is on screen
    if (!this.scrollRequest) return;

    const list = this.template.querySelector(SELECTOR_MESSAGE_LIST);

    if (!list) return;

    // [3] Put back the old position after earlier messages were added; otherwise go to the bottom
    if (this.scrollRequest === SCROLL_REQUEST.RESTORE) list[LIST_METHOD.RESTORE_SCROLL]();
    else list[LIST_METHOD.SCROLL_TO_BOTTOM](this.scrollRequest === SCROLL_REQUEST.BOTTOM);

    this.scrollRequest = null;
  }

  // The window's own settings, the page and what Apex said about the user.
  get isUtilityBar() {

    return this.channel === CHANNEL.UTILITY_BAR;
  }

  get effectiveRecordId() {

    return this.isUtilityBar ? this.pageRecordId : this.recordId;
  }

  get effectiveObjectApiName() {

    return this.isUtilityBar ? this.pageObjectApiName : this.objectApiName;
  }

  get shellStyle() {

    return buildShellStyle(this.accentColor, this.height, this.isUtilityBar);
  }

  get state() {

    return this.context ? this.context.state : null;
  }

  get ui() {

    return (this.context && this.context.ui) || {};
  }

  get user() {

    return (this.context && this.context.user) || {};
  }

  get record() {

    return (this.context && this.context.record) || {};
  }

  get agent() {

    return this.context ? this.context.agent : null;
  }

  get currentConversationId() {

    return this.conversation ? this.conversation.id : null;
  }

  get termsPolicyUrl() {

    return this.context && this.context.terms ? this.context.terms.policyUrl : null;
  }

  get agentGreeting() {

    return this.agent ? this.agent.greeting : null;
  }

  get hasRecord() {

    return !!this.record.recordId;
  }

  // Which state the window is in.
  get isReady() {

    return this.state === CHAT_STATE.READY;
  }

  get isInactive() {

    return this.state === CHAT_STATE.INACTIVE;
  }

  get isMaintenance() {

    return this.state === CHAT_STATE.MAINTENANCE;
  }

  get isChannelDisabled() {

    return this.state === CHAT_STATE.CHANNEL_DISABLED;
  }

  get isTerms() {

    return this.state === CHAT_STATE.TERMS;
  }

  get isNoAccess() {

    return this.state === CHAT_STATE.NO_ACCESS;
  }

  get isNoAgent() {

    return this.state === CHAT_STATE.NO_AGENT;
  }

  get isHistoryView() {

    return this.isReady && this.view === VIEW.HISTORY;
  }

  get isReadOnly() {

    return !!this.readOnlyOwner;
  }

  // What the header shows.
  get headerBadge() {

    // [1] The most important reason first
    if (this.isInactive) return HEADER_BADGE.OFF;

    if (this.isMaintenance) return HEADER_BADGE.MAINTENANCE;

    if (this.isReady && this.user.debugMode) return HEADER_BADGE.DEBUG;

    return null;
  }

  get agentName() {

    return this.agent ? this.agent.name : null;
  }

  get agentId() {

    return this.agent ? this.agent.id : null;
  }

  get agents() {

    return (this.context && this.context.agents) || [];
  }

  get hasConversation() {

    return !!this.conversation;
  }

  get isNewDisabled() {

    return !!(this.user.newChatsDisabled || !this.canSend || this.blocksNewConversations || this.waiting || this.isSending);
  }

  get headerMenuItems() {

    // [1] The menu is for the user's own conversation, once the window is ready
    const isMenuAvailable = this.isReady && !!this.conversation && !this.isReadOnly;
    const isConversationActive = !!(this.conversation && this.conversation.isActive);

    // [2] Hand the work to the helper
    const canShare = !!(this.conversation && this.conversation.canShare);

    return buildHeaderMenuItems(isMenuAvailable, this.user.exportEnabled, isConversationActive, canShare);
  }

  // What the dialogs show.
  get isSaveDialogOpen() {

    return !!this.saveDialog;
  }

  get saveTarget() {

    return this.saveDialog ? this.saveDialog.target : null;
  }

  get saveText() {

    return this.saveDialog ? this.saveDialog.text : "";
  }

  // What the body shows.
  get showContextBar() {

    return !!(this.record.recordId && this.hasConversation && !this.isReadOnly);
  }

  get showNewChatsPaused() {

    return !!(this.user.newChatsDisabled && !this.conversation && this.messages.length === 0);
  }

  get showEmptyState() {

    return !this.conversation && this.messages.length === 0 && !this.showNewChatsPaused;
  }

  get showReadOnlyBar() {

    return this.isReadOnly;
  }

  get readOnlyHeading() {

    return formatLabel(LABELS.readOnlyLine, this.readOnlyOwner);
  }

  get showEndedBar() {

    return !!(this.conversation && !this.conversation.isActive && !this.isReadOnly);
  }

  get showComposer() {

    return !this.showNewChatsPaused && !this.showEndedBar && !this.isReadOnly;
  }

  get canResumeConversation() {

    return !!(this.conversation && this.conversation.canResume && this.canSend);
  }

  get isStartNewDisabled() {

    return !!(this.user.newChatsDisabled || !this.canSend || this.blocksNewConversations);
  }

  // A user with an AI User Setting but no AI Usage Policy can read, but nothing that sends or starts AI work.
  get canSend() {

    return this.user.canSend !== false;
  }

  // The usage limit the user has reached, from the server; empty when they have reached none.
  get usageLimit() {

    return this.context ? this.context.usage : null;
  }

  // How much of each usage limit the user has used, for the More menu in the header and the usage readout under the composer.
  get usageMeters() {

    return (this.context && this.context.usageMeters) || [];
  }

  // Minutes without activity before a conversation stops counting as open, for the agent in use; empty for never.
  get agentIdleTimeoutMinutes() {

    return this.agent ? this.agent.idleTimeoutMinutes : null;
  }

  get showUsageBanner() {

    return !!(this.usageLimit && !this.isReadOnly);
  }

  // A reached limit stops a new conversation unless the user's behaviour is Notify Only.
  get blocksNewConversations() {

    return !!(this.usageLimit && this.usageLimit.blocksNewConversations);
  }

  // A limit that blocks every message, or one that blocks a new conversation while the user has none open, stops the composer.
  get isBlockedByUsage() {

    return !!(this.usageLimit && (this.usageLimit.blocksMessages || (this.usageLimit.blocksNewConversations && !this.conversation)));
  }

  get showNoPolicyBanner() {

    return !!(this.context && this.context.blockedState === BLOCKED_STATE.NO_POLICY);
  }

  get commands() {

    return (this.context && this.context.commands) || [];
  }

  get openConversationSummary() {

    return this.context ? this.context.openConversation : null;
  }

  // The server names the one reason the user cannot send right now, so the window does not work one out.
  get isBlocked() {

    return !!(this.context && this.context.blockedState);
  }

  get isComposerDisabled() {

    return this.isBlocked || this.isBlockedByUsage || this.isSending;
  }

  get composerPlaceholder() {

    // [1] A blocked user is told why, in the box itself
    if (this.isBlocked && this.context.blockedMessage) return this.context.blockedMessage;

    // [2] A user held back by a usage limit is told, in the box itself
    if (this.isBlockedByUsage) return this.usageLimit.blocksMessages ? LABELS.composerPlaceholderAllowanceUsed : LABELS.composerPlaceholderNewPaused;

    // [3] Otherwise the hint depends on whether there is a record
    return this.record.recordId ? LABELS.composerPlaceholder : LABELS.composerPlaceholderNoRecord;
  }

  get composerFooter() {

    return this.user.debugMode ? LABELS.debugFooter : LABELS.disclaimer;
  }

  get isWorking() {

    return !!this.waiting;
  }

  get working() {

    // [1] Hand the work to the helper
    return buildWorkingView(this.waiting, this.ui, this.record.recordName);
  }

  // The view models aiChatMessageList renders - every per-message flag is decided in the helper so the children stay simple.
  get messageItems() {

    // [1] Gather what the helper needs to decide each flag
    const options = { ui: this.ui, user: this.user, conversation: this.conversation, isReadOnly: this.isReadOnly, agentName: this.agentName, canSend: this.canSend, hasMoreMessages: this.hasMoreMessages, isWaiting: !!this.waiting, hasErrorTurn: !!this.errorTurn, feedbackStates: this.feedbackStates, actionStates: this.actionStates, debugTraces: this.debugTraces };

    // [2] Hand the work to the helper
    return buildMessageItems(this.messages, options);
  }

  // The history view.
  get hasSharedHistory() {

    return this.sharedHistory.length > 0;
  }

  get historyItems() {

    return this.historyFilter === HISTORY_FILTER.SHARED ? this.sharedHistory : this.history;
  }

  // Tells the window the tab was shown or hidden: polling pauses while hidden and starts again, from the beginning, when shown.
  handleVisibilityChange = () => {

    // [1] Nothing to pause or restart unless a reply is being waited for
    if (!this.waiting) return;

    // [2] Hidden: stop the next poll. Shown: start polling again from the beginning
    if (document.hidden) {

      if (this.pollTimer) clearTimeout(this.pollTimer);

      this.pollTimer = null;
    } else {

      this.pollAttempt = 0;
      this.refreshConversation();
    }
  };

  // The user sent a message from the composer.
  async handleSend(event) {

    // [1] Ignore a send while one is under way, with no agent, or in a conversation that is someone else's
    const text = event.detail.text;

    if (this.isSending || !this.agent || this.isReadOnly) return;

    // [2] Show the message at once, as sending, and clear the box
    this.isSending = true;
    this.composerError = null;
    this.errorTurn = null;

    const localId = buildLocalId();
    const commandMatch = text.match(COMMAND_PATTERN);

    this.messages = [...this.messages, buildDraftMessage(localId, text, commandMatch)];
    this.callComposer(COMPOSER_METHOD.CLEAR);
    this.scrollRequest = SCROLL_REQUEST.BOTTOM;

    // [3] Carry on in the open conversation, when there is one
    const openConversationId = this.conversation && this.conversation.isActive ? this.conversation.id : null;

    try {

      // [4] Send it
      const requestJson = JSON.stringify({ conversationId: openConversationId, agentId: this.agent.id, text, channel: this.channel, recordId: this.record.recordId || null, objectApiName: this.record.objectApiName || null });
      const result = await sendMessage({ requestJson });

      // [5] Keep the message, or give the text back with the reason
      if (result.status === SEND_STATUS.SENT) this.applySentMessage(result, localId, text, openConversationId);
      else this.restoreUnsent(localId, text, result.message);
    } catch (error) {

      this.restoreUnsent(localId, text, getErrorMessage(error));
    } finally {

      this.isSending = false;
    }
  }

  // The user pressed Stop. Stop only stops waiting here - the reply is still generated and saved, and shows when the conversation is opened again.
  handleStop() {

    // [1] Stop the polling and the clock
    this.stopWaiting();

    // [2] Say so in the message list
    const notice = buildNoticeMessage(buildLocalId(ID_PREFIX_NOTICE), LABELS.stoppedWaiting);

    this.messages = [...this.messages, notice];
    this.scrollRequest = SCROLL_REQUEST.BOTTOM;
  }

  // The user chose Try again (failed reply) or Regenerate (newest reply); both re-run the newest user message.
  async handleRetry() {

    // [1] Nothing to retry without a conversation
    if (!this.conversation) return;

    // [2] A Regenerate replaces the newest reply, which stays on screen until the new one arrives
    const replaced = this.errorTurn ? null : this.findLast(isSavedAgentMessage);

    if (this.errorTurn) this.errorTurn = { ...this.errorTurn, isRetrying: true, retryError: null };

    try {

      // [3] Run it again and wait for the reply
      await retryLatestMessage({ conversationId: this.conversation.id });

      this.errorTurn = null;
      this.startWaiting(replaced ? replaced.id : null);
      this.scrollRequest = SCROLL_REQUEST.BOTTOM;
    } catch (error) {

      // [4] Show the reason on the failed card, or as a toast when there is no card
      if (this.errorTurn) this.errorTurn = { ...this.errorTurn, isRetrying: false, retryError: getErrorMessage(error) };
      else this.toastError(error);
    }
  }

  // The user clicked in the window: the utility bar stops flashing.
  handleShellClick() {

    // [1] Nothing to switch off unless the utility is highlighted
    if (!this.isUtilityHighlighted || !this.utilityId) return;

    // [2] Switch the highlight off
    this.isUtilityHighlighted = false;
    setUtilityHighlighted(this.utilityId, { highlighted: false }).catch(() => {});
  }

  // The user scrolled to the top and asked for earlier messages.
  async handleLoadEarlier() {

    // [1] Nothing to load without a saved message to start from, or while loading
    const oldest = this.messages.find((message) => message.isServer);

    if (!oldest || this.isLoadingEarlier) return;

    // [2] Remember where the list was, so it can be put back
    const list = this.template.querySelector(SELECTOR_MESSAGE_LIST);

    if (list) list[LIST_METHOD.CAPTURE_SCROLL]();

    this.isLoadingEarlier = true;

    try {

      // [3] Put the earlier messages above the ones shown
      const page = await getEarlierMessages({ conversationId: this.conversation.id, beforeMessageId: oldest.id });

      this.messages = [...page.messages.map(buildServerMessage), ...this.messages];
      this.hasMoreMessages = page.hasMore;
      this.scrollRequest = SCROLL_REQUEST.RESTORE;
    } catch (error) {

      this.toastError(error);
    } finally {

      this.isLoadingEarlier = false;
    }
  }

  // Everything a message can do, from aiChatMessage, bubbled through the list.
  handleMessageAction(event) {

    // [1] The list is the last to hear it
    event.stopPropagation();

    const { action, messageId } = event.detail;

    // [2] Do what was asked
    if (action === MESSAGE_ACTION.RATE) this.rateMessage(messageId, event.detail.rating);
    else if (action === MESSAGE_ACTION.SUBMIT_FEEDBACK) this.sendFeedbackDetail(messageId, event.detail.reason, event.detail.comment);
    else if (action === MESSAGE_ACTION.CLOSE_FEEDBACK) this.setFeedbackState(messageId, { open: false });
    else if (action === MESSAGE_ACTION.REGENERATE) this.handleRetry();
    else if (action === MESSAGE_ACTION.RUN_ACTION) this.runAction(messageId, event.detail.inputs);
    else if (action === MESSAGE_ACTION.DECLINE_ACTION) this.declineAction(messageId);
    else if (action === MESSAGE_ACTION.DISMISS_ACTION) this.setActionState(messageId, { status: ACTION_STATUS.DISMISSED });
    else if (action === MESSAGE_ACTION.LOAD_TRACE) this.loadTrace(messageId);
    else if (action === MESSAGE_ACTION.CLOSE_TRACE) this.closeTrace(messageId);
    else if (action === MESSAGE_ACTION.SAVE_TO_RECORD) this.openSaveDialog(messageId, event.detail.target);
  }

  // The user picked another agent in the header.
  handleAgentSelect(event) {

    // [1] Reload the window for that agent
    this.selectedAgentKey = event.detail.agentId;
    this.loadContext();
  }

  // The user chose New. Ends the open conversation (so single-conversation Agents and concurrency limits stay correct) and shows a fresh one. From a conversation someone else started, it goes back to the user's own chat instead, which has nothing of theirs to end.
  async handleNewConversation() {

    // [1] Go back to the chat view
    this.view = VIEW.CHAT;

    // [2] Someone else's conversation: go back to the user's own chat
    if (this.isReadOnly) {

      this.loadContext();
      return;
    }

    // [3] End the open conversation when it has saved messages
    const hasSavedMessages = this.messages.some((message) => message.isServer);

    if (this.conversation && this.conversation.isActive && hasSavedMessages) {

      try {

        await closeConversation({ conversationId: this.conversation.id });
      } catch (error) {

        this.toastError(error);
        return;
      }
    }

    // [4] Show a fresh conversation
    this.applyConversation(null);
    this.context = { ...this.context, openConversation: null };
    this.callComposer(COMPOSER_METHOD.FOCUS);
  }

  // The user picked an item in the header menu: end the conversation, or export it.
  async handleMenuSelect(event) {

    // [1] Nothing to end or export without a conversation
    const value = event.detail.value;

    if (!this.conversation) return;

    // [2] End the conversation, and show it as closed
    if (value === MENU.END) {

      try {

        await closeConversation({ conversationId: this.conversation.id });

        this.stopWaiting();
        this.conversation = { ...this.conversation, isActive: false, status: CONVERSATION_STATUS.CLOSED, canResume: !!(this.agent && this.agent.allowResume) };

        // Ending one frees a place, so the open conversations limit no longer applies
        if (this.usageLimit && this.usageLimit.limitType === USAGE_LIMIT_TYPE.OPEN) this.context = { ...this.context, usage: null };

        // The open conversations meter drops by one
        this.context = { ...this.context, usageMeters: this.usageMeters.map((meter) => (meter.limitType === USAGE_LIMIT_TYPE.OPEN ? { ...meter, used: Math.max(0, meter.used - 1) } : meter)) };
      } catch (error) {

        this.toastError(error);
      }
    } else if (value === MENU.SHARE) {

      // [2b] Share the conversation, read-only, with individual users
      this.openShareDialog();
    } else if (value === MENU.EXPORT) {

      // [3] Export the transcript as a text file
      try {

        const transcript = await exportConversation({ conversationId: this.conversation.id });

        downloadTextFile(buildTranscriptFileName(this.conversation.name), transcript);
      } catch (error) {

        this.toastError(error);
      }
    }
  }

  // The user chose to carry on with a conversation that ended.
  async handleResume() {

    try {

      // [1] Reopen it and show it
      const view = await resumeConversation({ conversationId: this.conversation.id });

      this.applyConversation(view);
    } catch (error) {

      this.toastError(error);
    }
  }

  // The user chose to start a new conversation after one ended.
  handleStartNew() {

    // [1] Show a fresh conversation
    this.applyConversation(null);
    this.context = { ...this.context, openConversation: null };
  }

  // The user is looking at someone else's conversation and chose to go back to their own.
  handleBackToOwnChat() {

    // [1] Load the window again
    this.loadContext();
  }

  // The user opened the history.
  handleOpenHistory() {

    // [1] Show the history for the record, or for everything when there is no record
    this.view = VIEW.HISTORY;
    this.historyFilter = this.record.recordId ? HISTORY_FILTER.RECORD : HISTORY_FILTER.ALL;
    this.sharedHistory = [];

    // [2] Load the user's own history, and find out whether anything is shared with them
    this.loadHistory();
    this.loadSharedHistory();
  }

  // The user went back from the history to the chat.
  handleHistoryBack() {

    this.view = VIEW.CHAT;
    this.scrollRequest = SCROLL_REQUEST.BOTTOM;
  }

  // The user picked another tab in the history.
  handleHistoryFilter(event) {

    this.historyFilter = event.detail.filter;
    this.loadHistory();
  }

  // The user opened a conversation, from the history or from the card that offers the one already open.
  async handleOpenConversation(event) {

    // [1] A conversation chosen from the shared tab is shown read-only, with its owner's name
    const conversationId = event.detail.conversationId;
    const sharedSummary = this.view === VIEW.HISTORY ? this.sharedHistory.find((summary) => isSameId(summary.id, conversationId)) : null;
    const ownerName = sharedSummary ? sharedSummary.ownerName || LABELS.someoneElse : null;

    try {

      // [2] Open it and show it
      const view = await openConversation({ conversationId });

      this.applyConversation(view, ownerName);
      this.view = VIEW.CHAT;
    } catch (error) {

      this.toastError(error);
    }
  }

  // The user agreed to the terms.
  async handleAgreeTerms() {

    this.isAcknowledging = true;
    this.termsError = null;

    try {

      // [1] Record the agreement, then load the window again
      await acknowledgeTerms();
      await this.loadContext();
    } catch (error) {

      this.termsError = getErrorMessage(error);
    } finally {

      this.isAcknowledging = false;
    }
  }

  // The user chose Check again, or Try again after the window failed to load.
  handleCheckAgain() {

    this.loadContext();
  }

  // The user picked a command in the empty state: put it in the box.
  handleCommandSelect(event) {

    this.callComposer(COMPOSER_METHOD.SET_TEXT, `${event.detail.command} `);
  }

  // The command menu opened or closed.
  handleCommandMenuToggle(event) {

    this.isCommandMenuOpen = event.detail.open;
  }

  // Loads what the window shows. A newer load (navigation, agent switch) replaces one still under way.
  async loadContext() {

    // [1] Start a new load and stop waiting for any reply
    const sequence = ++this.loadSequence;

    this.isLoading = true;
    this.loadError = null;
    this.stopWaiting();

    try {

      // [2] Ask Apex
      const agentKey = this.selectedAgentKey || this.agentKey || null;
      const context = await getChatContext({ recordId: this.effectiveRecordId || null, objectApiName: this.effectiveObjectApiName || null, channel: this.channel, agentKey });

      // [3] Ignore the answer when a newer load replaced this one
      if (sequence !== this.loadSequence) return;

      // [4] Show it
      this.context = context;
      this.view = VIEW.CHAT;
      this.applyConversation(context.conversation);
    } catch (error) {

      if (sequence === this.loadSequence) this.loadError = getErrorMessage(error);
    } finally {

      if (sequence === this.loadSequence) this.isLoading = false;
    }
  }

  // Shows a conversation (or none - a new one) and resets everything tied to the previous one. A conversation someone else started (readOnlyOwner) is shown as it stands, with no waiting for a reply.
  applyConversation(view, readOnlyOwner = null) {

    // [1] Forget everything tied to the previous conversation
    this.stopWaiting();
    this.feedbackStates = {};
    this.actionStates = {};
    this.debugTraces = {};
    this.errorTurn = null;
    this.composerError = null;
    this.saveDialog = null;
    this.isShareOpen = false;
    this.readOnlyOwner = readOnlyOwner;

    // [2] No conversation: show an empty window
    if (!view) {

      this.conversation = null;
      this.messages = [];
      this.hasMoreMessages = false;
      return;
    }

    // [3] Show the conversation and its messages
    this.conversation = buildConversationFromView(view);
    this.messages = (view.messages || []).map(buildServerMessage);
    this.hasMoreMessages = view.hasMoreMessages;
    this.scrollRequest = SCROLL_REQUEST.BOTTOM;

    // [4] Wait for the reply when one is still being worked on, and open the newest debug trace
    if (view.isProcessing && view.isActive && !readOnlyOwner) this.startWaiting();

    this.loadLatestTrace();
  }

  // The server saved the message: swap the one shown as sending for the saved one, and start waiting for the reply.
  applySentMessage(result, localId, text, openConversationId) {

    // [1] The saved version of the message
    const sentMessage = buildServerMessage(result.userMessage);

    // [2] The open conversation hit its Agent's message/token cap, so the service closed it and started a new one
    if (result.isNewConversation && openConversationId) {

      this.feedbackStates = {};
      this.actionStates = {};
      this.debugTraces = {};
      this.hasMoreMessages = false;
      this.messages = [buildNoticeMessage(buildLocalId(ID_PREFIX_NOTICE), LABELS.newConversationStarted), sentMessage];
    } else {

      this.messages = this.messages.map((message) => (message.id === localId ? sentMessage : message));
    }

    // [3] A new conversation was started for this message
    if (result.isNewConversation || !this.conversation) {

      const canShare = !!(this.agent && this.agent.isShareable);

      this.conversation = buildStartedConversation(result.conversationId, text, this.agentName, canShare, !!this.record.recordId);
      this.context = { ...this.context, openConversation: null };
    }

    // [4] Wait for the reply
    this.scrollRequest = SCROLL_REQUEST.BOTTOM;
    this.startWaiting();
  }

  // The message was refused: take it out of the list and give the text back with the reason.
  restoreUnsent(localId, text, message) {

    this.messages = this.messages.filter((item) => item.id !== localId);
    this.callComposer(COMPOSER_METHOD.SET_TEXT, text);
    this.composerError = message;
  }

  // Starts watching for the reply. replacesId is the reply a Regenerate is replacing: it stays on screen until the new one arrives.
  startWaiting(replacesId = null) {

    // [1] Start from nothing
    this.stopWaiting();
    this.waiting = { startedAt: Date.now(), elapsedSeconds: 0, isHeld: false, replacesId };
    this.pollAttempt = 0;

    // [2] The clock only shows in the step card
    if (this.ui.showExecutionTrace) {

      // eslint-disable-next-line @lwc/lwc/no-async-operation
      this.elapsedTimer = setInterval(() => this.tickElapsed(), ELAPSED_TICK_MS);
    }

    // [3] Start polling
    this.schedulePoll();
  }

  // Stops the polling and the clock.
  stopWaiting() {

    // [1] Stop both timers
    if (this.elapsedTimer) clearInterval(this.elapsedTimer);

    if (this.pollTimer) clearTimeout(this.pollTimer);

    // [2] Forget them, and stop waiting
    this.elapsedTimer = null;
    this.pollTimer = null;
    this.waiting = null;
  }

  // Moves the clock on by working out the seconds since the wait began.
  tickElapsed() {

    // [1] Nothing to update once the wait is over
    if (!this.waiting) return;

    // [2] Whole seconds since the wait began
    const elapsedSeconds = Math.floor((Date.now() - this.waiting.startedAt) / MS_PER_SECOND);

    this.waiting = { ...this.waiting, elapsedSeconds };
  }

  // The wait before each poll doubles from the first wait to the ceiling for the kind of wait. Nothing is scheduled while the tab is hidden: it starts again, from the beginning, when the tab is shown.
  schedulePoll() {

    // [1] Cancel the poll already scheduled
    if (this.pollTimer) clearTimeout(this.pollTimer);

    this.pollTimer = null;

    // [2] Nothing to schedule when not waiting, or while the tab is hidden
    if (!this.waiting || document.hidden) return;

    // [3] A held message waits longer between polls than one being worked on
    const ceiling = this.waiting.isHeld ? POLL_HELD_CEILING_MS : POLL_PROCESSING_CEILING_MS;
    const delay = getPollDelay(this.pollAttempt, ceiling);

    this.pollAttempt += 1;

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.pollTimer = setTimeout(() => this.refreshConversation(), delay);
  }

  // Pulls in everything newer than the last saved message. Done waiting once a new reply has arrived; failed if the conversation is no longer being worked on and no reply came.
  async refreshConversation() {

    // [1] Nothing to refresh without a conversation, or while a refresh is under way
    if (!this.conversation || this.isRefreshing) return;

    this.isRefreshing = true;

    const conversationId = this.conversation.id;
    let isAnswered = false;

    try {

      // [2] Ask for everything newer than the last saved message
      const lastSaved = this.findLast((message) => message.isServer);
      const afterMessageId = lastSaved ? lastSaved.id : null;
      const update = await getConversationUpdate({ conversationId, afterMessageId });

      // [3] Stop when the user moved to another conversation meanwhile
      if (!this.conversation || this.conversation.id !== conversationId) return;

      // [4] Add the new messages
      const freshMessages = findFreshMessages(this.messages, update.messages);

      isAnswered = freshMessages.some((message) => message.sender === MESSAGE_SENDER.AGENT);

      if (freshMessages.length) this.addFreshMessages(freshMessages, isAnswered);

      // [5] Keep the conversation's status up to date, and the usage limit once the reply is finished (the server sends it only then)
      this.conversation = { ...this.conversation, status: update.status, isActive: update.status === CONVERSATION_STATUS.ACTIVE };

      if (!update.isProcessing) this.context = { ...this.context, usage: update.usage, usageMeters: update.usageMeters };

      // [6] A reply that arrived after the window gave up on it means the failed card no longer applies
      if (isAnswered) {

        this.errorTurn = null;
        this.highlightUtility();
        this.loadLatestTrace();
      }

      // [7] Decide whether to keep waiting
      if (this.waiting) this.updateWaiting(update, isAnswered);
    } catch {

      // Left waiting - the next poll tries again.
    } finally {

      this.isRefreshing = false;

      if (this.waiting && !isAnswered) this.schedulePoll();
    }
  }

  // Adds the new messages. A reply that replaces a Regenerated one takes its place.
  addFreshMessages(freshMessages, isAnswered) {

    // [1] The reply this one replaces, when it is an answer to a Regenerate
    const replacesId = this.waiting && isAnswered ? this.waiting.replacesId : null;

    // [2] Show the new messages after the ones kept
    this.messages = [...this.messages.filter((message) => message.id !== replacesId), ...freshMessages];
    this.scrollRequest = SCROLL_REQUEST.SOFT;
  }

  // After a poll: stop when answered, fail when the conversation is no longer being worked on, otherwise note whether the message is still held.
  updateWaiting(update, isAnswered) {

    // [1] Answered: nothing more to wait for
    if (isAnswered) {

      this.stopWaiting();
      return;
    }

    // [2] Not being worked on and no reply for long enough means the reply failed
    const hasWaitedLongEnough = Date.now() - this.waiting.startedAt >= PROCESSING_GRACE_SECONDS * MS_PER_SECOND;

    if (!update.isProcessing && hasWaitedLongEnough) {

      this.failReply();
      return;
    }

    // [3] A message that has just been started leaves the held wait, so it goes back to polling quickly
    if (update.isHeld !== this.waiting.isHeld) this.pollAttempt = 0;

    this.waiting = { ...this.waiting, isHeld: !!update.isHeld };
  }

  // Not being worked on any more and no reply came: show the failed card, then add its reference when Apex has one.
  async failReply() {

    // [1] Show the failed card
    this.stopWaiting();
    this.errorTurn = { reference: null, debugDetail: null, isRetrying: false, retryError: null };
    this.scrollRequest = SCROLL_REQUEST.BOTTOM;

    if (!this.conversation) return;

    try {

      // [2] Add the reference to the card
      const detail = await getFailureDetail({ conversationId: this.conversation.id });

      if (this.errorTurn) this.errorTurn = { ...this.errorTurn, reference: detail.reference, debugDetail: detail.debugDetail };
    } catch {

      // The card still works without a reference.
    }
  }

  // Makes the utility bar flash when a reply arrives while the user is elsewhere.
  highlightUtility() {

    // [1] Only the utility bar can flash
    if (!this.utilityId || !this.isUtilityBar) return;

    // [2] Flash it until the user clicks in the window
    this.isUtilityHighlighted = true;
    setUtilityHighlighted(this.utilityId, { highlighted: true }).catch(() => {});
  }

  // The rating saves straight away; thumbs down also opens "What went wrong?" for the optional detail.
  async rateMessage(messageId, rating) {

    // [1] Show the rating at once, keeping the old one in case it fails
    const message = this.messages.find((item) => item.id === messageId);
    const previousRating = message ? message.feedbackRating : null;

    this.updateMessage(messageId, { feedbackRating: rating });
    this.setFeedbackState(messageId, { open: rating === FEEDBACK_RATING.NOT_HELPFUL, thanks: false });

    try {

      // [2] Save it
      await submitFeedback({ messageId, rating, reason: null, comment: null });
    } catch (error) {

      // [3] Put the old rating back
      this.updateMessage(messageId, { feedbackRating: previousRating });
      this.setFeedbackState(messageId, { open: false });
      this.toastError(error);
    }
  }

  // Saves the reason and comment given after a thumbs down.
  async sendFeedbackDetail(messageId, reason, comment) {

    this.setFeedbackState(messageId, { submitting: true });

    try {

      // [1] Save it and say thank you
      await submitFeedback({ messageId, rating: FEEDBACK_RATING.NOT_HELPFUL, reason, comment });

      this.setFeedbackState(messageId, { open: false, submitting: false, thanks: true });
    } catch (error) {

      this.setFeedbackState(messageId, { submitting: false });
      this.toastError(error);
    }
  }

  // Runs a suggested action, or hands a Screen Flow action to the modal.
  async runAction(messageId, inputs) {

    // [1] Show the card as running
    this.setActionState(messageId, { status: ACTION_STATUS.RUNNING });

    // [2] A Screen Flow action is run in a modal, not by the server
    const message = this.messages.find((item) => item.id === messageId);

    if (message && message.suggestedAction && message.suggestedAction.isScreenFlow) {

      await this.runScreenFlow(messageId, message.suggestedAction, inputs);
      return;
    }

    try {

      // [3] Run it on the server and show how it went
      const result = await runSuggestedAction({ messageId, inputsJson: JSON.stringify(inputs || {}) });
      const status = result.isSuccess ? ACTION_STATUS.DONE : ACTION_STATUS.FAILED;

      this.setActionState(messageId, { status, message: result.message });
    } catch (error) {

      this.setActionState(messageId, { status: ACTION_STATUS.FAILED, message: getErrorMessage(error) });
    }
  }

  // A Screen Flow action is not run by the server: it is checked there, then shown in a modal where it runs as the user. How it ended is recorded on the reply afterwards; closing it before it finished leaves the card as it was.
  async runScreenFlow(messageId, action, inputs) {

    let outcome = null;

    // [1] The modal reports how the flow ended
    const handleOutcome = (event) => {

      event.stopPropagation();
      outcome = event.detail.outcome;
    };

    try {

      // [2] Check the action on the server, then run the flow in the modal
      const launch = await launchScreenFlowAction({ messageId, inputsJson: JSON.stringify(inputs || {}) });

      await AiChatScreenFlowModal.open({ size: SCREEN_FLOW_MODAL_SIZE, label: action.name, flowApiName: launch.flowApiName, inputVariables: launch.inputVariables, onoutcome: handleOutcome });
    } catch (error) {

      this.setActionState(messageId, { status: ACTION_STATUS.FAILED, message: getErrorMessage(error) });
      return;
    }

    try {

      // [3] Record how it ended on the reply
      await recordScreenFlowOutcome({ messageId, outcome });
    } catch {

      // The record of the outcome is for the audit trail only, so the user is not interrupted.
    }

    // [4] Show the card as finished, failed, or as it was when the modal was closed early
    if (outcome === FLOW_OUTCOME.FINISHED) this.setActionState(messageId, { status: ACTION_STATUS.DONE, message: null });
    else if (outcome === FLOW_OUTCOME.ERROR) this.setActionState(messageId, { status: ACTION_STATUS.FAILED, message: LABELS.actionFailed });
    else this.setActionState(messageId, { status: ACTION_STATUS.IDLE });
  }

  // Cancel on the confirmation: nothing runs, and the server records that the action was offered and declined. The card stays so the user can still change their mind.
  async declineAction(messageId) {

    try {

      await declineSuggestedAction({ messageId });
    } catch {

      // The record of the decline is for the audit trail only, so the user is not interrupted.
    }
  }

  // Loads the debug trace for one reply.
  async loadTrace(messageId) {

    // [1] Nothing to load without a message, or when it is already loaded or loading
    if (!messageId || this.debugTraces[messageId]) return;

    // [2] Mark it as loading
    this.debugTraces = { ...this.debugTraces, [messageId]: { trace: null, error: null } };

    try {

      // [3] Show the trace
      const trace = await getDebugTrace({ messageId });

      this.debugTraces = { ...this.debugTraces, [messageId]: { trace, error: null } };
    } catch (error) {

      this.debugTraces = { ...this.debugTraces, [messageId]: { trace: null, error: getErrorMessage(error) } };
    }
  }

  // Dropping the loaded trace puts the "Show request trace" link back - opening it again reloads it fresh.
  closeTrace(messageId) {

    // [1] Keep every trace except this one
    const remaining = { ...this.debugTraces };

    delete remaining[messageId];

    this.debugTraces = remaining;
  }

  // Debug mode opens the trace for the newest reply automatically; older ones load on request.
  loadLatestTrace() {

    // [1] Only in debug mode, and not in someone else's conversation
    if (!this.user.debugMode || this.isReadOnly) return;

    // [2] Load the newest saved reply's trace
    const latestReply = this.findLast(isSavedAgentMessage);

    if (latestReply) this.loadTrace(latestReply.id);
  }

  // The "Shared with me" tab shows only for a user who has something shared with them, and only that user's scope and permissions decide that, so the window asks once each time the history opens and shows the tab when the answer is not empty.
  async loadSharedHistory() {

    try {

      this.sharedHistory = await getSharedConversationHistory();
    } catch {

      this.sharedHistory = [];
    }
  }

  // Loads the user's own history for the tab shown. A newer load replaces one still under way.
  async loadHistory() {

    // [1] Start a new load
    const sequence = ++this.historySequence;

    this.historyError = null;

    // [2] The shared tab was already loaded when the history opened
    if (this.historyFilter === HISTORY_FILTER.SHARED) {

      this.isHistoryLoading = false;
      return;
    }

    this.isHistoryLoading = true;

    try {

      // [3] Ask Apex, and keep the answer only when no newer load replaced this one
      const onlyThisRecord = this.historyFilter === HISTORY_FILTER.RECORD;
      const history = await getConversationHistory({ recordId: this.record.recordId || null, onlyThisRecord });

      if (sequence === this.historySequence) this.history = history;
    } catch (error) {

      if (sequence === this.historySequence) this.historyError = getErrorMessage(error);
    } finally {

      if (sequence === this.historySequence) this.isHistoryLoading = false;
    }
  }

  // Below MIN_CHAT_WIDTH_PX the window asks for a wider region instead of rendering cramped.
  observeWidth() {

    // [1] Watch once, and only where the browser can
    if (this.resizeObserver || typeof ResizeObserver === "undefined") return;

    // [2] Note whether the window is too narrow each time its width changes
    const handleResize = (entries) => {

      const width = entries[0].contentRect.width;
      const isTooNarrow = width > 0 && width < MIN_CHAT_WIDTH_PX;

      if (isTooNarrow !== this.isTooNarrow) this.isTooNarrow = isTooNarrow;
    };

    this.resizeObserver = new ResizeObserver(handleResize);
    this.resizeObserver.observe(this.template.host);
  }

  // Parent -> child calls into the composer (setText, clear, focus).
  callComposer(method, argument) {

    const composer = this.template.querySelector(SELECTOR_COMPOSER);

    if (composer) composer[method](argument);
  }

  // Changes some fields of one message.
  updateMessage(messageId, changes) {

    this.messages = this.messages.map((message) => (message.id === messageId ? { ...message, ...changes } : message));
  }

  // Changes some fields of what the user has done with one message's feedback.
  setFeedbackState(messageId, changes) {

    const previousState = this.feedbackStates[messageId] || {};

    this.feedbackStates = { ...this.feedbackStates, [messageId]: { ...previousState, ...changes } };
  }

  // Sets the state of one message's suggested action card.
  setActionState(messageId, state) {

    this.actionStates = { ...this.actionStates, [messageId]: state };
  }

  // The newest message matching the test, or null.
  findLast(predicate) {

    const index = findLastIndex(this.messages, predicate);

    return index < 0 ? null : this.messages[index];
  }

  // Shows an error as a toast.
  // Opens the Save to record dialog with the reply text, so the user can change it before it is saved.
  openSaveDialog(messageId, target) {

    // [1] Find the reply
    const message = this.messages.find((item) => item.id === messageId);

    if (!message) return;

    // [2] Open the dialog with the text the user sees
    this.saveError = null;
    this.saveDialog = { messageId, target, text: message.displayText };
  }

  // The user confirmed the text in the Save to record dialog. Apex checks the reply is theirs and saves it as the user.
  async handleSaveConfirm(event) {

    // [1] Nothing to save without a dialog, or while a save is running
    if (!this.saveDialog || this.isSavingToRecord) return;

    this.isSavingToRecord = true;
    this.saveError = null;

    try {

      // [2] Save the text the user confirmed
      const { messageId, target } = this.saveDialog;
      const result = await saveReplyToRecord({ messageId, target, text: event.detail.text });

      // [3] Close the dialog and say it worked
      this.saveDialog = null;
      this.dispatchEvent(new ShowToastEvent({ title: LABELS.appName, message: (result && result.message) || LABELS.savedToRecord, variant: TOAST_VARIANT_SUCCESS }));
    } catch (error) {

      // [4] Keep the dialog open with the reason, so the text is not lost
      this.saveError = getErrorMessage(error);
    } finally {

      this.isSavingToRecord = false;
    }
  }

  // The user closed the Save to record dialog without saving.
  handleSaveCancel() {

    // [1] Close it
    this.saveDialog = null;
    this.saveError = null;
  }

  // Opens the Share dialog and loads the people the conversation is already shared with.
  async openShareDialog() {

    // [1] Open it empty, with the people loading
    this.isShareOpen = true;
    this.shareRecipients = [];
    this.shareResults = [];
    this.shareError = null;
    this.isShareLoading = true;

    try {

      // [2] Load the people with access
      this.shareRecipients = await getConversationShares({ conversationId: this.conversation.id });
    } catch (error) {

      this.shareError = getErrorMessage(error);
    } finally {

      this.isShareLoading = false;
    }
  }

  // The user typed in the Share dialog's search box and stopped. Only the newest search's answer is kept.
  async handleShareSearch(event) {

    // [1] Start a new search, and drop the answer of any older one
    const searchText = event.detail.text;
    this.shareSequence += 1;
    const sequence = this.shareSequence;

    // [2] Too short to search: show no results
    if (searchText.length < SHARE_MIN_SEARCH_LENGTH) {

      this.shareResults = [];
      this.isShareSearching = false;
      return;
    }

    this.isShareSearching = true;
    this.shareError = null;

    try {

      // [3] Search, and keep the answer only when no newer search has started
      const results = await searchShareableUsers({ conversationId: this.conversation.id, searchText });

      if (sequence === this.shareSequence) this.shareResults = results;
    } catch (error) {

      if (sequence === this.shareSequence) this.shareError = getErrorMessage(error);
    } finally {

      if (sequence === this.shareSequence) this.isShareSearching = false;
    }
  }

  // The user chose a person to share the conversation with.
  async handleShareUser(event) {

    // [1] Nothing to do while another step is running
    if (this.isShareBusy) return;

    this.isShareBusy = true;
    this.shareError = null;

    try {

      // [2] Share it, then show the person as having access and take them out of the results
      const userId = event.detail.userId;
      const recipient = await shareConversation({ conversationId: this.conversation.id, userId });

      this.shareRecipients = [...this.shareRecipients, recipient];
      this.shareResults = this.shareResults.filter((result) => result.userId !== userId);
    } catch (error) {

      this.shareError = getErrorMessage(error);
    } finally {

      this.isShareBusy = false;
    }
  }

  // The user chose to remove a person's access.
  async handleUnshareUser(event) {

    // [1] Nothing to do while another step is running
    if (this.isShareBusy) return;

    this.isShareBusy = true;
    this.shareError = null;

    try {

      // [2] Remove the access, then take the person out of the list
      const userId = event.detail.userId;

      await unshareConversation({ conversationId: this.conversation.id, userId });

      this.shareRecipients = this.shareRecipients.filter((recipient) => recipient.userId !== userId);
    } catch (error) {

      this.shareError = getErrorMessage(error);
    } finally {

      this.isShareBusy = false;
    }
  }

  // The user closed the Share dialog.
  handleShareClose() {

    // [1] Close it and drop any search still waiting
    this.shareSequence += 1;
    this.isShareOpen = false;
    this.isShareSearching = false;
  }

  toastError(error) {

    this.dispatchEvent(new ShowToastEvent({ title: LABELS.appName, message: getErrorMessage(error), variant: TOAST_VARIANT_ERROR }));
  }
}
