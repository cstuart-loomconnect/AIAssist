/*
Component Name: aiAssistChat

=================================================================
=================================================================

Description: The work the AI Assist chat window hands off: plain functions that take what they need and return a result.

Step 1: Format text for the user (labels, times, days, token counts, elapsed time, errors)
Step 2: Turn what Apex returns into what the child components render (messages, items, working view, menu)
Step 3: Turn an AI reply from markdown into safe HTML
Step 4: Small checks and searches (same Id, last matching message, file name, file download)

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS, CONVERSATION_STATUS, NEW_CONVERSATION_TITLE_LENGTH, MESSAGE_SENDER, MESSAGE_STATUS, FEEDBACK_RATING, ACTION_STATUS, WORKING_MODE, STEP_STATE, MENU, MENU_ICONS, ACCENT_PATTERN, DEFAULT_ACCENT, DEFAULT_HEIGHT_PX, UTILITY_BAR_HEIGHT, POLL_FIRST_MS, MS_PER_DAY, SECONDS_PER_MINUTE, ELAPSED_SECONDS_LENGTH, ELAPSED_PAD_CHARACTER, DAY_SEPARATOR_JOIN, TIME_FORMAT_OPTIONS, DAY_FORMAT_OPTIONS, DOWNLOAD_LINK_TAG, DOWNLOAD_LINK_HIDDEN_DISPLAY, DOWNLOAD_DATA_PREFIX, TRANSCRIPT_DEFAULT_NAME, TRANSCRIPT_EXTENSION, TRANSCRIPT_NAME_UNSAFE_PATTERN, TRANSCRIPT_NAME_EDGE_PATTERN, TRANSCRIPT_NAME_SEPARATOR, ID_PREFIX_LOCAL, LINE_BREAK_PATTERN, NEW_LINE, BULLET_PATTERN, NUMBERED_PATTERN, HEADING_PATTERN, LIST_TYPE, ESCAPE_RULES, INLINE_MARKDOWN_RULES } from "./aiAssistChatSettings";

// The number the next local id is built from.
let localIdCounter = 0;

// "Reading {0} and thinking" + "Contact" -> "Reading Contact and thinking". The value is put in as it is, so a "$" in a name is never read as a special pattern.
export function formatLabel(template, ...values) {

  // [1] Put each value in place of its {number}
  return values.reduce((text, value, index) => text.replace(`{${index}}`, () => value), template);
}

// The CSS custom property and height the shell is styled with. An accent that is not a hex colour falls back to the default.
export function buildShellStyle(accentColor, height, isUtilityBar) {

  // [1] Use the accent only when it is a hex colour
  const isValidAccent = ACCENT_PATTERN.test(accentColor || "");
  const accent = isValidAccent ? accentColor : DEFAULT_ACCENT;

  // [2] The utility bar fills its space; a record page uses the height it was given
  const pageHeight = `${Number(height) || DEFAULT_HEIGHT_PX}px`;
  const shellHeight = isUtilityBar ? UTILITY_BAR_HEIGHT : pageHeight;

  return `--aia-accent: ${accent}; height: ${shellHeight};`;
}

// The wait before poll number `attempt` (from 0): doubles from the first wait up to the ceiling.
export function getPollDelay(attempt, ceilingMs) {

  // [1] Double the first wait for each earlier attempt, but never go past the ceiling
  const doubledDelay = POLL_FIRST_MS * 2 ** attempt;

  return Math.min(doubledDelay, ceilingMs);
}

// True for a reply from the AI that the server has saved.
export function isSavedAgentMessage(message) {

  // [1] An AI reply that came from the server, not one made in the window
  return message.sender === MESSAGE_SENDER.AGENT && message.isServer;
}

// Apex ChatMessage -> the shape the children render from. bodyHtml is built once here, not on every render.
export function buildServerMessage(message) {

  // [1] Only an AI reply has a body made from markdown
  const isAgentMessage = message.sender === MESSAGE_SENDER.AGENT;
  const bodyHtml = isAgentMessage ? buildHtmlFromMarkdown(message.displayText) : null;

  // [2] Mark it as saved on the server
  return { ...message, isServer: true, status: MESSAGE_STATUS.SENT, bodyHtml };
}

// A message the user has just typed, shown while the server is still saving it.
export function buildDraftMessage(localId, text, commandMatch) {

  // [1] A command starts with a slash, and its name is the part that matched
  const isCommand = !!commandMatch;
  const commandName = commandMatch ? commandMatch[0] : null;

  // [2] Show it as sending, dated now
  return { id: localId, sender: MESSAGE_SENDER.USER, displayText: text, isCommand, commandName, createdDate: new Date().toISOString(), status: MESSAGE_STATUS.SENDING };
}

// A line of text in the message list that is not from the user or the AI, such as "New conversation started".
export function buildNoticeMessage(noticeId, noticeText) {

  // [1] A notice has an id and its text only
  return { id: noticeId, isNotice: true, noticeText };
}

// The conversation the window keeps from what Apex returned.
export function buildConversationFromView(view) {

  // [1] Keep only what the window needs
  return { id: view.id, name: view.name, title: view.title, status: view.status, isActive: view.isActive, canResume: view.canResume, agentName: view.agentName, canShare: !!view.canShare, hasRelatedRecord: !!view.hasRelatedRecord };
}

// The window's own record of a conversation the server has just started for the user's first message.
export function buildStartedConversation(conversationId, text, agentName, canShare, hasRelatedRecord) {

  // [1] The title is the start of the first message
  const title = text.slice(0, NEW_CONVERSATION_TITLE_LENGTH);

  return { id: conversationId, title, status: CONVERSATION_STATUS.ACTIVE, isActive: true, canResume: false, agentName, canShare, hasRelatedRecord };
}

// The messages Apex sent that the window does not have yet, ready to show.
export function findFreshMessages(knownMessages, serverMessages) {

  // [1] Collect the ids the window already has
  const knownIds = new Set(knownMessages.map((message) => message.id));

  // [2] Keep the new ones and prepare them for the children
  const newMessages = serverMessages.filter((message) => !knownIds.has(message.id));

  return newMessages.map(buildServerMessage);
}

// What the header's menu offers: export when the user may, sharing when the conversation can be shared, and ending a conversation that is still open.
export function buildHeaderMenuItems(isMenuAvailable, exportEnabled, isConversationActive, canShare) {

  // [1] No menu while the window is not ready, there is no conversation, or it is someone else's
  const items = [];

  if (!isMenuAvailable) return items;

  // [2] Add each item the user may use
  if (exportEnabled) items.push({ value: MENU.EXPORT, label: LABELS.exportConversation, iconName: MENU_ICONS.EXPORT });

  if (canShare) items.push({ value: MENU.SHARE, label: LABELS.shareConversation, iconName: MENU_ICONS.SHARE, hint: LABELS.shareHint });

  if (isConversationActive) items.push({ value: MENU.END, label: LABELS.closeConversation, iconName: MENU_ICONS.END });

  return items;
}

// What the window shows while a reply is being worked on, or null when it shows nothing. A message held for a free place says so, whatever the typing and steps settings. Otherwise steps mode shows the step card, and typing mode the lighter indicator. The steps are not live: the server holds no step until the reply is saved, so the card shows "Reading..." as the active step and "Write the answer" as pending, with the elapsed clock.
export function buildWorkingView(waiting, ui, recordName) {

  // [1] Nothing is being waited for
  if (!waiting) return null;

  // [2] A held message says it is waiting for a free place
  if (waiting.isHeld) return { mode: WORKING_MODE.TYPING, label: LABELS.heldLabel };

  // [3] Steps mode: the step card with the elapsed clock
  if (ui.showExecutionTrace) {

    const readingLabel = recordName ? formatLabel(LABELS.stepReadingRecord, recordName) : LABELS.stepReading;
    const steps = [{ label: readingLabel, state: STEP_STATE.ACTIVE }, { label: LABELS.stepWriting, state: STEP_STATE.PENDING }];

    return { mode: WORKING_MODE.STEPS, elapsedLabel: formatElapsed(waiting.elapsedSeconds), steps };
  }

  // [4] Typing mode: the lighter indicator
  if (ui.typingIndicatorEnabled) {

    const typingLabel = recordName ? formatLabel(LABELS.workingOnRecord, recordName) : LABELS.workingLabel;

    return { mode: WORKING_MODE.TYPING, label: typingLabel };
  }

  // [5] Both are switched off
  return null;
}

// The view models aiChatMessageList renders - every per-message flag is decided here so the children stay simple.
export function buildMessageItems(messages, options) {

  // [1] Work out what applies to every message
  const { ui, user, conversation, isReadOnly, agentName, canSend, hasMoreMessages, isWaiting, hasErrorTurn, feedbackStates, actionStates, debugTraces } = options;
  const canAct = !isReadOnly;
  const isDebugMode = !!user.debugMode && !isReadOnly;
  const isActionsOn = canAct && canSend && !!ui.inlineActionsEnabled && !!user.workflowActionsEnabled;
  const isConversationActive = !!(conversation && conversation.isActive);
  const shownAgentName = (conversation && conversation.agentName) || agentName || LABELS.appName;
  const canSaveToRecord = canAct && !!(conversation && conversation.hasRelatedRecord);
  const shared = { ui, canAct, canSend, canSaveToRecord, isDebugMode, isActionsOn, isConversationActive, isWaiting, hasErrorTurn, feedbackStates, actionStates, debugTraces, agentName: shownAgentName };

  // [2] Find the newest saved AI reply, and the first message that is not a notice
  const lastAgentIndex = findLastIndex(messages, isSavedAgentMessage);
  const firstRealIndex = messages.findIndex((message) => !message.isNotice);

  // [3] Build one item per message, remembering the day of the previous one and whether the AI's name has been shown
  const items = [];
  let previousDate = null;
  let isAgentHeaderShown = false;

  messages.forEach((message, index) => {

    if (message.isNotice) {

      items.push(buildNoticeItem(message));
      return;
    }

    // [4] A day separator goes above the first message and above the first message of each new day
    const createdDate = new Date(message.createdDate);
    const isFirstMessage = index === firstRealIndex && !hasMoreMessages;
    const isNewDay = !!previousDate && getDayDifference(previousDate, createdDate) !== 0;
    const separatorLabel = isFirstMessage || isNewDay ? formatDaySeparator(createdDate) : null;
    previousDate = createdDate;

    // [5] What every kind of message has
    const showTimestamp = !!ui.showTimestamps && message.status === MESSAGE_STATUS.SENT;
    const base = { id: message.id, separatorLabel, displayText: message.displayText, timeLabel: formatTime(message.createdDate), showTimestamp };

    // [6] A message from the user
    if (message.sender === MESSAGE_SENDER.USER) {

      items.push(buildUserItem(base, message));
      return;
    }

    // [7] A message from the AI: only the first one shows the agent's name
    const showAgentHeader = !isAgentHeaderShown;
    isAgentHeaderShown = true;

    items.push(buildAgentItem(base, message, shared, showAgentHeader, index === lastAgentIndex));
  });

  return items;
}

// The item for a notice line.
function buildNoticeItem(message) {

  // [1] A notice shows its text only
  return { id: message.id, isNotice: true, noticeText: message.noticeText };
}

// The item for a message from the user.
function buildUserItem(base, message) {

  // [1] A command shows its name apart from the rest of the text
  const isCommand = !!message.isCommand;
  const commandRest = isCommand ? message.displayText.slice(message.commandName.length).trim() : null;

  // [2] Show whether the server has saved it yet
  const isSending = message.status === MESSAGE_STATUS.SENDING;

  return { ...base, isUser: true, isCommand, commandName: message.commandName, commandRest, isSending };
}

// The item for a message from the AI.
function buildAgentItem(base, message, shared, showAgentHeader, isLastAgentMessage) {

  // [1] Read what the window knows about this message
  const { ui, canAct, canSend, canSaveToRecord, isDebugMode, isActionsOn, isConversationActive, isWaiting, hasErrorTurn, feedbackStates, actionStates, debugTraces, agentName } = shared;
  const feedback = feedbackStates[message.id] || {};
  const trace = debugTraces[message.id];
  const sources = message.sources || [];

  // [2] The sources as a list the template can loop over
  const sourceItems = sources.map((label, sourceIndex) => ({ key: `${sourceIndex}`, label }));

  // [3] Only the newest reply of an open conversation can be regenerated, and not while waiting or after a failure
  const canRegenerate = canAct && canSend && isLastAgentMessage && isConversationActive && !isWaiting && !hasErrorTurn;

  // [4] The suggested action and its card state
  const suggestedAction = isActionsOn ? message.suggestedAction : null;
  const actionState = actionStates[message.id] || { status: ACTION_STATUS.IDLE };

  // [5] The debug trace: shown when loaded, or a link to load it
  const showTrace = isDebugMode && !!trace;
  const showTraceLink = isDebugMode && !trace;

  return {
    ...base,
    isAgent: true,
    bodyHtml: message.bodyHtml,
    showAgentHeader,
    agentName,
    hasSources: sources.length > 0,
    sources: sourceItems,
    skillName: message.skillName || null,
    showFeedback: canAct && !!ui.feedbackEnabled,
    isHelpful: message.feedbackRating === FEEDBACK_RATING.HELPFUL,
    isNotHelpful: message.feedbackRating === FEEDBACK_RATING.NOT_HELPFUL,
    feedbackOpen: !!feedback.open,
    feedbackSubmitting: !!feedback.submitting,
    feedbackThanks: !!feedback.thanks,
    canRegenerate,
    canSaveToRecord,
    tokenLabel: message.tokenCount ? formatTokenCount(message.tokenCount) : null,
    suggestedAction,
    actionsDisplay: ui.suggestedActionsDisplay,
    actionState,
    showTrace,
    trace: trace ? trace.trace : null,
    traceError: trace ? trace.error : null,
    showTraceLink
  };
}

// 1240 -> "1,240 tokens".
export function formatTokenCount(value) {

  // [1] No count, no text
  if (value === null || value === undefined) return "";

  // [2] Put the number in the user's own format
  return `${Number(value).toLocaleString()} ${LABELS.tokens}`;
}

// A time of day in the user's own format, or empty when there is no time.
export function formatTime(value) {

  // [1] No time, no text
  if (!value) return "";

  // [2] Hours and minutes only
  return new Date(value).toLocaleTimeString([], TIME_FORMAT_OPTIONS);
}

// How many whole days apart two dates are (0 for the same day).
export function getDayDifference(date, now = new Date()) {

  // [1] The start of each day, so the time of day does not matter
  const startOfDate = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  const startOfNow = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();

  // [2] Count the days between them
  return Math.round((startOfNow - startOfDate) / MS_PER_DAY);
}

// "Today · 13:02", "Yesterday · 09:10", "Thu 24 Sep · 16:40".
export function formatDaySeparator(value, now = new Date()) {

  // [1] Say how long ago the day was
  const date = new Date(value);
  const dayDifference = getDayDifference(date, now);

  // [2] Today and yesterday have their own words; any other day is written out
  let day = date.toLocaleDateString([], DAY_FORMAT_OPTIONS);

  if (dayDifference === 0) day = LABELS.todayHeading;
  else if (dayDifference === 1) day = LABELS.yesterday;

  // [3] Add the time of day
  return `${day}${DAY_SEPARATOR_JOIN}${formatTime(value)}`;
}

// 4 -> "0:04", 75 -> "1:15".
export function formatElapsed(seconds) {

  // [1] Whole seconds, never below zero
  const totalSeconds = Math.max(0, Math.floor(seconds));

  // [2] Minutes, then seconds with a leading zero
  const minutes = Math.floor(totalSeconds / SECONDS_PER_MINUTE);
  const remainingSeconds = String(totalSeconds % SECONDS_PER_MINUTE).padStart(ELAPSED_SECONDS_LENGTH, ELAPSED_PAD_CHARACTER);

  return `${minutes}:${remainingSeconds}`;
}

// Replaces the characters HTML would read as markup.
function formatEscapedText(text) {

  // [1] Apply each rule in turn
  return ESCAPE_RULES.reduce((escapedText, rule) => escapedText.replace(rule.pattern, rule.replacement), text);
}

// One line of an AI reply with its bold, italic, code and link marks turned into tags. The text is escaped first.
function formatInlineMarkdown(text) {

  // [1] Escape, then apply each mark in turn
  const escapedText = formatEscapedText(text);

  return INLINE_MARKDOWN_RULES.reduce((markedText, rule) => markedText.replace(rule.pattern, rule.replacement), escapedText);
}

// Minimal, escape-first markdown for AI replies (paragraphs, **bold**, *italic*, `code`, lists, headings, links). The output also passes through lightning-formatted-rich-text's sanitiser.
export function buildHtmlFromMarkdown(markdown) {

  // [1] No text, no HTML
  if (!markdown) return "";

  // [2] Go through the reply a line at a time
  const lines = markdown.replace(LINE_BREAK_PATTERN, NEW_LINE).split(NEW_LINE);
  const html = [];
  let listType = null;
  let paragraph = [];

  // [3] Writes out the lines collected so far as one paragraph
  const flushParagraph = () => {

    if (paragraph.length) html.push(`<p>${paragraph.map(formatInlineMarkdown).join("<br>")}</p>`);

    paragraph = [];
  };

  // [4] Closes the list that is open, if any
  const closeList = () => {

    if (listType) html.push(`</${listType}>`);

    listType = null;
  };

  // [5] A bullet or numbered line is a list item, a # line is a heading, a blank line ends a block, anything else is paragraph text
  lines.forEach((line) => {

    const bullet = line.match(BULLET_PATTERN);
    const numbered = line.match(NUMBERED_PATTERN);
    const heading = line.match(HEADING_PATTERN);

    if (bullet || numbered) {

      flushParagraph();

      const type = bullet ? LIST_TYPE.BULLET : LIST_TYPE.NUMBERED;

      if (listType !== type) {

        closeList();
        html.push(`<${type}>`);
        listType = type;
      }

      html.push(`<li>${formatInlineMarkdown((bullet || numbered)[1])}</li>`);
    } else if (heading) {

      flushParagraph();
      closeList();
      html.push(`<p><strong>${formatInlineMarkdown(heading[1])}</strong></p>`);
    } else if (!line.trim()) {

      flushParagraph();
      closeList();
    } else {

      closeList();
      paragraph.push(line);
    }
  });

  // [6] Close whatever is still open
  flushParagraph();
  closeList();

  return html.join("");
}

// Readable message from an Apex/LDS error in any of its shapes.
export function getErrorMessage(error) {

  // [1] No error, or a plain text one
  if (!error) return LABELS.genericError;

  if (typeof error === "string") return error;

  // [2] A list of errors, one message each
  if (Array.isArray(error.body)) return error.body.map((entry) => entry.message).join(", ");

  // [3] One error with a message in its body, or in the error itself
  if (error.body && typeof error.body.message === "string") return error.body.message;

  if (typeof error.message === "string") return error.message;

  // [4] Nothing readable
  return LABELS.genericError;
}

// Salesforce Ids arrive as 15 or 18 characters depending on the source - compare on the first 15.
export function isSameId(first, second) {

  // [1] A missing Id matches nothing
  if (!first || !second) return false;

  // [2] Compare the first 15 characters
  return String(first).slice(0, 15) === String(second).slice(0, 15);
}

// Saves text as a file through a temporary link.
export function downloadTextFile(fileName, text) {

  // [1] Make a link that holds the text and names the file
  const link = document.createElement(DOWNLOAD_LINK_TAG);
  link.href = `${DOWNLOAD_DATA_PREFIX}${encodeURIComponent(text)}`;
  link.download = fileName;
  link.style.display = DOWNLOAD_LINK_HIDDEN_DISPLAY;

  // [2] Click it, then take it away
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
}

// "AI Conversation - 000123" -> "AI-Conversation-000123.txt".
export function buildTranscriptFileName(conversationName) {

  // [1] Use the default name when the conversation has none
  const name = conversationName || TRANSCRIPT_DEFAULT_NAME;

  // [2] Swap anything that is not a letter or digit for a dash, and trim dashes from the ends
  const dashedName = name.replace(TRANSCRIPT_NAME_UNSAFE_PATTERN, TRANSCRIPT_NAME_SEPARATOR);
  const trimmedName = dashedName.replace(TRANSCRIPT_NAME_EDGE_PATTERN, "");

  return `${trimmedName}${TRANSCRIPT_EXTENSION}`;
}

// An id for a message or notice that only exists in the window until the server saves it.
export function buildLocalId(prefix = ID_PREFIX_LOCAL) {

  // [1] Count up so two ids made in the same millisecond differ
  localIdCounter += 1;

  return `${prefix}-${Date.now()}-${localIdCounter}`;
}

// Index of the last item matching the predicate, or -1.
export function findLastIndex(items, predicate) {

  // [1] Look from the end back to the start
  for (let index = items.length - 1; index >= 0; index--) {

    if (predicate(items[index])) return index;
  }

  // [2] Nothing matched
  return -1;
}
