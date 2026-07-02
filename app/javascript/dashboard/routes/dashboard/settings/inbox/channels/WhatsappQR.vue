<script setup>
import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Baileys from './Baileys.vue';
import WuzapiWhatsapp from './WuzapiWhatsapp.vue';
import EvolutionGo from './EvolutionGo.vue';
import ChannelSelector from 'dashboard/components/ChannelSelector.vue';

const props = defineProps({
  mode: {
    type: String,
    default: 'create',
    validator: value => ['create', 'convert'].includes(value),
  },
  inbox: {
    type: Object,
    default: null,
  },
});

const isConvertMode = computed(() => props.mode === 'convert');

const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const isLeaving = ref(false);

const PROVIDER_TYPES = {
  BAILEYS: 'baileys',
  WUZAPI: 'wuzapi',
  EVOLUTION_GO: 'evolution_go',
};

const selectedProvider = computed(() => route.query.provider);

const PROVIDER_CATALOG = computed(() => [
  {
    key: PROVIDER_TYPES.BAILEYS,
    title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.BAILEYS'),
    description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.BAILEYS_DESC'),
    icon: 'i-woot-whatsapp',
  },
  {
    key: PROVIDER_TYPES.WUZAPI,
    title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WUZAPI'),
    description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WUZAPI_DESC'),
    icon: 'i-woot-whatsapp',
  },
  {
    key: PROVIDER_TYPES.EVOLUTION_GO,
    title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.EVOLUTION_GO'),
    description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.EVOLUTION_GO_DESC'),
    icon: 'i-woot-whatsapp',
  },
]);

const isValidSelectedProvider = computed(() => {
  if (!selectedProvider.value) return false;
  return PROVIDER_CATALOG.value.some(
    ({ key }) => key === selectedProvider.value
  );
});

const showProviderSelection = computed(
  () => !isLeaving.value && !isValidSelectedProvider.value
);
const showConfiguration = computed(
  () => !isLeaving.value && isValidSelectedProvider.value
);

const selectProvider = providerValue => {
  router.push({
    name: route.name,
    params: route.params,
    query: { provider: providerValue },
  });
};
</script>

<template>
  <div class="overflow-auto col-span-6 p-6 w-full h-full">
    <div v-if="showProviderSelection">
      <div class="mb-10 text-left">
        <h1 class="mb-2 text-lg font-medium text-n-slate-12">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP_QR.SELECT_PROVIDER.TITLE') }}
        </h1>
        <p class="text-sm leading-relaxed text-n-slate-11">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP_QR.SELECT_PROVIDER.DESCRIPTION') }}
        </p>
      </div>

      <div class="flex gap-6 justify-start">
        <ChannelSelector
          v-for="provider in PROVIDER_CATALOG"
          :key="provider.key"
          :title="provider.title"
          :description="provider.description"
          :icon="provider.icon"
          @click="selectProvider(provider.key)"
        />
      </div>
    </div>

    <div v-else-if="showConfiguration">
      <div class="px-6 py-5 rounded-2xl border border-n-weak">
        <Baileys
          v-if="selectedProvider === PROVIDER_TYPES.BAILEYS"
          :mode="mode"
          :inbox="inbox"
        />
        <WuzapiWhatsapp
          v-else-if="selectedProvider === PROVIDER_TYPES.WUZAPI"
          :mode="mode"
          :inbox="inbox"
        />
        <EvolutionGo
          v-else-if="selectedProvider === PROVIDER_TYPES.EVOLUTION_GO"
          :mode="mode"
          :inbox="inbox"
        />
      </div>
    </div>
  </div>
</template>
