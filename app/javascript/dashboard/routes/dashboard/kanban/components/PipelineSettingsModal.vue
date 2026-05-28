<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  isOpen: {
    type: Boolean,
    required: true
  },
  pipeline: {
    type: Object,
    default: null
  },
  labelId: {
    type: [Number, String],
    default: null
  },
  fullConfig: {
    type: Object,
    required: true
  }
});

const emit = defineEmits(['close', 'save']);

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

// Form states
const pipelineId = ref(null);
const name = ref('');
const description = ref('');
const stages = ref([]);
const inboxes = ref([]);
const agents = ref([]);
const automations = ref({
  auto_create: false,
  auto_assign_agent: false,
  auto_assign_conversation: false,
  auto_resolve_on_won_lost: false,
  auto_win_on_resolve: false
});

// Load lists from store
const allInboxes = computed(() => store.getters['inboxes/getInboxes'] || []);
const allAgents = computed(() => store.getters['agents/getAgents'] || []);
const allLabels = computed(() => store.getters['labels/getLabels'] || []);

onMounted(() => {
  // Fetch required dependencies
  store.dispatch('inboxes/get');
  store.dispatch('agents/get');
  store.dispatch('labels/get');

  if (props.pipeline) {
    // Editing existing pipeline
    pipelineId.value = props.pipeline.id;
    name.value = props.pipeline.name || '';
    description.value = props.pipeline.description || '';
    stages.value = JSON.parse(JSON.stringify(props.pipeline.stages || []));
    inboxes.value = Array.isArray(props.pipeline.inboxes) ? [...props.pipeline.inboxes] : [];
    agents.value = Array.isArray(props.pipeline.agents) ? [...props.pipeline.agents] : [];
    automations.value = {
      auto_create: false,
      auto_assign_agent: false,
      auto_assign_conversation: false,
      auto_resolve_on_won_lost: false,
      auto_win_on_resolve: false,
      ...(props.pipeline.automations || {})
    };
  } else {
    // New pipeline
    pipelineId.value = Date.now();
    name.value = '';
    description.value = '';
    stages.value = [
      { id: 'st_1', title: 'Novo Lead', label: 'Novo Lead', color: '#3b82f6' },
      { id: 'st_2', title: 'Qualificando', label: 'Qualificando', color: '#f59e0b' },
      { id: 'st_3', title: 'Proposta Enviada', label: 'Proposta Enviada', color: '#8b5cf6' },
      { id: 'st_4', title: 'Negociação', label: 'Negociação', color: '#f97316' },
      { id: 'st_5', title: 'Oportunidade Perdida', label: 'Oportunidade Perdida', color: '#ef4444', is_lost: true },
      { id: 'st_6', title: 'Oportunidade Ganha', label: 'Oportunidade Ganha', color: '#10b981', is_won: true }
    ];
    inboxes.value = [];
    agents.value = [];
    automations.value = {
      auto_create: false,
      auto_assign_agent: false,
      auto_assign_conversation: false,
      auto_resolve_on_won_lost: false,
      auto_win_on_resolve: false
    };
  }
});

// Stage management actions
const addStage = () => {
  const newId = `st_${Date.now()}`;
  stages.value.push({
    id: newId,
    title: `Etapa ${stages.value.length + 1}`,
    label: `Etapa ${stages.value.length + 1}`,
    color: '#3b82f6'
  });
};

const removeStage = (index) => {
  stages.value.splice(index, 1);
};

const moveStageUp = (index) => {
  if (index === 0) return;
  const temp = stages.value[index];
  stages.value[index] = stages.value[index - 1];
  stages.value[index - 1] = temp;
};

const moveStageDown = (index) => {
  if (index === stages.value.length - 1) return;
  const temp = stages.value[index];
  stages.value[index] = stages.value[index + 1];
  stages.value[index + 1] = temp;
};

const toggleWon = (index) => {
  stages.value[index].is_won = !stages.value[index].is_won;
  if (stages.value[index].is_won) stages.value[index].is_lost = false;
};

const toggleLost = (index) => {
  stages.value[index].is_lost = !stages.value[index].is_lost;
  if (stages.value[index].is_lost) stages.value[index].is_won = false;
};

// Toggle selections for inboxes & agents
const toggleInbox = (id) => {
  const index = inboxes.value.indexOf(id);
  if (index > -1) {
    inboxes.value.splice(index, 1);
  } else {
    inboxes.value.push(id);
  }
};

const toggleAgent = (id) => {
  const index = agents.value.indexOf(id);
  if (index > -1) {
    agents.value.splice(index, 1);
  } else {
    agents.value.push(id);
  }
};

const handleSave = () => {
  if (!name.value.trim()) return;

  const updatedPipeline = {
    id: pipelineId.value,
    name: name.value.trim(),
    description: description.value.trim(),
    stages: stages.value.map(s => ({
      ...s,
      title: s.title.trim(),
      label: s.label.trim()
    })),
    inboxes: inboxes.value,
    agents: agents.value,
    automations: automations.value
  };

  emit('save', updatedPipeline);
};
</script>

<template>
  <div
    v-if="isOpen"
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-sm"
  >
    <div
      class="flex flex-col w-full max-w-4xl h-[85vh] border bg-slate-900 border-slate-800 rounded-2xl shadow-2xl overflow-hidden animate-in fade-in zoom-in-95 duration-200"
    >
      <!-- Header -->
      <div class="flex items-center justify-between px-6 py-4 border-b border-slate-800">
        <h3 class="text-lg font-semibold text-slate-100 flex items-center gap-2">
          <Icon icon="i-lucide-settings" class="text-blue-500 size-5" />
          {{ t('KANBAN.SETTINGS.TITLE') }}
        </h3>
        <button
          type="button"
          class="p-1.5 text-slate-400 hover:text-slate-200 rounded-lg hover:bg-slate-800 transition-colors"
          @click="emit('close')"
        >
          <Icon icon="i-lucide-x" class="size-5" />
        </button>
      </div>

      <!-- Content Grid -->
      <div class="flex-1 overflow-y-auto px-6 py-6 space-y-8">
        <!-- Basic Info Section -->
        <div class="space-y-4">
          <h4 class="text-sm font-medium uppercase tracking-wider text-slate-400">
            {{ t('KANBAN.SETTINGS.BASIC_INFO') }}
          </h4>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div class="space-y-1.5">
              <label class="text-xs font-semibold text-slate-300">
                {{ t('KANBAN.SETTINGS.FUNNEL_NAME') }} *
              </label>
              <input
                v-model="name"
                type="text"
                class="w-full px-3.5 py-2.5 rounded-lg border border-slate-700 bg-slate-950 text-slate-200 text-sm focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none"
                placeholder="Ex: Pipeline de Vendas"
              />
            </div>
            <div class="space-y-1.5">
              <label class="text-xs font-semibold text-slate-300">
                {{ t('KANBAN.SETTINGS.FUNNEL_DESC') }}
              </label>
              <input
                v-model="description"
                type="text"
                class="w-full px-3.5 py-2.5 rounded-lg border border-slate-700 bg-slate-950 text-slate-200 text-sm focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none"
                placeholder="Breve descrição sobre a finalidade do funil"
              />
            </div>
          </div>
        </div>

        <hr class="border-slate-800" />

        <!-- Stages Section -->
        <div class="space-y-4">
          <div class="flex items-center justify-between">
            <h4 class="text-sm font-medium uppercase tracking-wider text-slate-400">
              {{ t('KANBAN.SETTINGS.STAGES') }}
            </h4>
            <Button
              small
              blue
              solid
              class="flex items-center gap-1.5"
              @click="addStage"
            >
              <Icon icon="i-lucide-plus" class="size-4" />
              {{ t('KANBAN.SETTINGS.ADD_STAGE') }}
            </Button>
          </div>

          <div class="space-y-3">
            <div
              v-for="(stage, index) in stages"
              :key="stage.id"
              class="flex flex-col md:flex-row items-stretch md:items-center gap-3 p-4 rounded-xl border border-slate-800 bg-slate-950/40 hover:bg-slate-950/60 transition-colors"
            >
              <!-- Order actions -->
              <div class="flex items-center md:flex-col justify-between gap-1.5">
                <button
                  type="button"
                  class="p-1 text-slate-500 hover:text-slate-300 disabled:opacity-30"
                  :disabled="index === 0"
                  @click="moveStageUp(index)"
                >
                  <Icon icon="i-lucide-chevron-up" class="size-4 md:size-5" />
                </button>
                <button
                  type="button"
                  class="p-1 text-slate-500 hover:text-slate-300 disabled:opacity-30"
                  :disabled="index === stages.length - 1"
                  @click="moveStageDown(index)"
                >
                  <Icon icon="i-lucide-chevron-down" class="size-4 md:size-5" />
                </button>
              </div>

              <!-- Title & Mapping -->
              <div class="flex-1 grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div class="space-y-1">
                  <label class="text-[10px] uppercase font-bold tracking-wider text-slate-500">
                    {{ t('KANBAN.SETTINGS.STAGE_NAME') }}
                  </label>
                  <input
                    v-model="stage.title"
                    type="text"
                    class="w-full px-3 py-1.5 rounded-md border border-slate-700 bg-slate-900 text-slate-200 text-xs focus:border-blue-500 outline-none"
                  />
                </div>
                <div class="space-y-1">
                  <label class="text-[10px] uppercase font-bold tracking-wider text-slate-500">
                    {{ t('KANBAN.SETTINGS.STAGE_LABEL') }} (Chatwoot Label)
                  </label>
                  <input
                    v-model="stage.label"
                    type="text"
                    list="available-labels-list"
                    class="w-full px-3 py-1.5 rounded-md border border-slate-700 bg-slate-900 text-slate-200 text-xs focus:border-blue-500 outline-none"
                  />
                </div>
              </div>

              <!-- Color picker -->
              <div class="space-y-1 min-w-[70px]">
                <label class="text-[10px] uppercase font-bold tracking-wider text-slate-500 block">
                  {{ t('KANBAN.SETTINGS.STAGE_COLOR') }}
                </label>
                <div class="flex items-center gap-1.5">
                  <input
                    v-model="stage.color"
                    type="color"
                    class="w-8 h-8 rounded border border-slate-700 bg-slate-900 cursor-pointer overflow-hidden p-0"
                  />
                  <span class="text-xs text-slate-400 font-mono uppercase">{{ stage.color }}</span>
                </div>
              </div>

              <!-- Status configuration (Won/Lost) -->
              <div class="flex items-center gap-2 pt-4 md:pt-0">
                <button
                  type="button"
                  class="px-2.5 py-1.5 rounded-md border text-xs font-semibold flex items-center gap-1 transition-all"
                  :class="stage.is_won 
                    ? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-400' 
                    : 'border-slate-800 bg-slate-900 text-slate-400 hover:text-slate-300'"
                  @click="toggleWon(index)"
                >
                  <Icon icon="i-lucide-check-circle" class="size-3.5" />
                  Ganha
                </button>
                <button
                  type="button"
                  class="px-2.5 py-1.5 rounded-md border text-xs font-semibold flex items-center gap-1 transition-all"
                  :class="stage.is_lost 
                    ? 'border-rose-500/30 bg-rose-500/10 text-rose-400' 
                    : 'border-slate-800 bg-slate-900 text-slate-400 hover:text-slate-300'"
                  @click="toggleLost(index)"
                >
                  <Icon icon="i-lucide-x-circle" class="size-3.5" />
                  Perdida
                </button>
              </div>

              <!-- Actions -->
              <div class="flex items-center justify-end md:justify-center">
                <button
                  type="button"
                  class="p-2 text-rose-400 hover:text-rose-300 rounded-lg hover:bg-rose-500/10 transition-colors"
                  @click="removeStage(index)"
                >
                  <Icon icon="i-lucide-trash-2" class="size-4" />
                </button>
              </div>
            </div>
          </div>
        </div>

        <hr class="border-slate-800" />

        <!-- Automations Section -->
        <div class="space-y-4">
          <div class="space-y-1">
            <h4 class="text-sm font-medium uppercase tracking-wider text-slate-400">
              {{ t('KANBAN.SETTINGS.AUTOMATIONS') }}
            </h4>
            <p class="text-xs text-slate-500">
              {{ t('KANBAN.SETTINGS.AUTOMATIONS_HELP') }}
            </p>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <!-- Automation Toggle Cards -->
            <div
              class="flex items-start gap-3 p-4 rounded-xl border border-slate-800 bg-slate-950/20"
            >
              <input
                id="auto-create-toggle"
                v-model="automations.auto_create"
                type="checkbox"
                class="mt-1 size-4 rounded border-slate-700 bg-slate-900 text-blue-500 focus:ring-blue-500 focus:ring-offset-0"
              />
              <div class="space-y-1.5 flex-1">
                <label for="auto-create-toggle" class="text-sm font-medium text-slate-200 cursor-pointer block">
                  {{ t('KANBAN.SETTINGS.AUTO_CREATE') }}
                </label>
                <p class="text-xs text-slate-500">
                  Novas conversas serão colocadas automaticamente na primeira etapa do funil.
                </p>

                <!-- Inbox Selector -->
                <div v-if="automations.auto_create" class="space-y-1.5 pt-2">
                  <label class="text-[10px] uppercase font-bold tracking-wider text-slate-500 block">
                    Filtrar por caixas de entrada (todas se vazio):
                  </label>
                  <div class="flex flex-wrap gap-1.5 max-h-32 overflow-y-auto p-1 border border-slate-850 rounded bg-slate-900">
                    <button
                      v-for="inbox in allInboxes"
                      :key="inbox.id"
                      type="button"
                      class="px-2 py-0.5 rounded text-[10px] font-semibold border transition-all"
                      :class="inboxes.includes(inbox.id)
                        ? 'border-blue-500/30 bg-blue-500/10 text-blue-400'
                        : 'border-slate-800 bg-slate-950 text-slate-400'"
                      @click="toggleInbox(inbox.id)"
                    >
                      {{ inbox.name }}
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <div
              class="flex items-start gap-3 p-4 rounded-xl border border-slate-800 bg-slate-950/20"
            >
              <input
                id="auto-assign-agent-toggle"
                v-model="automations.auto_assign_agent"
                type="checkbox"
                class="mt-1 size-4 rounded border-slate-700 bg-slate-900 text-blue-500 focus:ring-blue-500 focus:ring-offset-0"
              />
              <div class="space-y-1.5 flex-1">
                <label for="auto-assign-agent-toggle" class="text-sm font-medium text-slate-200 cursor-pointer block">
                  {{ t('KANBAN.SETTINGS.AUTO_ASSIGN_AGENT') }}
                </label>
                <p class="text-xs text-slate-500">
                  Cards novos ou sem responsável serão distribuídos entre os agentes selecionados.
                </p>

                <!-- Agent Selector -->
                <div v-if="automations.auto_assign_agent" class="space-y-1.5 pt-2">
                  <label class="text-[10px] uppercase font-bold tracking-wider text-slate-500 block">
                    Agentes elegíveis (todos se vazio):
                  </label>
                  <div class="flex flex-wrap gap-1.5 max-h-32 overflow-y-auto p-1 border border-slate-850 rounded bg-slate-900">
                    <button
                      v-for="agent in allAgents"
                      :key="agent.id"
                      type="button"
                      class="px-2 py-0.5 rounded text-[10px] font-semibold border transition-all"
                      :class="agents.includes(agent.id)
                        ? 'border-blue-500/30 bg-blue-500/10 text-blue-400'
                        : 'border-slate-800 bg-slate-950 text-slate-400'"
                      @click="toggleAgent(agent.id)"
                    >
                      {{ agent.name }}
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <div
              class="flex items-start gap-3 p-4 rounded-xl border border-slate-800 bg-slate-950/20"
            >
              <input
                id="auto-assign-conv-toggle"
                v-model="automations.auto_assign_conversation"
                type="checkbox"
                class="mt-1 size-4 rounded border-slate-700 bg-slate-900 text-blue-500 focus:ring-blue-500 focus:ring-offset-0"
              />
              <div class="space-y-1.5 flex-1">
                <label for="auto-assign-conv-toggle" class="text-sm font-medium text-slate-200 cursor-pointer block">
                  {{ t('KANBAN.SETTINGS.AUTO_ASSIGN_CONV') }}
                </label>
                <p class="text-xs text-slate-500">
                  Ao alterar o atendente do card no Kanban, a conversa no Chatwoot será atribuída automaticamente a ele.
                </p>
              </div>
            </div>

            <div
              class="flex items-start gap-3 p-4 rounded-xl border border-slate-800 bg-slate-950/20"
            >
              <input
                id="auto-resolve-toggle"
                v-model="automations.auto_resolve_on_won_lost"
                type="checkbox"
                class="mt-1 size-4 rounded border-slate-700 bg-slate-900 text-blue-500 focus:ring-blue-500 focus:ring-offset-0"
              />
              <div class="space-y-1.5 flex-1">
                <label for="auto-resolve-toggle" class="text-sm font-medium text-slate-200 cursor-pointer block">
                  {{ t('KANBAN.SETTINGS.AUTO_RESOLVE') }}
                </label>
                <p class="text-xs text-slate-500">
                  Mover o card para uma coluna de Ganho/Perda resolverá a conversa correspondente no Chatwoot.
                </p>
              </div>
            </div>

            <div
              class="flex items-start gap-3 p-4 rounded-xl border border-slate-800 bg-slate-950/20"
            >
              <input
                id="auto-win-toggle"
                v-model="automations.auto_win_on_resolve"
                type="checkbox"
                class="mt-1 size-4 rounded border-slate-700 bg-slate-900 text-blue-500 focus:ring-blue-500 focus:ring-offset-0"
              />
              <div class="space-y-1.5 flex-1">
                <label for="auto-win-toggle" class="text-sm font-medium text-slate-200 cursor-pointer block">
                  {{ t('KANBAN.SETTINGS.AUTO_WIN') }}
                </label>
                <p class="text-xs text-slate-500">
                  Quando um atendente marcar a conversa como resolvida no chat convencional, o card será movido para a etapa de "Ganho".
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Footer Actions -->
      <div class="flex items-center justify-between px-6 py-4 border-t border-slate-800 bg-slate-950/40">
        <div>
          <Button
            v-if="props.pipeline"
            small
            red
            class="flex items-center gap-1.5"
            @click="emit('delete')"
          >
            <Icon icon="i-lucide-trash-2" class="size-4" />
            {{ t('KANBAN.SETTINGS.DELETE') }}
          </Button>
        </div>
        <div class="flex items-center gap-3">
          <Button
            md
            class="border border-slate-700 hover:bg-slate-800 text-slate-300"
            @click="emit('close')"
          >
            Cancelar
          </Button>
          <Button
            md
            blue
            solid
            :disabled="!name.trim()"
            @click="handleSave"
          >
            {{ t('KANBAN.SETTINGS.SAVE') }}
          </Button>
        </div>
      </div>
    </div>
  </div>

  <!-- Available labels list for HTML5 autocomplete -->
  <datalist id="available-labels-list">
    <option v-for="label in allLabels" :key="label.id" :value="label.title" />
  </datalist>
</template>
