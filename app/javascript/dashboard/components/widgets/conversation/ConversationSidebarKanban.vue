<script setup>
/* eslint-disable no-console, no-use-before-define, no-restricted-syntax */
import { computed, ref, onMounted, watch } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { KanbanConfigHelper } from '../../../routes/dashboard/kanban/helpers/kanbanConfig';
import ConversationApi from '../../../api/conversations';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const { t } = useI18n();
const store = ref(useStore());

const allAgents = computed(() => store.value.getters['agents/getAgents'] || []);

// Configuration and state fields
const fullConfig = ref({ pipelines: [] });
const activePipelineId = ref(null);
const activeStageId = ref(null);
const priorityValue = ref('');
const dueDateValue = ref('');
const activeAgentId = ref('');

// Computed conversation properties
const conversation = computed(() => {
  return (
    store.value.getters.getConversationById(
      props.conversationId
    ) || {}
  );
});

// Detect which pipeline stage the conversation currently occupies
const detectConversationPipeline = () => {
  const kanbanStage = conversation.value.kanban_stage;

  for (const pipeline of fullConfig.value.pipelines) {
    const match = pipeline.stages.find(s => s.id === kanbanStage);
    if (match) {
      activePipelineId.value = pipeline.id;
      activeStageId.value = match.id;
      return;
    }
  }

  // Fallback to first pipeline if none matches
  if (fullConfig.value.pipelines.length > 0) {
    activePipelineId.value = fullConfig.value.pipelines[0].id;
  }
  activeStageId.value = null;
};

const activePipeline = computed(() => {
  return (
    fullConfig.value.pipelines.find(p => p.id === activePipelineId.value) ||
    null
  );
});

// Fetch active config and load inputs
const loadPipelineConfig = async () => {
  try {
    const { config } = await KanbanConfigHelper.loadConfig(store.value);
    fullConfig.value = config;

    // Detect if conversation is already in a pipeline stage
    detectConversationPipeline();
  } catch (err) {
    console.error('Failed to load Kanban config for sidebar:', err);
  }
};

// Sync inputs from conversation properties
const syncConversationData = () => {
  if (!conversation.value) return;

  priorityValue.value =
    conversation.value.priority ||
    conversation.value.custom_attributes?.priority ||
    '';

  const dVal = conversation.value.custom_attributes?.due_date || '';
  if (dVal) {
    dueDateValue.value = new Date(dVal).toISOString().split('T')[0];
  } else {
    dueDateValue.value = '';
  }

  activeAgentId.value = conversation.value.meta?.assignee?.id || '';
};

onMounted(() => {
  loadPipelineConfig();
  syncConversationData();
});

// Watchers for reactive sync
watch(
  () => props.conversationId,
  () => {
    detectConversationPipeline();
    syncConversationData();
  }
);

watch(
  conversation,
  () => {
    syncConversationData();
  },
  { deep: true }
);

// Actions
const onPipelineChange = () => {
  activeStageId.value = null;
};

const selectStage = async stage => {
  if (!activePipeline.value) return;

  activeStageId.value = stage ? stage.id : null;

  try {
    await ConversationApi.update(props.conversationId, {
      kanban_stage: stage ? stage.id : null,
    });
    store.value.dispatch('updateConversation', {
      id: props.conversationId,
      kanban_stage: stage ? stage.id : null,
    });

    if (stage) {
      handleStageAutomations(stage);
    }
  } catch (err) {
    console.error('Failed to update stage:', err);
  }
};

const updatePriority = async () => {
  const p = priorityValue.value === '' ? null : priorityValue.value;
  try {
    await store.value.dispatch('conversations/assignPriority', {
      conversationId: props.conversationId,
      priority: p,
    });
  } catch (err) {
    console.error('Failed to assign priority:', err);
  }
};

const updateDueDate = async () => {
  const dVal = dueDateValue.value;
  const currentCustomAttributes = {
    ...(conversation.value.custom_attributes || {}),
  };

  if (dVal) {
    // Set to local midnight of selected day
    const localDate = new Date(dVal + 'T00:00:00');
    currentCustomAttributes.due_date = localDate.toISOString();
  } else {
    delete currentCustomAttributes.due_date;
  }

  try {
    await store.value.dispatch('conversations/updateCustomAttributes', {
      conversationId: props.conversationId,
      customAttributes: currentCustomAttributes,
    });
  } catch (err) {
    console.error('Failed to update due date custom attribute:', err);
  }
};

const updateAgent = async () => {
  const id = activeAgentId.value ? Number(activeAgentId.value) : null;
  if (!id) return;
  try {
    await store.value.dispatch('conversations/assignAgent', {
      conversationId: props.conversationId,
      agentId: id,
    });
  } catch (err) {
    console.error('Failed to assign agent:', err);
  }
};

const handleResolve = async () => {
  try {
    await store.value.dispatch('conversations/toggleStatus', {
      conversationId: props.conversationId,
      status: 'resolved',
    });
  } catch (err) {
    console.error('Failed to resolve conversation from sidebar:', err);
  }
};

// Automations processor when moving stage
const handleStageAutomations = async stage => {
  const automations = activePipeline.value.automations || {};

  // 1. Auto resolve when dragging to a won/lost column
  if (automations.auto_resolve_on_won_lost && (stage.is_won || stage.is_lost)) {
    try {
      await store.value.dispatch('conversations/toggleStatus', {
        conversationId: props.conversationId,
        status: 'resolved',
      });
    } catch (err) {
      console.error('Failed to auto-resolve on stage change:', err);
    }
  }

  // 2. Auto assign unassigned cards to online agent
  if (automations.auto_assign_agent && !conversation.value.meta?.assignee) {
    const agentsList = activePipeline.value.agents || [];
    const allAgents = store.value.getters['agents/getAgents'] || [];

    // Find active agents (online)
    const onlineAgents = allAgents.filter(
      a => a.availability_status === 'online'
    );
    const eligibleAgents =
      agentsList.length > 0
        ? onlineAgents.filter(a => agentsList.includes(a.id))
        : onlineAgents;

    if (eligibleAgents.length > 0) {
      // Pick random or first eligible agent
      const agentToAssign =
        eligibleAgents[Math.floor(Math.random() * eligibleAgents.length)];
      try {
        await store.value.dispatch('conversations/assignAgent', {
          conversationId: props.conversationId,
          agentId: agentToAssign.id,
        });
      } catch (err) {
        console.error('Failed to auto-assign agent:', err);
      }
    }
  }
};
</script>

<template>
  <div class="flex flex-col gap-3 py-2 px-1 text-slate-200">
    <!-- Pipeline dropdown -->
    <div class="flex flex-col gap-1">
      <label
        class="text-[10px] uppercase font-bold tracking-wider text-slate-500"
      >
        {{ t('KANBAN.SIDEBAR.PIPELINE') }}
      </label>
      <select
        v-model="activePipelineId"
        class="w-full px-3 py-2 rounded-lg border border-slate-800 bg-slate-950 text-slate-200 text-xs focus:border-blue-500 outline-none"
        @change="onPipelineChange"
      >
        <option
          v-for="pipeline in fullConfig.pipelines"
          :key="pipeline.id"
          :value="pipeline.id"
        >
          {{ pipeline.name }}
        </option>
      </select>
    </div>

    <!-- Stage visual buttons -->
    <div v-if="activePipeline" class="flex flex-col gap-1.5">
      <label
        class="text-[10px] uppercase font-bold tracking-wider text-slate-500"
      >
        {{ t('KANBAN.SIDEBAR.STAGE') }}
      </label>
      <div class="flex flex-wrap gap-1.5">
        <!-- Remove from pipeline button -->
        <button
          type="button"
          class="flex items-center gap-1 px-2.5 py-1.5 rounded-lg border text-[11px] font-semibold transition-all"
          :class="
            activeStageId === null
              ? 'border-slate-600 bg-slate-800 text-slate-200'
              : 'border-slate-800 bg-slate-950 text-slate-400 hover:border-slate-700 hover:text-slate-300'
          "
          @click="selectStage(null)"
        >
          <Icon icon="i-lucide-x" class="size-3" />
          {{ t('KANBAN.SIDEBAR.NOT_IN_PIPELINE') }}
        </button>
        <!-- Stage colored buttons -->
        <button
          v-for="stage in activePipeline.stages"
          :key="stage.id"
          type="button"
          class="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg border text-[11px] font-semibold transition-all"
          :class="
            activeStageId === stage.id
              ? 'border-slate-600 bg-slate-800 text-slate-200'
              : 'border-slate-800 bg-slate-950 text-slate-400 hover:border-slate-700 hover:text-slate-300'
          "
          @click="selectStage(stage)"
        >
          <span
            class="size-2 rounded-full shrink-0"
            :style="{ backgroundColor: stage.color || '#3b82f6' }"
          />
          {{ stage.title }}
        </button>
      </div>
    </div>

    <!-- Priority and Due Date Row -->
    <div class="grid grid-cols-2 gap-3">
      <!-- Priority -->
      <div class="flex flex-col gap-1">
        <label
          class="text-[10px] uppercase font-bold tracking-wider text-slate-500"
        >
          {{ t('KANBAN.SIDEBAR.PRIORITY') }}
        </label>
        <select
          v-model="priorityValue"
          class="w-full px-3 py-2 rounded-lg border border-slate-800 bg-slate-950 text-slate-200 text-xs focus:border-blue-500 outline-none"
          @change="updatePriority"
        >
          <option value="">{{ t('KANBAN.SIDEBAR.PRIORITY_NONE') }}</option>
          <option value="urgent">
            {{ t('KANBAN.CARD.PRIORITIES.URGENT') }}
          </option>
          <option value="high">{{ t('KANBAN.CARD.PRIORITIES.HIGH') }}</option>
          <option value="medium">
            {{ t('KANBAN.CARD.PRIORITIES.MEDIUM') }}
          </option>
          <option value="low">{{ t('KANBAN.CARD.PRIORITIES.LOW') }}</option>
        </select>
      </div>

      <!-- Due Date -->
      <div class="flex flex-col gap-1">
        <label
          class="text-[10px] uppercase font-bold tracking-wider text-slate-500"
        >
          {{ t('KANBAN.SIDEBAR.DUE_DATE') }}
        </label>
        <input
          v-model="dueDateValue"
          type="date"
          class="w-full px-3 py-1.5 rounded-lg border border-slate-800 bg-slate-950 text-slate-200 text-xs focus:border-blue-500 outline-none"
          @change="updateDueDate"
        />
      </div>
    </div>

    <!-- Agent selector -->
    <div class="flex flex-col gap-1">
      <label
        class="text-[10px] uppercase font-bold tracking-wider text-slate-500"
      >
        {{ t('KANBAN.SIDEBAR.AGENT') }}
      </label>
      <select
        v-model="activeAgentId"
        class="w-full px-3 py-2 rounded-lg border border-slate-800 bg-slate-950 text-slate-200 text-xs focus:border-blue-500 outline-none"
        @change="updateAgent"
      >
        <option value="">{{ t('KANBAN.SIDEBAR.NO_AGENT') }}</option>
        <option
          v-for="agent in allAgents"
          :key="agent.id"
          :value="agent.id"
        >
          {{ agent.name }}
        </option>
      </select>
    </div>

    <!-- Quick Actions -->
    <div class="flex items-center gap-2 pt-2">
      <!-- Quick Resolve -->
      <button
        v-if="conversation.status !== 'resolved'"
        type="button"
        class="w-full py-2 px-3 rounded-lg border border-emerald-500/20 bg-emerald-500/10 text-emerald-400 text-xs font-semibold hover:bg-emerald-500/20 transition-all flex items-center justify-center gap-1.5"
        @click="handleResolve"
      >
        <Icon icon="i-lucide-check-circle" class="size-4 shrink-0" />
        {{ t('KANBAN.SIDEBAR.RESOLVE_CONVERSATION') }}
      </button>

      <!-- Already resolved indicator -->
      <div
        v-else
        class="w-full py-2 px-3 rounded-lg border border-slate-800 bg-slate-950 text-slate-500 text-xs font-semibold text-center flex items-center justify-center gap-1.5"
      >
        <Icon icon="i-lucide-check" class="size-4 shrink-0" />
        {{ t('KANBAN.SIDEBAR.CONVERSATION_RESOLVED') }}
      </div>
    </div>
  </div>
</template>
