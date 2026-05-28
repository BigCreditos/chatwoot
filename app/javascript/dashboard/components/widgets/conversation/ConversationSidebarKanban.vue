<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { KanbanConfigHelper } from '../../../routes/dashboard/kanban/helpers/kanbanConfig';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true
  }
});

const { t } = useI18n();
const store = ref(useStore());

// Configuration and state fields
const fullConfig = ref({ pipelines: [] });
const activePipelineId = ref(null);
const activeStageId = ref(null);
const priorityValue = ref('');
const dueDateValue = ref('');

// Computed conversation properties
const conversation = computed(() => {
  return store.value.getters['conversations/getConversation'](props.conversationId) || {};
});

// Mapped labels for active conversation
const savedLabels = computed(() => {
  return store.value.getters['conversationLabels/getConversationLabels'](props.conversationId) || [];
});

const activePipeline = computed(() => {
  return fullConfig.value.pipelines.find(p => p.id === activePipelineId.value) || null;
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

const detectConversationPipeline = () => {
  const labels = savedLabels.value;
  
  // Find which pipeline and stage matches the conversation's active labels
  for (const pipeline of fullConfig.value.pipelines) {
    for (const stage of pipeline.stages) {
      if (labels.includes(stage.label)) {
        activePipelineId.value = pipeline.id;
        activeStageId.value = stage.id;
        return;
      }
    }
  }

  // Fallback to first pipeline if none matches
  if (fullConfig.value.pipelines.length > 0) {
    activePipelineId.value = fullConfig.value.pipelines[0].id;
  }
  activeStageId.value = null;
};

// Sync inputs from conversation properties
const syncConversationData = () => {
  if (!conversation.value) return;

  priorityValue.value = conversation.value.priority || conversation.value.custom_attributes?.priority || '';
  
  const dVal = conversation.value.custom_attributes?.due_date || '';
  if (dVal) {
    // Format YYYY-MM-DD for standard date input
    dueDateValue.value = new Date(dVal).toISOString().split('T')[0];
  } else {
    dueDateValue.value = '';
  }
};

onMounted(() => {
  loadPipelineConfig();
  syncConversationData();
});

// Watchers for reactive sync
watch(() => props.conversationId, () => {
  detectConversationPipeline();
  syncConversationData();
});

watch(savedLabels, () => {
  detectConversationPipeline();
});

watch(conversation, () => {
  syncConversationData();
}, { deep: true });

// Actions
const onPipelineChange = () => {
  activeStageId.value = null;
};

const onStageChange = async () => {
  if (!activePipeline.value) return;
  
  const selectedStage = activePipeline.value.stages.find(s => s.id === activeStageId.value);
  const currentLabels = [...savedLabels.value];
  const allStagesLabels = activePipeline.value.stages.map(s => s.label);

  // Strip other stage labels
  const cleanLabels = currentLabels.filter(lbl => !allStagesLabels.includes(lbl));

  if (selectedStage) {
    cleanLabels.push(selectedStage.label);

    // Apply native stage automations
    handleStageAutomations(selectedStage);
  }

  try {
    await store.value.dispatch('conversationLabels/update', {
      conversationId: props.conversationId,
      labels: cleanLabels
    });
  } catch (err) {
    console.error('Failed to update stage label:', err);
  }
};

const updatePriority = async () => {
  const p = priorityValue.value === '' ? null : priorityValue.value;
  try {
    await store.value.dispatch('conversations/assignPriority', {
      conversationId: props.conversationId,
      priority: p
    });
  } catch (err) {
    console.error('Failed to assign priority:', err);
  }
};

const updateDueDate = async () => {
  const dVal = dueDateValue.value;
  const currentCustomAttributes = { ...(conversation.value.custom_attributes || {}) };
  
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
      customAttributes: currentCustomAttributes
    });
  } catch (err) {
    console.error('Failed to update due date custom attribute:', err);
  }
};

const handleResolve = async () => {
  try {
    await store.value.dispatch('conversations/toggleStatus', {
      conversationId: props.conversationId,
      status: 'resolved'
    });
  } catch (err) {
    console.error('Failed to resolve conversation from sidebar:', err);
  }
};

// Automations processor when moving stage
const handleStageAutomations = async (stage) => {
  const automations = activePipeline.value.automations || {};
  
  // 1. Auto resolve when dragging to a won/lost column
  if (automations.auto_resolve_on_won_lost && (stage.is_won || stage.is_lost)) {
    try {
      await store.value.dispatch('conversations/toggleStatus', {
        conversationId: props.conversationId,
        status: 'resolved'
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
    const onlineAgents = allAgents.filter(a => a.availability_status === 'online');
    const eligibleAgents = agentsList.length > 0 
      ? onlineAgents.filter(a => agentsList.includes(a.id)) 
      : onlineAgents;

    if (eligibleAgents.length > 0) {
      // Pick random or first eligible agent
      const agentToAssign = eligibleAgents[Math.floor(Math.random() * eligibleAgents.length)];
      try {
        await store.value.dispatch('conversations/assignAgent', {
          conversationId: props.conversationId,
          agentId: agentToAssign.id
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
      <label class="text-[10px] uppercase font-bold tracking-wider text-slate-500">
        {{ t('KANBAN.SIDEBAR.PIPELINE') }}
      </label>
      <select
        v-model="activePipelineId"
        class="w-full px-3 py-2 rounded-lg border border-slate-800 bg-slate-950 text-slate-200 text-xs focus:border-blue-500 outline-none"
        @change="onPipelineChange"
      >
        <option v-for="pipeline in fullConfig.pipelines" :key="pipeline.id" :value="pipeline.id">
          {{ pipeline.name }}
        </option>
      </select>
    </div>

    <!-- Stage dropdown -->
    <div v-if="activePipeline" class="flex flex-col gap-1">
      <label class="text-[10px] uppercase font-bold tracking-wider text-slate-500">
        {{ t('KANBAN.SIDEBAR.STAGE') }}
      </label>
      <select
        v-model="activeStageId"
        class="w-full px-3 py-2 rounded-lg border border-slate-800 bg-slate-950 text-slate-200 text-xs focus:border-blue-500 outline-none"
        @change="onStageChange"
      >
        <option :value="null">
          -- {{ t('KANBAN.SIDEBAR.NOT_IN_PIPELINE') }} --
        </option>
        <option v-for="stage in activePipeline.stages" :key="stage.id" :value="stage.id">
          {{ stage.title }}
        </option>
      </select>
    </div>

    <!-- Priority and Due Date Row -->
    <div class="grid grid-cols-2 gap-3">
      <!-- Priority -->
      <div class="flex flex-col gap-1">
        <label class="text-[10px] uppercase font-bold tracking-wider text-slate-500">
          {{ t('KANBAN.SIDEBAR.PRIORITY') }}
        </label>
        <select
          v-model="priorityValue"
          class="w-full px-3 py-2 rounded-lg border border-slate-800 bg-slate-950 text-slate-200 text-xs focus:border-blue-500 outline-none"
          @change="updatePriority"
        >
          <option value="">Nenhuma</option>
          <option value="urgent">Urgente</option>
          <option value="high">Alta</option>
          <option value="medium">Média</option>
          <option value="low">Baixa</option>
        </select>
      </div>

      <!-- Due Date -->
      <div class="flex flex-col gap-1">
        <label class="text-[10px] uppercase font-bold tracking-wider text-slate-500">
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
        Resolver Conversa
      </button>

      <!-- Already resolved indicator -->
      <div
        v-else
        class="w-full py-2 px-3 rounded-lg border border-slate-800 bg-slate-950 text-slate-500 text-xs font-semibold text-center flex items-center justify-center gap-1.5"
      >
        <Icon icon="i-lucide-check" class="size-4 shrink-0" />
        Atendimento Resolvido
      </div>
    </div>
  </div>
</template>
