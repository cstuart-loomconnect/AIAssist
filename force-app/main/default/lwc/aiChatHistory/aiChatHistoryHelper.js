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

import { LABELS, STATUS_ACTIVE, STATUS_ARCHIVED, CLOSE_REASON_IDLE_TIMEOUT, CLOSE_REASON_MESSAGE_LIMIT, CLOSE_REASON_TOKEN_LIMIT, STATUS_CLASS, STATUS_CLASS_ACTIVE, ROW_CLASS, ROW_CLASS_CURRENT, TITLE_CLASS, TITLE_CLASS_CURRENT, DAYS_IN_WEEK, DAYS_AGO_TODAY, DAYS_AGO_YESTERDAY, MS_PER_DAY, TIME_FORMAT_OPTIONS, WEEKDAY_FORMAT_OPTIONS, DAY_MONTH_FORMAT_OPTIONS, ID_COMPARE_LENGTH, COUNT_PLACEHOLDER, META_SEPARATOR } from "./aiChatHistorySettings";

// Works out the start of the day a date falls on, as a number of milliseconds.
export function buildStartOfDay(date) {

  // [1] Keep the year, month and day and drop the time
  const startOfDay = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();

  return startOfDay;
}

// Works out how many whole days ago a date was, counting by calendar day.
export function buildDayDifference(date, now = new Date()) {

  // [1] Find the start of each day
  const startOfToday = buildStartOfDay(now);
  const startOfDate = buildStartOfDay(date);

  // [2] Count the days between them
  const dayDifference = Math.round((startOfToday - startOfDate) / MS_PER_DAY);

  return dayDifference;
}

// Writes a time of day in the user's own locale. A blank value gives a blank label.
export function formatTime(value) {

  // [1] Nothing to show when there is no value
  if (!value) return "";

  // [2] Write the time of day
  const timeLabel = new Date(value).toLocaleTimeString([], TIME_FORMAT_OPTIONS);

  return timeLabel;
}

// Writes the date on the right of a row: the time today, the day this week, or the day and month before that.
export function formatHistoryDate(value, now = new Date()) {

  // [1] Work out how many days ago it was
  const date = new Date(value);
  const dayDifference = buildDayDifference(date, now);

  // [2] Today shows the time
  if (dayDifference === DAYS_AGO_TODAY) return formatTime(value);

  // [3] This week shows the day
  if (dayDifference < DAYS_IN_WEEK) return date.toLocaleDateString([], WEEKDAY_FORMAT_OPTIONS);

  // [4] Anything older shows the day and month
  return date.toLocaleDateString([], DAY_MONTH_FORMAT_OPTIONS);
}

// Picks the group heading a conversation sits under, from how many days ago it was last used.
export function buildGroupLabel(dayDifference) {

  // [1] Pick the heading from the day
  if (dayDifference === DAYS_AGO_TODAY) return LABELS.todayHeading;
  if (dayDifference === DAYS_AGO_YESTERDAY) return LABELS.yesterday;
  if (dayDifference < DAYS_IN_WEEK) return LABELS.earlierThisWeek;

  return LABELS.older;
}

// Groups conversations under Today, Yesterday, Earlier this week and Older, keeping their order.
export function buildConversationGroups(conversations, now = new Date()) {

  // [1] The parent may not have set any conversations yet
  const conversationList = conversations || [];
  const groups = [];
  const groupsByLabel = new Map();

  // [2] Put each conversation in the group for the day it was last used
  conversationList.forEach((conversation) => {

    const dayDifference = buildDayDifference(new Date(conversation.lastActivity), now);
    const label = buildGroupLabel(dayDifference);

    // [3] Start the group the first time its heading comes up
    if (!groupsByLabel.has(label)) {

      const group = { label, items: [] };

      groupsByLabel.set(label, group);
      groups.push(group);
    }

    groupsByLabel.get(label).items.push(conversation);
  });

  return groups;
}

// Builds the badge for a conversation's status: its words and its classes. Nothing when there is no summary.
export function buildConversationStatus(summary) {

  // [1] Nothing to show without a summary
  if (!summary) return null;

  // [2] An open conversation gets the green badge
  if (summary.status === STATUS_ACTIVE) return { label: LABELS.statusActive, className: STATUS_CLASS_ACTIVE };

  // [3] The others get the plain badge, worded by why they ended
  if (summary.status === STATUS_ARCHIVED) return { label: LABELS.statusArchived, className: STATUS_CLASS };
  if (summary.closeReason === CLOSE_REASON_IDLE_TIMEOUT) return { label: LABELS.statusTimedOut, className: STATUS_CLASS };
  if (summary.closeReason === CLOSE_REASON_MESSAGE_LIMIT || summary.closeReason === CLOSE_REASON_TOKEN_LIMIT) return { label: LABELS.statusLimitReached, className: STATUS_CLASS };

  return { label: LABELS.statusClosed, className: STATUS_CLASS };
}

// Answers whether two Salesforce Ids are the same. An Id arrives as 15 or 18 characters depending on the source, so only the first 15 are compared.
export function isSameId(first, second) {

  // [1] A missing Id is never the same
  if (!first || !second) return false;

  // [2] Compare the first 15 characters
  const firstStart = String(first).slice(0, ID_COMPARE_LENGTH);
  const secondStart = String(second).slice(0, ID_COMPARE_LENGTH);

  return firstStart === secondStart;
}

// Writes the small line under a conversation's title: who started it, the agent and the number of messages.
export function buildMetaLabel(conversation) {

  // [1] Write the number of messages
  const messagesLabel = LABELS.messagesCount.replace(COUNT_PLACEHOLDER, conversation.messageCount);

  // [2] Start with the owner when someone else started it
  const ownerLabel = conversation.ownerName ? `${conversation.ownerName}${META_SEPARATOR}` : "";

  // [3] Use the agent's name, or the app's name when there is none
  const agentLabel = conversation.agentName || LABELS.appName;

  return `${ownerLabel}${agentLabel}${META_SEPARATOR}${messagesLabel}`;
}

// Keeps the conversations whose title or agent contains what the user typed. All of them when the search is blank.
export function buildFilteredConversations(conversations, searchTerm) {

  // [1] Tidy what the user typed
  const term = (searchTerm || "").trim().toLowerCase();
  const conversationList = conversations || [];

  // [2] A blank search keeps everything
  if (!term) return conversationList;

  // [3] Keep the conversations that match
  const filteredConversations = conversationList.filter((conversation) => {

    const searchableText = `${conversation.title} ${conversation.agentName || ""}`.toLowerCase();

    return searchableText.includes(term);
  });

  return filteredConversations;
}

// Builds the groups the template shows: each conversation with its status, date, small line and classes.
export function buildGroupViews(conversations, currentConversationId, now = new Date()) {

  // [1] Group the conversations by day
  const groups = buildConversationGroups(conversations, now);
  const groupViews = [];

  // [2] Build a view for each conversation in each group
  groups.forEach((group) => {

    const items = group.items.map((conversation) => {

      const isCurrent = isSameId(conversation.id, currentConversationId);
      const status = buildConversationStatus(conversation);
      const showStatus = !!status && status.label !== LABELS.statusClosed;

      return { ...conversation, status, showStatus, dateLabel: formatHistoryDate(conversation.lastActivity, now), metaLabel: buildMetaLabel(conversation), className: isCurrent ? ROW_CLASS_CURRENT : ROW_CLASS, titleClass: isCurrent ? TITLE_CLASS_CURRENT : TITLE_CLASS };
    });

    groupViews.push({ ...group, items });
  });

  return groupViews;
}
