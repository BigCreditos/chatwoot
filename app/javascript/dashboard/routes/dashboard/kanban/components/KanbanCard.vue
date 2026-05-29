<script setup>
/* eslint-disable no-console */
import { computed, ref, onMounted, onUnmounted } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Thumbnail from 'dashboard/components/widgets/Thumbnail.vue';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['click', 'resolve']);

const { t } = useI18n();
const store = ref(useStore());

// Hover state
const isHovered = ref(false);
const showPriorityPopover = ref(false);

// Online indicator
const isOnline = computed(() => {
  return (
    props.conversation.meta?.sender?.availability_status === 'online' ||
    props.conversation.meta?.sender?.online === true
  );
});

// Format Creation Time Tooltip
const exactCreationTime = computed(() => {
  const dateVal = props.conversation.created_at || props.conversation.timestamp;
  if (!dateVal) return '';
  const d = new Date(dateVal * 1000 || dateVal);
  return `Criado em ${d.toLocaleDateString('pt-BR')} às ${d.toLocaleTimeString('pt-BR')}`;
});

// Custom timeago formatter (English/Portuguese abbreviated)
const timeAgo = computed(() => {
  const timeVal = props.conversation.created_at || props.conversation.timestamp;
  if (!timeVal) return '';
  const date = new Date(timeVal * 1000 || timeVal);
  const now = new Date();
  const diffMs = now - date;
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMins / 60);
  const diffDays = Math.floor(diffHours / 24);

  if (diffMins < 1) return 'agora';
  if (diffMins < 60) return `${diffMins}m`;
  if (diffHours < 24) return `${diffHours}h`;
  return `${diffDays}d`;
});

// Time badge for card: shows "Atrasado", "Amanhã", or timeago
const timeBadge = computed(() => {
  // First check due date for Atrasado/Amanhã
  const dVal = dueDateValue.value;
  if (dVal) {
    const dueDate = new Date(dVal);
    const today = new Date();
    const dDate = new Date(dueDate.getFullYear(), dueDate.getMonth(), dueDate.getDate());
    const tDate = new Date(today.getFullYear(), today.getMonth(), today.getDate());
    const diffDays = Math.floor((dDate - tDate) / (1000 * 60 * 60 * 24));

    if (diffDays < 0) {
      return {
        label: 'Atrasado',
        class: 'bg-rose-500/10 text-rose-400 border-rose-500/20',
      };
    }
    if (diffDays === 1) {
      return {
        label: 'Amanhã',
        class: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
      };
    }
    if (diffDays === 0) {
      return {
        label: 'Hoje',
        class: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
      };
    }
  }

  // Otherwise show time since creation
  const ta = timeAgo.value;
  if (!ta) return null;
  return {
    label: ta,
    class: 'bg-slate-800 text-slate-400 border-slate-700/50',
  };
});

// Inbox & Channel Helpers
const inboxId = computed(() => props.conversation.inbox_id);
const inbox = computed(() => {
  return store.value.getters['inboxes/getInbox'](inboxId.value) || {};
});

const channelType = computed(() => {
  const ch = props.conversation.meta?.channel || inbox.value.channel_type || '';
  return ch.toLowerCase();
});

// Priority states & helpers
const conversationPriority = computed(() => {
  return (
    props.conversation.priority ||
    props.conversation.custom_attributes?.priority ||
    null
  );
});

const priorityMeta = computed(() => {
  const p = conversationPriority.value;
  switch (p) {
    case 'urgent':
      return {
        label: 'Urgente',
        colorClass: 'bg-rose-500/10 text-rose-400 border-rose-500/30',
        icon: 'i-lucide-alert-triangle',
      };
    case 'high':
      return {
        label: 'Alta',
        colorClass: 'bg-amber-500/10 text-amber-400 border-amber-500/30',
        icon: 'i-lucide-chevron-up',
      };
    case 'medium':
      return {
        label: 'Média',
        colorClass: 'bg-blue-500/10 text-blue-400 border-blue-500/30',
        icon: 'i-lucide-minus',
      };
    case 'low':
      return {
        label: 'Baixa',
        colorClass: 'bg-slate-500/10 text-slate-400 border-slate-700/30',
        icon: 'i-lucide-chevron-down',
      };
    default:
      return null;
  }
});

// Due Date Urgency Logic
const dueDateValue = computed(() => {
  return props.conversation.custom_attributes?.due_date || null;
});

const urgencyMeta = computed(() => {
  const dVal = dueDateValue.value;
  if (!dVal) return null;

  const dueDate = new Date(dVal);
  const today = new Date();

  // Strip time for clean day comparison
  const dDate = new Date(
    dueDate.getFullYear(),
    dueDate.getMonth(),
    dueDate.getDate()
  );
  const tDate = new Date(
    today.getFullYear(),
    today.getMonth(),
    today.getDate()
  );

  const diffDays = Math.floor((dDate - tDate) / (1000 * 60 * 60 * 24));

  if (diffDays < 0) {
    return {
      status: 'overdue',
      label: '⚠️ Vencido',
      badgeClass: 'bg-rose-500/10 text-rose-400 border-rose-500/20',
      borderClass: 'border-rose-500/40 bg-rose-500/[0.02]',
      text: dueDate.toLocaleDateString('pt-BR', {
        day: 'numeric',
        month: 'short',
      }),
    };
  }
  if (diffDays === 0) {
    return {
      status: 'today',
      label: '⚠️ Hoje',
      badgeClass: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
      borderClass: 'border-amber-500/40 bg-amber-500/[0.02]',
      text: 'Hoje',
    };
  }
  return {
    status: 'future',
    label: `📅 ${dueDate.toLocaleDateString('pt-BR', { day: 'numeric', month: 'short' })}`,
    badgeClass: 'bg-slate-800 text-slate-400 border-slate-700/50',
    borderClass: 'border-slate-800',
    text: dueDate.toLocaleDateString('pt-BR', {
      day: 'numeric',
      month: 'short',
    }),
  };
});

// Channel Style Metas
const channelMeta = computed(() => {
  const ch = channelType.value;
  if (ch.includes('whatsapp')) {
    return {
      icon: 'i-lucide-phone',
      color: 'text-emerald-500',
      name: 'WhatsApp',
    };
  }
  if (ch.includes('email')) {
    return { icon: 'i-lucide-mail', color: 'text-cyan-500', name: 'E-mail' };
  }
  if (ch.includes('instagram')) {
    return {
      icon: 'i-lucide-instagram',
      color: 'text-pink-500',
      name: 'Instagram',
    };
  }
  if (ch.includes('facebook')) {
    return {
      icon: 'i-lucide-facebook',
      color: 'text-blue-600',
      name: 'Facebook',
    };
  }
  if (ch.includes('twitter')) {
    return { icon: 'i-lucide-twitter', color: 'text-sky-400', name: 'Twitter' };
  }
  if (ch.includes('telegram')) {
    return { icon: 'i-lucide-send', color: 'text-sky-500', name: 'Telegram' };
  }
  return { icon: 'i-lucide-globe', color: 'text-slate-400', name: 'Web Chat' };
});

// Last message content
const messageSnippet = computed(() => {
  const msg =
    props.conversation.last_non_activity_message ||
    (props.conversation.messages && props.conversation.messages.length > 0
      ? props.conversation.messages[props.conversation.messages.length - 1]
      : null);
  if (!msg) return 'Sem mensagens';
  const cleanContent = msg.content || '';
  return cleanContent.length > 60
    ? cleanContent.substring(0, 60) + '...'
    : cleanContent;
});

// Quick Actions Implementation
const handleResolve = e => {
  e.stopPropagation();
  emit('resolve', props.conversation.id);
};

const updatePriority = async p => {
  showPriorityPopover.value = false;
  try {
    await store.value.dispatch('conversations/assignPriority', {
      conversationId: props.conversation.id,
      priority: p,
    });
  } catch (err) {
    console.error('Failed to assign priority:', err);
  }
};

// Popover closing click outside
const closePopover = () => {
  showPriorityPopover.value = false;
};

// Document click listener for popover
const handleDocumentClick = e => {
  if (
    showPriorityPopover.value &&
    !e.target.closest('.priority-popover-trigger')
  ) {
    closePopover();
  }
};

onMounted(() => {
  document.addEventListener('click', handleDocumentClick);
});

onUnmounted(() => {
  document.removeEventListener('click', handleDocumentClick);
});
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text -->
  <div
    class="group relative flex flex-col p-3.5 rounded-xl border border-slate-800 bg-slate-900 shadow-md hover:shadow-lg transition-all duration-200 cursor-grab active:cursor-grabbing hover:border-slate-700"
    :class="urgencyMeta ? urgencyMeta.borderClass : 'border-slate-800'"
    @mouseenter="isHovered = true"
    @mouseleave="isHovered = false"
    @click="emit('click', props.conversation.id)"
  >
    <!-- Drag Indicator (grip dots, top-left) -->
    <div
      class="absolute top-2 left-2 text-slate-600 opacity-0 group-hover:opacity-100 transition-opacity duration-150"
    >
      <Icon icon="i-lucide-grip-vertical" class="size-3.5" />
    </div>

    <!-- Card Header: Online Indicator + Thumbnail + Name/ID | Channel -->
    <div
      class="flex items-start justify-between w-full gap-2"
      :class="{ 'pl-4': true }"
    >
      <div class="flex items-center gap-2.5">
        <!-- Avatar with Online Indicator -->
        <div class="relative shrink-0">
          <Thumbnail
            :src="props.conversation.meta?.sender?.thumbnail"
            :username="props.conversation.meta?.sender?.name || 'Cliente'"
            size="28px"
            class="shrink-0"
          />
          <span
            v-if="isOnline"
            class="absolute -bottom-0.5 -right-0.5 size-2.5 rounded-full bg-emerald-500 border-2 border-slate-900"
          />
        </div>
        <div class="flex flex-col min-w-0">
          <span
            class="text-xs font-semibold text-slate-200 truncate"
          >
            {{ props.conversation.meta?.sender?.name || 'Cliente' }}
          </span>
          <span class="text-[10px] text-slate-500 font-medium">
            #{{ props.conversation.display_id || props.conversation.id }}
          </span>
        </div>
      </div>

      <!-- Channel Brand Icon -->
      <span
        v-if="channelMeta"
        :class="[channelMeta.color]"
        :title="channelMeta.name"
        class="shrink-0 p-1 bg-slate-950/40 rounded-lg"
      >
        <Icon :icon="channelMeta.icon" class="size-3.5" />
      </span>
    </div>

    <!-- Message Snippet -->
    <p
      class="mt-2 text-xs text-slate-400 font-normal leading-relaxed break-words line-clamp-2 min-h-[28px]"
    >
      {{ messageSnippet }}
    </p>

    <!-- Badges Row: Time badge + Priority + Snooze -->
    <div class="flex flex-wrap items-center gap-1.5 mt-2.5">
      <!-- Time Badge (Atrasado / Amanhã / 55m) -->
      <span
        v-if="timeBadge"
        :class="[timeBadge.class]"
        class="px-2 py-0.5 rounded text-[10px] font-semibold border"
      >
        {{ timeBadge.label }}
      </span>

      <!-- Priority Badge -->
      <span
        v-if="priorityMeta"
        :class="[priorityMeta.colorClass]"
        class="px-2 py-0.5 rounded text-[10px] font-semibold border flex items-center gap-1"
      >
        <Icon :icon="priorityMeta.icon" class="size-3 shrink-0" />
        {{ priorityMeta.label }}
      </span>

      <!-- Snooze status -->
      <span
        v-if="props.conversation.status === 'snoozed'"
        class="px-2 py-0.5 rounded text-[10px] font-semibold border border-purple-500/20 bg-purple-500/10 text-purple-400 flex items-center gap-1"
      >
        <Icon icon="i-lucide-clock" class="size-3 shrink-0" />
        {{ t('KANBAN.CARD.SNOOZED') }}
      </span>
    </div>

    <!-- Card Footer: Inbox + Assignee (compact, no timeago) -->
    <div
      class="flex items-center justify-between mt-3 pt-2.5 border-t border-slate-800/40"
    >
      <!-- Inbox Badge -->
      <span
        v-if="inbox && inbox.name"
        class="px-1.5 py-0.5 bg-slate-950/60 border border-slate-800 text-[9px] text-slate-400 font-medium rounded truncate max-w-[180px]"
        :title="inbox.name"
      >
        {{ inbox.name }}
      </span>
      <span v-else class="text-[9px] text-slate-600">—</span>

      <!-- Assignee Thumbnail -->
      <Thumbnail
        v-if="props.conversation.meta?.assignee"
        :src="props.conversation.meta?.assignee?.thumbnail"
        :username="props.conversation.meta?.assignee?.name || 'Agente'"
        size="16px"
        class="shrink-0 ring-1 ring-slate-800"
        :title="props.conversation.meta?.assignee?.name"
      />
      <!-- Unassigned Placeholder -->
      <div
        v-else
        class="w-[16px] h-[16px] rounded-full bg-slate-950 flex items-center justify-center border border-dashed border-slate-800 shrink-0 cursor-pointer"
        :title="t('KANBAN.CARD.NO_ASSIGNEE')"
      >
        <Icon icon="i-lucide-user" class="text-slate-600 size-2" />
      </div>
    </div>

    <!-- Hover Hover Actions (Overlay) -->
    <div
      v-if="isHovered"
      class="absolute top-2 right-2 flex items-center gap-1.5 bg-slate-900 border border-slate-700 shadow-md px-1.5 py-1 rounded-lg z-20 transition-all duration-150"
      @click.stop
    >
      <!-- Quick Priority Selector trigger -->
      <div class="relative priority-popover-trigger">
        <button
          type="button"
          class="p-1 hover:bg-slate-800 rounded text-slate-400 hover:text-slate-200 transition-colors"
          title="Alterar Prioridade"
          @click.stop="showPriorityPopover = !showPriorityPopover"
        >
          <Icon icon="i-lucide-flag" class="size-3.5" />
        </button>

        <!-- Popover list -->
        <div
          v-if="showPriorityPopover"
          class="absolute top-7 right-0 flex flex-col min-w-[100px] bg-slate-900 border border-slate-800 shadow-xl rounded-lg overflow-hidden py-1 z-30 animate-in fade-in slide-in-from-top-1"
        >
          <button
            type="button"
            class="px-3 py-1.5 text-xs text-left font-medium text-rose-400 hover:bg-slate-800 transition-colors flex items-center gap-1.5"
            @click="updatePriority('urgent')"
          >
            <Icon icon="i-lucide-alert-triangle" class="size-3" />
            Urgente
          </button>
          <button
            type="button"
            class="px-3 py-1.5 text-xs text-left font-medium text-amber-400 hover:bg-slate-800 transition-colors flex items-center gap-1.5"
            @click="updatePriority('high')"
          >
            <Icon icon="i-lucide-chevron-up" class="size-3" />
            Alta
          </button>
          <button
            type="button"
            class="px-3 py-1.5 text-xs text-left font-medium text-blue-400 hover:bg-slate-800 transition-colors flex items-center gap-1.5"
            @click="updatePriority('medium')"
          >
            <Icon icon="i-lucide-minus" class="size-3" />
            Média
          </button>
          <button
            type="button"
            class="px-3 py-1.5 text-xs text-left font-medium text-slate-400 hover:bg-slate-800 transition-colors flex items-center gap-1.5"
            @click="updatePriority('low')"
          >
            <Icon icon="i-lucide-chevron-down" class="size-3" />
            Baixa
          </button>
          <button
            type="button"
            class="px-3 py-1.5 text-xs text-left font-medium text-slate-500 hover:bg-slate-800 border-t border-slate-850 transition-colors"
            @click="updatePriority(null)"
          >
            Nenhuma
          </button>
        </div>
      </div>

      <!-- Quick Resolve (✔) Button -->
      <button
        type="button"
        class="p-1 hover:bg-emerald-500/10 rounded text-slate-400 hover:text-emerald-400 transition-colors"
        title="Resolver Conversa"
        @click.stop="handleResolve"
      >
        <Icon icon="i-lucide-check" class="size-3.5" />
      </button>
    </div>
  </div>
</template>
