<script setup>
import { computed } from 'vue';
import { MESSAGE_TYPE } from 'widget/helpers/constants';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
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
  multiLine: {
    type: Boolean,
    default: false,
  },
});

const { getPlainText } = useMessageFormatter();

const attachmentIcons = {
  image: 'i-lucide-image',
  audio: 'i-lucide-headphones',
  video: 'i-lucide-video',
  file: 'i-lucide-file',
  location: 'i-lucide-map-pin',
  fallback: 'i-lucide-link-2',
};

const messageByAgent = computed(() => {
  const { message_type: messageType } = props.message;
  return messageType === MESSAGE_TYPE.OUTGOING;
});

const isMessageAnActivity = computed(() => {
  const { message_type: messageType } = props.message;
  return messageType === MESSAGE_TYPE.ACTIVITY;
});

const isMessagePrivate = computed(() => {
  const { private: isPrivate } = props.message;
  return isPrivate;
});

const parsedLastMessage = computed(() => {
  const { content_attributes: contentAttributes } = props.message;
  const { email: { subject } = {} } = contentAttributes || {};
  return getPlainText(subject || props.message.content);
});

const lastMessageFileType = computed(() => {
  const { attachments = [] } = props.message;
  if (attachments.length > 0) {
    return attachments[0].file_type;
  }
  return props.message.content_type;
});

const attachmentIcon = computed(() => {
  return attachmentIcons[lastMessageFileType.value] || 'i-lucide-paperclip';
});

const attachmentMessageContent = computed(() => {
  const type = lastMessageFileType.value;
  if (['image', 'audio', 'video', 'file', 'location'].includes(type)) {
    return `CHAT_LIST.ATTACHMENTS.${type}.CONTENT`;
  }
  return null;
});

const isAudio = computed(() => lastMessageFileType.value === 'audio');

const isMessageSticker = computed(() => {
  return props.message && props.message.content_type === 'sticker';
});
</script>

<template>
  <div
    class="min-w-0 text-sm"
    :class="
      multiLine
        ? 'flex items-start gap-1'
        : 'grid grid-cols-[auto_1fr] items-center gap-1'
    "
  >
    <template v-if="showMessageType && !multiLine">
      <Icon
        v-if="isMessagePrivate"
        icon="i-lucide-lock-keyhole"
        class="size-3.5"
      />
      <Icon
        v-else-if="messageByAgent"
        icon="i-lucide-undo-2"
        class="size-3.5"
      />
      <Icon
        v-else-if="isMessageAnActivity"
        icon="i-lucide-info"
        class="size-3.5"
      />
    </template>

    <span
      class="min-w-0 text-body-main"
      :class="multiLine ? 'line-clamp-2' : 'truncate'"
    >
      <!-- Case for previous and conversation conversation card -->
      <template v-if="showMessageType && multiLine">
        <Icon
          v-if="isMessagePrivate"
          icon="i-lucide-lock-keyhole"
          class="inline-block align-middle size-3.5 ltr:mr-1 rtl:ml-1"
        />
        <Icon
          v-else-if="messageByAgent"
          icon="i-lucide-undo-2"
          class="inline-block align-middle size-3.5 ltr:mr-1 rtl:ml-1"
        />
        <Icon
          v-else-if="isMessageAnActivity"
          icon="i-lucide-info"
          class="inline-block align-middle size-3.5 ltr:mr-1 rtl:ml-1"
        />
      </template>
      <span
        v-if="message.content && isMessageSticker"
        class="inline-grid grid-flow-col auto-cols-max items-center gap-1"
      >
        <Icon icon="i-lucide-image" class="size-3.5" />
        {{ $t('CHAT_LIST.ATTACHMENTS.image.CONTENT') }}
      </span>

      <template v-else-if="message.content">
        {{ parsedLastMessage }}
      </template>

      <span
        v-else-if="attachmentMessageContent"
        class="inline-block align-middle truncate"
        :class="{ 'text-n-blue-11': isAudio }"
      >
        <Icon
          v-if="attachmentIcon && showMessageType"
          :icon="attachmentIcon"
          class="inline-block align-middle size-3.5 ltr:mr-1 rtl:ml-1"
        />
        <span class="inline-block align-middle">
          {{ $t(attachmentMessageContent) }}
        </span>
      </span>

      <template v-else>
        {{ defaultEmptyMessage || $t('CHAT_LIST.NO_CONTENT') }}
      </template>
    </span>
  </div>
</template>
