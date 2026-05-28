<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ScheduleDateShortcuts from './ScheduleDateShortcuts.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  inboxId: {
    type: Number,
    default: undefined,
  },
});

const { t } = useI18n();
const store = useStore();
const scheduledTime = ref(null);
const messageContent = ref('');
const dateTimeError = ref('');
const isScheduling = ref(false);

const isValid = computed(() => {
  return scheduledTime.value && messageContent.value.trim();
});

const currentUserId = computed(() => store.getters.getCurrentUser?.id);

const scheduleMessage = async () => {
  if (!isValid.value) return;

  isScheduling.value = true;
  try {
    await store.dispatch('messages/create', {
      conversationId: props.conversationId,
      message: {
        content: messageContent.value.trim(),
        scheduled_at: scheduledTime.value.toISOString(),
      },
    });
    messageContent.value = '';
    scheduledTime.value = null;
    useAlert(t('SCHEDULED_MESSAGES.SCHEDULE_SUCCESS'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('SCHEDULED_MESSAGES.SCHEDULE_ERROR')
    );
  } finally {
    isScheduling.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-3 p-2">
    <label class="text-xs font-medium text-n-slate-11">
      {{ t('SCHEDULED_MESSAGES.CONTENT_LABEL') }}
    </label>
    <textarea
      v-model="messageContent"
      :placeholder="t('SCHEDULED_MESSAGES.CONTENT_PLACEHOLDER')"
      class="w-full px-3 py-2 text-sm border rounded-lg resize-none border-n-weak bg-n-base text-n-slate-12 focus:border-n-brand focus:outline-none"
      rows="3"
    />
    <ScheduleDateShortcuts
      v-model="scheduledTime"
      :date-time-error="dateTimeError"
    />
    <button
      type="button"
      :disabled="!isValid || isScheduling"
      class="w-full py-2 px-4 text-sm font-medium text-white rounded-lg bg-n-brand hover:bg-n-brand-hover disabled:opacity-50 disabled:cursor-not-allowed"
      @click="scheduleMessage"
    >
      {{ t('SCHEDULED_MESSAGES.SCHEDULE_BUTTON') }}
    </button>
  </div>
</template>
