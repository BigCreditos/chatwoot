<script setup>
/* eslint-disable no-console, no-restricted-globals, no-alert */
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useRouter, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Thumbnail from 'dashboard/components/widgets/Thumbnail.vue';

// Custom Kanban Components
import KanbanCard from './components/KanbanCard.vue';
import PipelineSettingsModal from './components/PipelineSettingsModal.vue';

// Config Storage Helper
import { KanbanConfigHelper } from './helpers/kanbanConfig';

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const route = useRoute();

// State fields
const fullConfig = ref({ pipelines: [] });
const activePipelineId = ref(null);
const configLabelId = ref(null);
const searchQuery = ref('');
const pipelineSearchQuery = ref('');
const filterAgentId = ref('');
const filterInboxId = ref('');

// Modals
const showSettingsModal = ref(false);
const activeEditingPipeline = ref(null);
const showAddCardPopoverId = ref(null); // ID of the column where "+ Adicionar tarefa" is open

// Load core Chatwoot resources
const allAgents = computed(() => store.getters['agents/getAgents'] || []);
const allInboxes = computed(() => store.getters['inboxes/getInboxes'] || []);
const allConversations = computed(
  () => store.getters['conversations/getAllConversations'] || []
);

// Active pipeline
const activePipeline = computed(() => {
  return (
    fullConfig.value.pipelines.find(p => p.id === activePipelineId.value) ||
    null
  );
});

// Load configs from special Label
const loadKanbanConfig = async () => {
  try {
    const { labelId, config } = await KanbanConfigHelper.loadConfig(store);
    fullConfig.value = config;
    configLabelId.value = labelId;

    const queryPipelineId = Number(route.query.pipeline_id);
    if (
      queryPipelineId &&
      config.pipelines.some(p => p.id === queryPipelineId)
    ) {
      activePipelineId.value = queryPipelineId;
    } else {
      activePipelineId.value = null;
    }
  } catch (err) {
    console.error('Failed to load Kanban configurations:', err);
  }
};

watch(
  () => route.query.pipeline_id,
  newId => {
    const parsedId = Number(newId);
    if (parsedId && fullConfig.value.pipelines.some(p => p.id === parsedId)) {
      activePipelineId.value = parsedId;
    } else {
      activePipelineId.value = null;
    }
  }
);

// Overview Helper Methods
const selectPipeline = pipeline => {
  router.push({
    name: 'kanban_dashboard',
    query: { pipeline_id: pipeline.id },
  });
};

const getStageLeadsCount = stage => {
  return allConversations.value.filter(c => c.labels?.includes(stage.label))
    .length;
};

const getPipelineTotalLeads = pipeline => {
  let count = 0;
  pipeline.stages.forEach(stage => {
    count += getStageLeadsCount(stage);
  });
  return count;
};

const filteredPipelines = computed(() => {
  if (!pipelineSearchQuery.value.trim()) return fullConfig.value.pipelines;
  const q = pipelineSearchQuery.value.toLowerCase().trim();
  return fullConfig.value.pipelines.filter(
    p =>
      p.name.toLowerCase().includes(q) ||
      (p.description || '').toLowerCase().includes(q)
  );
});

const getPipelineUniqueAgents = pipeline => {
  const pipelineConversations = allConversations.value.filter(c =>
    pipeline.stages.some(stage => c.labels?.includes(stage.label))
  );
  const agentsMap = new Map();
  pipelineConversations.forEach(c => {
    const assignee = c.meta?.assignee;
    if (assignee && assignee.id) {
      agentsMap.set(assignee.id, assignee);
    }
  });
  return Array.from(agentsMap.values());
};

onMounted(() => {
  // Ensure Chatwoot memory is populated
  store.dispatch('conversations/fetchAllConversations');
  store.dispatch('labels/get');
  store.dispatch('inboxes/get');
  store.dispatch('agents/get');

  loadKanbanConfig();
});

// Filtered conversations based on Search, Agent, and Inbox select
const filteredConversations = computed(() => {
  let chats = [...allConversations.value];

  // 1. Text Search (ID, customer name, message text)
  if (searchQuery.value.trim()) {
    const q = searchQuery.value.toLowerCase().trim();
    chats = chats.filter(c => {
      const name = (c.meta?.sender?.name || '').toLowerCase();
      const lastMsg = (
        c.last_non_activity_message?.content || ''
      ).toLowerCase();
      const dispId = String(c.display_id || c.id);
      return name.includes(q) || lastMsg.includes(q) || dispId.includes(q);
    });
  }

  // 2. Agent Filter
  if (filterAgentId.value) {
    const agentIdNum = Number(filterAgentId.value);
    chats = chats.filter(c => c.meta?.assignee?.id === agentIdNum);
  }

  // 3. Inbox Filter
  if (filterInboxId.value) {
    const inboxIdNum = Number(filterInboxId.value);
    chats = chats.filter(c => c.inbox_id === inboxIdNum);
  }

  return chats;
});

// Vue Draggable lists map
const columnsCardsMap = ref({});

const syncColumns = () => {
  if (!activePipeline.value) return;

  const newMap = {};
  activePipeline.value.stages.forEach(stage => {
    newMap[stage.id] = [];
  });

  // Distribute filtered conversations into stages
  filteredConversations.value.forEach(conversation => {
    // A conversation can only reside in one stage's label per active pipeline
    const matchedStage = activePipeline.value.stages.find(s =>
      conversation.labels?.includes(s.label)
    );
    if (matchedStage) {
      newMap[matchedStage.id].push(conversation);
    }
  });

  columnsCardsMap.value = newMap;
};

// Sync lists when chats or active pipeline modifies
watch(
  [filteredConversations, activePipeline],
  () => {
    syncColumns();
  },
  { deep: true, immediate: true }
);

// Drag and drop changes handler
const onCardDragChange = async (event, targetStage) => {
  if (event.added) {
    const conversation = event.added.element;
    const currentLabels = [...(conversation.labels || [])];
    const allStagesLabels = activePipeline.value.stages.map(s => s.label);

    // Remove any label matching any stage in this pipeline
    const cleanLabels = currentLabels.filter(
      lbl => !allStagesLabels.includes(lbl)
    );

    // Add target stage's label
    cleanLabels.push(targetStage.label);

    try {
      await store.dispatch('conversationLabels/update', {
        conversationId: conversation.id,
        labels: cleanLabels,
      });

      // 1. Auto resolve when dragging to a won/lost column
      if (
        activePipeline.value.automations?.auto_resolve_on_won_lost &&
        (targetStage.is_won || targetStage.is_lost)
      ) {
        await store.dispatch('conversations/toggleStatus', {
          conversationId: conversation.id,
          status: 'resolved',
        });
      }
    } catch (err) {
      console.error('Failed to update stage label via drag:', err);
    }
  }
};

// Navigation to conversation detail
const openConversation = conversationId => {
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: store.getters.getCurrentAccountId,
      conversationId: conversationId,
    },
  });
};

// Quick Resolve action inside the card
const resolveConversation = async conversationId => {
  try {
    await store.dispatch('conversations/toggleStatus', {
      conversationId,
      status: 'resolved',
    });
  } catch (err) {
    console.error('Failed to resolve conversation:', err);
  }
};

// Open Modals for Pipeline management
const openAddPipeline = () => {
  activeEditingPipeline.value = null;
  showSettingsModal.value = true;
};

const openEditPipeline = () => {
  activeEditingPipeline.value = activePipeline.value;
  showSettingsModal.value = true;
};

const closeSettingsModal = () => {
  showSettingsModal.value = false;
  activeEditingPipeline.value = null;
};

// Save edited pipeline
const savePipelineConfig = async updatedPipeline => {
  showSettingsModal.value = false;

  const pipelines = [...fullConfig.value.pipelines];
  const existingIndex = pipelines.findIndex(p => p.id === updatedPipeline.id);

  if (existingIndex > -1) {
    pipelines[existingIndex] = updatedPipeline;
  } else {
    pipelines.push(updatedPipeline);
  }

  const newConfig = { pipelines };

  try {
    // 1. Save serialized JSON into hidden label description
    await KanbanConfigHelper.saveConfig(store, configLabelId.value, newConfig);

    // 2. Ensure mapped labels exist natively in the account
    await KanbanConfigHelper.ensureMappedLabelsExist(store, updatedPipeline);

    // Re-fetch config to refresh states
    await loadKanbanConfig();
    activePipelineId.value = updatedPipeline.id;
  } catch (err) {
    console.error('Failed to save pipeline configuration:', err);
  }
};

// Delete active pipeline
const deleteActivePipeline = async () => {
  if (!activePipeline.value) return;

  const isConfirmed = confirm(t('KANBAN.SETTINGS.DELETE_CONFIRM'));
  if (!isConfirmed) return;

  showSettingsModal.value = false;

  const remainingPipelines = fullConfig.value.pipelines.filter(
    p => p.id !== activePipeline.value.id
  );
  const newConfig = { pipelines: remainingPipelines };

  try {
    await KanbanConfigHelper.saveConfig(store, configLabelId.value, newConfig);
    await loadKanbanConfig();

    if (fullConfig.value.pipelines.length > 0) {
      activePipelineId.value = fullConfig.value.pipelines[0].id;
    } else {
      activePipelineId.value = null;
    }
  } catch (err) {
    console.error('Failed to delete pipeline:', err);
  }
};

// Filter recent conversations that have NO label belonging to this pipeline stages
const eligibleConversationsForInclusion = computed(() => {
  if (!activePipeline.value) return [];

  const allStagesLabels = activePipeline.value.stages.map(s => s.label);
  return allConversations.value.filter(c => {
    // Must NOT have any label from this pipeline
    const hasPipelineLabel = c.labels?.some(lbl =>
      allStagesLabels.includes(lbl)
    );
    // Status must not be resolved
    const isOpen = c.status !== 'resolved';
    return !hasPipelineLabel && isOpen;
  });
});

// Add task quick action: immediately assigns the conversation to the first stage
const addConversationToStage = async (conversation, stage) => {
  showAddCardPopoverId.value = null;
  const currentLabels = [...(conversation.labels || [])];
  currentLabels.push(stage.label);

  try {
    await store.dispatch('conversationLabels/update', {
      conversationId: conversation.id,
      labels: currentLabels,
    });
  } catch (err) {
    console.error('Failed to add conversation to stage:', err);
  }
};
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text -->
  <div
    class="flex flex-col w-full h-full bg-slate-950 font-sans overflow-hidden"
  >
    <!-- 1. Funis Overview (Visão geral) when activePipelineId is null -->
    <div
      v-if="activePipelineId === null"
      class="flex-grow flex flex-col h-full bg-slate-950 p-8 overflow-y-auto"
    >
      <!-- Overview Header -->
      <div
        class="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-4 mb-8 shrink-0"
      >
        <h2 class="text-2xl font-bold tracking-tight text-slate-100 shrink-0">
          Funis
        </h2>

        <div class="flex items-center gap-3">
          <!-- Search Input -->
          <div class="relative">
            <input
              v-model="pipelineSearchQuery"
              type="text"
              placeholder="Buscar funis..."
              class="w-56 pl-9 pr-3 py-2 rounded-xl border border-slate-800 bg-slate-900 text-slate-200 text-xs focus:border-blue-500 outline-none placeholder:text-slate-500"
            />
            <span class="absolute left-3 top-2.5 text-slate-500">
              <Icon icon="i-lucide-search" class="size-3.5" />
            </span>
          </div>

          <Button
            blue
            class="flex items-center gap-1.5 px-4 py-2 text-sm font-semibold rounded-xl shrink-0"
            @click="openAddPipeline"
          >
            <Icon icon="i-lucide-plus" class="size-4" />
            Adicionar Funil
          </Button>
        </div>
      </div>

      <!-- Funnels List -->
      <div class="flex flex-col gap-5 max-w-5xl">
        <div
          v-for="p in filteredPipelines"
          :key="p.id"
          class="bg-slate-900/60 hover:bg-slate-900 border border-slate-850 hover:border-slate-800 rounded-2xl p-6 transition-all cursor-pointer flex flex-col gap-4 shadow-lg hover:shadow-2xl"
          @click="selectPipeline(p)"
        >
          <!-- Pipeline Header Info -->
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <span class="text-lg font-bold text-slate-200">{{ p.name }}</span>
              <span
                class="px-2.5 py-0.5 rounded-full bg-slate-950 text-xs font-semibold text-slate-400 border border-slate-800"
              >
                {{ getPipelineTotalLeads(p) }}
              </span>
            </div>

            <!-- Agent / Inbox placeholder avatars (from the pipeline or active leads) -->
            <div class="flex items-center -space-x-2">
              <Thumbnail
                v-for="agent in getPipelineUniqueAgents(p).slice(0, 4)"
                :key="agent.id"
                :src="agent.thumbnail"
                :username="agent.name"
                size="26px"
                class="border-2 border-slate-900 rounded-full shrink-0"
              />
              <span
                v-if="getPipelineUniqueAgents(p).length > 4"
                class="size-[26px] rounded-full border-2 border-slate-900 bg-slate-950 text-[10px] font-bold text-slate-400 flex items-center justify-center shrink-0 z-10"
              >
                +{{ getPipelineUniqueAgents(p).length - 4 }}
              </span>
            </div>
          </div>

          <!-- Stages Summary Horizontal Bar -->
          <div class="flex flex-wrap gap-2.5">
            <div
              v-for="stage in p.stages"
              :key="stage.id"
              class="bg-slate-950/70 px-3.5 py-1.5 rounded-full text-xs font-semibold text-slate-300 flex items-center gap-2 border border-slate-850"
            >
              <span
                class="size-2 rounded-full"
                :style="{ backgroundColor: stage.color || '#3b82f6' }"
              />
              <span>{{ stage.title }}</span>
              <span class="text-slate-500 font-bold ml-0.5">{{
                getStageLeadsCount(stage)
              }}</span>
            </div>
          </div>
        </div>

        <div
          v-if="filteredPipelines.length === 0"
          class="flex flex-col items-center justify-center py-20 text-center gap-4 bg-slate-900/20 border border-dashed border-slate-850 rounded-2xl"
        >
          <div class="p-4 bg-slate-900/60 rounded-full text-slate-500">
            <Icon icon="i-lucide-folder-open" class="size-8" />
          </div>
          <div class="flex flex-col gap-1 max-w-sm">
            <h3 class="text-sm font-bold text-slate-300">
              Nenhum funil configurado
            </h3>
            <p class="text-xs text-slate-500 font-medium">
              Crie seu primeiro funil para gerenciar leads, propostas e
              fechamento comercial de forma visual.
            </p>
          </div>
          <Button blue small class="mt-2" @click="openAddPipeline">
            <Icon icon="i-lucide-plus" class="size-3.5" />
            Adicionar Funil
          </Button>
        </div>
      </div>
    </div>

    <!-- 2. Kanban Board (when activePipelineId is NOT null) -->
    <template v-else>
      <!-- Header Top Section -->
      <header
        class="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-4 px-6 py-4 border-b border-slate-900 bg-slate-950 shrink-0"
      >
        <!-- Title & Pipelines Selector -->
        <div class="flex items-center gap-3">
          <h2 class="text-xl font-bold tracking-tight text-slate-100 shrink-0">
            {{ t('KANBAN.HEADER.TITLE') }}
          </h2>

          <!-- Pipeline Select Dropdown -->
          <div
            v-if="fullConfig.pipelines.length > 0"
            class="flex items-center gap-1.5"
          >
            <select
              v-model="activePipelineId"
              class="px-3.5 py-1.5 rounded-lg border border-slate-800 bg-slate-900 text-slate-200 text-sm font-semibold outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500 cursor-pointer min-w-[160px]"
            >
              <option
                v-for="p in fullConfig.pipelines"
                :key="p.id"
                :value="p.id"
              >
                {{ p.name }}
              </option>
            </select>

            <!-- Edit pipeline settings gear -->
            <button
              type="button"
              class="p-2 border border-slate-850 hover:border-slate-800 hover:bg-slate-900/50 rounded-lg text-slate-400 hover:text-slate-200 transition-all"
              title="Configurações do Funil"
              @click="openEditPipeline"
            >
              <Icon icon="i-lucide-settings" class="size-4 shrink-0" />
            </button>
          </div>

          <!-- Add pipeline button -->
          <Button
            small
            blue
            class="flex items-center gap-1 shrink-0"
            @click="openAddPipeline"
          >
            <Icon icon="i-lucide-plus" class="size-3.5" />
            {{ t('KANBAN.HEADER.ADD_FUNNEL') }}
          </Button>
        </div>

        <!-- Filters & Search Bar -->
        <div class="flex flex-wrap items-center gap-2.5">
          <!-- Live Search Bar -->
          <div class="relative shrink-0 w-full sm:w-60">
            <input
              v-model="searchQuery"
              type="text"
              :placeholder="t('KANBAN.HEADER.SEARCH')"
              class="w-full pl-9 pr-3 py-1.5 rounded-lg border border-slate-800 bg-slate-900 text-slate-200 text-xs focus:border-blue-500 outline-none placeholder:text-slate-500"
            />
            <span class="absolute left-3 top-2.5 text-slate-500">
              <Icon icon="i-lucide-search" class="size-3.5" />
            </span>
          </div>

          <!-- Filter Agents -->
          <select
            v-model="filterAgentId"
            class="px-2.5 py-1.5 rounded-lg border border-slate-800 bg-slate-900 text-slate-300 text-xs outline-none cursor-pointer focus:border-blue-500"
          >
            <option value="">-- {{ t('KANBAN.HEADER.ALL_AGENTS') }} --</option>
            <option
              v-for="agent in allAgents"
              :key="agent.id"
              :value="agent.id"
            >
              {{ agent.name }}
            </option>
          </select>

          <!-- Filter Inboxes -->
          <select
            v-model="filterInboxId"
            class="px-2.5 py-1.5 rounded-lg border border-slate-800 bg-slate-900 text-slate-300 text-xs outline-none cursor-pointer focus:border-blue-500"
          >
            <option value="">-- {{ t('KANBAN.HEADER.ALL_INBOXES') }} --</option>
            <option
              v-for="inbox in allInboxes"
              :key="inbox.id"
              :value="inbox.id"
            >
              {{ inbox.name }}
            </option>
          </select>
        </div>
      </header>

      <!-- Draggable Stage Board Columns -->
      <main class="flex-grow flex gap-4 p-6 overflow-x-auto overflow-y-hidden">
        <!-- Stage Column -->
        <div
          v-for="stage in activePipeline?.stages"
          :key="stage.id"
          class="group/col flex flex-col w-[272px] shrink-0 bg-slate-900/40 border border-slate-900 rounded-2xl overflow-hidden hover:border-slate-850 transition"
        >
          <!-- Column Header Info -->
          <div
            class="flex items-center justify-between px-4 py-3 bg-slate-900/60 border-b border-slate-900/40 shrink-0"
          >
            <div class="flex items-center gap-2 min-w-0">
              <!-- Colored Column Bullet with Glow -->
              <span
                class="size-2.5 rounded-full shrink-0"
                :style="{
                  backgroundColor: stage.color || '#3b82f6',
                  filter: 'drop-shadow(0 0 6px ' + (stage.color || '#3b82f6') + ')',
                }"
              />
              <span class="text-xs font-bold text-slate-200 truncate">{{
                stage.title
              }}</span>
            </div>

            <div class="flex items-center gap-1">
              <!-- Total Leads Counter Badge -->
              <span
                class="px-2 py-0.5 rounded-full bg-slate-950 text-[10px] font-bold text-slate-400 border border-slate-800"
              >
                {{ columnsCardsMap[stage.id]?.length || 0 }}
              </span>

              <!-- More options button -->
              <button
                type="button"
                class="p-1 rounded-lg text-slate-500 hover:text-slate-300 hover:bg-slate-800 transition-colors opacity-0 group-hover/col:opacity-100"
                title="Mais opções"
              >
                <Icon icon="i-lucide-ellipsis" class="size-3.5" />
              </button>
            </div>
          </div>

          <!-- Draggable Cards Container -->
          <div
            class="flex-1 overflow-y-auto px-3.5 py-4 scrollbar-thin scrollbar-thumb-slate-800 scrollbar-track-transparent"
          >
            <Draggable
              v-model="columnsCardsMap[stage.id]"
              group="kanban-conversations"
              item-key="id"
              animation="200"
              ghost-class="bg-slate-950/40 border-dashed border-slate-700 opacity-60 scale-[0.98] rounded-xl"
              drag-class="scale-105 rotate-1 opacity-90 shadow-2xl rounded-xl z-50 cursor-grabbing"
              class="flex flex-col gap-3.5 min-h-[300px] h-full"
              @change="onCardDragChange($event, stage)"
            >
              <template #item="{ element }">
                <KanbanCard
                  :conversation="element"
                  @click="openConversation"
                  @resolve="resolveConversation"
                />
              </template>
            </Draggable>
          </div>

          <!-- "+ Adicionar tarefa" Button & Popover -->
          <div class="p-3 border-t border-slate-900/40 shrink-0 relative">
            <button
              type="button"
              class="w-full py-2 px-3 hover:bg-slate-900/50 rounded-lg text-slate-400 hover:text-slate-200 text-xs font-semibold flex items-center justify-center gap-1.5 transition-colors border border-slate-900"
              @click="
                showAddCardPopoverId =
                  showAddCardPopoverId === stage.id ? null : stage.id
              "
            >
              <Icon icon="i-lucide-plus" class="size-4 shrink-0" />
              {{ t('KANBAN.HEADER.ADD_TASK') }}
            </button>

            <!-- Add lead popover drop list -->
            <div
              v-if="showAddCardPopoverId === stage.id"
              class="absolute bottom-12 left-2 right-2 flex flex-col max-h-56 bg-slate-900 border border-slate-800 rounded-xl shadow-2xl overflow-y-auto py-1.5 z-40 animate-in fade-in slide-in-from-bottom-2"
            >
              <div
                class="px-3 py-1.5 border-b border-slate-800 text-[10px] uppercase font-bold text-slate-500"
              >
                Chats recentes sem funil
              </div>

              <button
                v-for="conv in eligibleConversationsForInclusion"
                :key="conv.id"
                type="button"
                class="px-3 py-2 text-left hover:bg-slate-800 text-slate-200 transition-colors flex items-center gap-2"
                @click="addConversationToStage(conv, stage)"
              >
                <Thumbnail
                  :src="conv.meta?.sender?.thumbnail"
                  :username="conv.meta?.sender?.name || 'Cliente'"
                  size="20px"
                  class="shrink-0"
                />
                <div class="flex flex-col min-w-0">
                  <span class="text-xs font-semibold truncate">{{
                    conv.meta?.sender?.name || 'Cliente'
                  }}</span>
                  <span class="text-[9px] text-slate-500 font-mono"
                    >#{{ conv.display_id || conv.id }}</span
                  >
                </div>
              </button>

              <div
                v-if="eligibleConversationsForInclusion.length === 0"
                class="px-4 py-6 text-center text-xs text-slate-500 font-medium leading-relaxed"
              >
                Nenhuma conversa recente elegível encontrada.
              </div>
            </div>
          </div>
        </div>
      </main>
    </template>

    <!-- Pipeline Configurations Settings Modal -->
    <PipelineSettingsModal
      v-if="showSettingsModal"
      :is-open="showSettingsModal"
      :pipeline="activeEditingPipeline"
      :label-id="configLabelId"
      :full-config="fullConfig"
      @close="closeSettingsModal"
      @save="savePipelineConfig"
      @delete="deleteActivePipeline"
    />
  </div>
</template>
