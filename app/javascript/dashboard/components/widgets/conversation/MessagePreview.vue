<script>
import { MESSAGE_TYPE } from 'widget/helpers/constants';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { ATTACHMENT_ICONS } from 'shared/constants/messages';

export default {
  name: 'MessagePreview',
  props: {
    message: {
      type: Object,
      required: true,
    },
    showMessageType: {
      type: Boolean,
      default: true,
    },
    defaultEmptyMessage: {
      type: String,
      default: '',
    },
  },
  setup() {
    const { getPlainText } = useMessageFormatter();
    return {
      getPlainText,
    };
  },
  computed: {
    messageByAgent() {
      const { message_type: messageType } = this.message;
      return messageType === MESSAGE_TYPE.OUTGOING;
    },
    isMessageAnActivity() {
      const { message_type: messageType } = this.message;
      return messageType === MESSAGE_TYPE.ACTIVITY;
    },
    isMessagePrivate() {
      const { private: isPrivate } = this.message;
      return isPrivate;
    },
    parsedLastMessage() {
      const { content_attributes: contentAttributes } = this.message;
      const { email: { subject } = {} } = contentAttributes || {};
      return this.getPlainText(subject || this.message.content);
    },
    lastMessageFileType() {
      const attachments = this.message.attachments || [];
      if (attachments.length > 0) {
        const attachment = attachments[0];
        const type = attachment.file_type || attachment.fileType;
        return type ? type.toString().toLowerCase() : null;
      }
      const contentType = this.message.content_type || this.message.contentType;
      return contentType ? contentType.toString().toLowerCase() : null;
    },
    attachmentIcon() {
      return ATTACHMENT_ICONS[this.lastMessageFileType] || 'attach';
    },
    attachmentMessageContent() {
      const type = this.lastMessageFileType;
      if (
        [
          'image',
          'audio',
          'video',
          'file',
          'location',
          'voice',
          '1', // Audio enum value as string
          'contact',
          'fallback',
        ].includes(type)
      ) {
        const isVoiceOrAudio =
          type === 'voice' || type === 'audio' || type === '1';
        const translationType = isVoiceOrAudio ? 'audio' : type;
        return `CHAT_LIST.ATTACHMENTS.${translationType}.CONTENT`;
      }
      return null;
    },
    isAudio() {
      const type = this.lastMessageFileType;
      return type === 'audio' || type === 'voice' || type === '1';
    },
    isMessageSticker() {
      return this.message && this.message.content_type === 'sticker';
    },
  },
};
</script>

<template>
  <div class="overflow-hidden text-ellipsis whitespace-nowrap">
    <template v-if="showMessageType">
      <fluent-icon
        v-if="isMessagePrivate"
        size="16"
        class="-mt-0.5 align-middle text-n-slate-11 inline-block"
        icon="lock-closed"
      />
      <fluent-icon
        v-else-if="messageByAgent"
        size="16"
        class="-mt-0.5 align-middle text-n-slate-11 inline-block"
        icon="arrow-reply"
      />
      <fluent-icon
        v-else-if="isMessageAnActivity"
        size="16"
        class="-mt-0.5 align-middle text-n-slate-11 inline-block"
        icon="info"
      />
    </template>
    <span v-if="isMessageSticker">
      <fluent-icon
        size="16"
        class="-mt-0.5 align-middle inline-block text-n-slate-11"
        icon="image"
      />
      {{ $t('CHAT_LIST.ATTACHMENTS.image.CONTENT') }}
    </span>
    <span v-else-if="message.content">
      {{ parsedLastMessage }}
    </span>
    <span
      v-else-if="attachmentMessageContent"
      :class="{ 'text-n-blue-11': isAudio }"
    >
      <fluent-icon
        v-if="attachmentIcon && showMessageType"
        size="16"
        class="-mt-0.5 align-middle inline-block"
        :class="isAudio ? 'text-n-blue-11' : 'text-n-slate-11'"
        :icon="attachmentIcon"
      />
      {{ $t(attachmentMessageContent) }}
    </span>
    <span v-else>
      {{ defaultEmptyMessage || $t('CHAT_LIST.NO_CONTENT') }}
    </span>
  </div>
</template>
