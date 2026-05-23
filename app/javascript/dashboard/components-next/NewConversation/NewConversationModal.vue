<script setup>
import { ref, reactive, computed, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import ContactAPI from 'dashboard/api/contacts';
import { DuplicateContactException } from 'shared/helpers/CustomErrors';
import { debounce } from '@chatwoot/utils';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';

const emit = defineEmits(['close']);

const store = useStore();
const router = useRouter();
const { locale } = useI18n();

// Computed Portuguese detector
const isPortuguese = computed(() => {
  const code = (locale.value || '').toLowerCase();
  return code.startsWith('pt');
});

// Dynamic Localizer mapping
const t = key => {
  const translations = {
    modalTitle: isPortuguese.value
      ? 'Nova Conversa (Novo Contato)'
      : 'New Conversation (New Contact)',
    contactNameLabel: isPortuguese.value
      ? 'Nome do Contato (Opcional)'
      : 'Contact Name (Optional)',
    contactNamePlaceholder: isPortuguese.value
      ? 'Ex: Maria da Silva'
      : 'e.g. Jane Doe',
    phoneNumberLabel: isPortuguese.value
      ? 'Número de Telefone (Obrigatório)'
      : 'Phone Number (Required)',
    phoneNumberPlaceholder: isPortuguese.value
      ? 'Ex: +5511999999999'
      : 'e.g. +1234567890',
    phoneNumberError: isPortuguese.value
      ? 'O número de telefone é obrigatório'
      : 'Phone number is required',
    inboxLabel: isPortuguese.value
      ? 'Caixa de Entrada (Obrigatório)'
      : 'Inbox (Required)',
    inboxPlaceholder: isPortuguese.value
      ? 'Selecione a caixa de entrada...'
      : 'Select inbox...',
    inboxError: isPortuguese.value
      ? 'A caixa de entrada é obrigatória'
      : 'Inbox is required',
    messageLabel: isPortuguese.value
      ? 'Mensagem Inicial (Obrigatório)'
      : 'Initial Message (Required)',
    messagePlaceholder: isPortuguese.value
      ? 'Digite a mensagem de boas-vindas...'
      : 'Type the welcome message...',
    messageError: isPortuguese.value
      ? 'A mensagem é obrigatória'
      : 'Message is required',
    labelsLabel: isPortuguese.value
      ? 'Etiquetas do Contato (Opcional)'
      : 'Contact Labels (Optional)',
    labelsPlaceholder: isPortuguese.value
      ? 'Selecione as etiquetas...'
      : 'Select labels...',
    agentLabel: isPortuguese.value
      ? 'Atribuir Agente (Opcional)'
      : 'Assign Agent (Optional)',
    agentPlaceholder: isPortuguese.value
      ? 'Selecione um agente...'
      : 'Select an agent...',
    teamLabel: isPortuguese.value
      ? 'Atribuir Time (Opcional)'
      : 'Assign Team (Optional)',
    teamPlaceholder: isPortuguese.value
      ? 'Selecione um time...'
      : 'Select a team...',
    priorityLabel: isPortuguese.value
      ? 'Prioridade da Conversa (Opcional)'
      : 'Conversation Priority (Optional)',
    priorityPlaceholder: isPortuguese.value
      ? 'Selecione a prioridade...'
      : 'Select priority...',
    priorityUrgent: isPortuguese.value ? 'Urgente' : 'Urgent',
    priorityHigh: isPortuguese.value ? 'Alta' : 'High',
    priorityMedium: isPortuguese.value ? 'Média' : 'Medium',
    priorityLow: isPortuguese.value ? 'Baixa' : 'Low',
    cancelButton: isPortuguese.value ? 'Cancelar' : 'Cancel',
    confirmButton: isPortuguese.value ? 'Criar e Enviar' : 'Create & Send',
    successMessage: isPortuguese.value
      ? 'Conversa criada e enviada com sucesso!'
      : 'Conversation created and sent successfully!',
    errorMessage: isPortuguese.value
      ? 'Erro ao criar a conversa. Verifique os dados.'
      : 'Error creating conversation. Please check the fields.',
    existingContactFound: isPortuguese.value
      ? 'Contato existente encontrado'
      : 'Existing contact found',
    existingContactWarning: isPortuguese.value
      ? 'O número digitado já está associado a este contato. Se você prosseguir, a mensagem será enviada a ele.'
      : 'The typed number is already associated with this contact. If you proceed, the message will be sent to them.',
  };
  return translations[key] || key;
};

// Selectors mapping
const inboxesList = useMapGetter('inboxes/getInboxes');
const labelsList = useMapGetter('labels/getLabels');
const agentsList = useMapGetter('agents/getAgents');
const teamsList = useMapGetter('teams/getTeams');

// Active/outbound inboxes
const inboxOptions = computed(() => {
  return (inboxesList.value || [])
    .filter(inbox => {
      const type = inbox.channel_type || inbox.channelType || '';
      return [
        'Channel::Whatsapp',
        'Channel::Sms',
        'Channel::Email',
        'Channel::TwilioSms',
        'Channel::Api',
      ].includes(type);
    })
    .map(inbox => ({
      value: inbox.id,
      label: inbox.name,
    }));
});

// Active labels
const labelOptions = computed(() => {
  return (labelsList.value || []).map(label => ({
    value: label.title,
    label: label.title,
  }));
});

// Agents list
const agentOptions = computed(() => {
  return (agentsList.value || []).map(agent => ({
    value: agent.id,
    label: agent.name,
  }));
});

// Teams list
const teamOptions = computed(() => {
  return (teamsList.value || []).map(team => ({
    value: team.id,
    label: team.name,
  }));
});

// Priority list
const priorityOptions = computed(() => {
  return [
    { value: 'low', label: t('priorityLow') },
    { value: 'medium', label: t('priorityMedium') },
    { value: 'high', label: t('priorityHigh') },
    { value: 'urgent', label: t('priorityUrgent') },
  ];
});

// State definitions
const state = reactive({
  contactName: '',
  phoneNumber: '',
  targetInboxId: '',
  message: '',
  selectedLabels: [],
  selectedAgentId: '',
  selectedTeamId: '',
  selectedPriority: '',
});

const existingContact = ref(null);

// Form validation rules
const rules = {
  phoneNumber: { required },
  targetInboxId: { required },
  message: { required },
};

const v$ = useVuelidate(rules, state);
const isSubmitting = ref(false);
const dialogRef = ref(null);

// Intelligent Phone Matching Helper
const isPhoneMatching = (phone1, phone2) => {
  if (!phone1 || !phone2) return false;
  const digits1 = phone1.replace(/\D/g, '');
  const digits2 = phone2.replace(/\D/g, '');
  if (!digits1 || !digits2) return false;
  if (digits1 === digits2) return true;
  if (digits1.length >= 8 && digits2.length >= 8) {
    return digits1.endsWith(digits2) || digits2.endsWith(digits1);
  }
  return false;
};

// Debounced Contact Search
const performContactLookup = debounce(async phoneVal => {
  const cleanPhone = (phoneVal || '').trim();
  if (!cleanPhone || cleanPhone.replace(/\D/g, '').length < 8) {
    existingContact.value = null;
    return;
  }

  try {
    const searchResponse = await ContactAPI.search(cleanPhone);
    const foundContact = (searchResponse.data?.payload || []).find(
      c =>
        c.phone_number === cleanPhone ||
        isPhoneMatching(c.phone_number, cleanPhone)
    );
    if (foundContact) {
      existingContact.value = foundContact;
      // Populate name if not currently set or if it's the exact clean phone
      if (
        !state.contactName.trim() ||
        state.contactName.trim() === cleanPhone
      ) {
        state.contactName = foundContact.name;
      }
    } else {
      existingContact.value = null;
    }
  } catch (e) {
    existingContact.value = null;
  }
}, 300);

watch(
  () => state.phoneNumber,
  newVal => {
    performContactLookup(newVal);
  }
);

const open = () => {
  // Reset state
  Object.assign(state, {
    contactName: '',
    phoneNumber: '',
    targetInboxId: '',
    message: '',
    selectedLabels: [],
    selectedAgentId: '',
    selectedTeamId: '',
    selectedPriority: '',
  });
  existingContact.value = null;
  v$.value.$reset();
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
  emit('close');
};

const onSubmit = async () => {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  isSubmitting.value = true;
  try {
    const cleanPhone = state.phoneNumber.trim();
    let contact = null;

    // Try finding contact first
    try {
      const searchResponse = await ContactAPI.search(cleanPhone);
      const foundContact = (searchResponse.data?.payload || []).find(
        c =>
          c.phone_number === cleanPhone ||
          isPhoneMatching(c.phone_number, cleanPhone)
      );
      if (foundContact) {
        contact = foundContact;
        if (
          state.contactName.trim() &&
          foundContact.name !== state.contactName.trim()
        ) {
          const updateResponse = await store.dispatch('contacts/update', {
            id: foundContact.id,
            name: state.contactName.trim(),
          });
          if (updateResponse) {
            contact = updateResponse;
          }
        }
      }
    } catch (e) {
      // ignore search failures and attempt create
    }

    // Create if not found
    if (!contact) {
      try {
        contact = await store.dispatch('contacts/create', {
          name: state.contactName.trim() || cleanPhone,
          phone_number: cleanPhone,
        });
      } catch (error) {
        if (
          error instanceof DuplicateContactException ||
          error.name === 'DuplicateContactException'
        ) {
          contact = error.data?.contact;
        } else {
          throw error;
        }
      }
    }

    if (!contact || !contact.id) {
      throw new Error('Failed to obtain contact ID');
    }

    const contactId = contact.id;

    // Apply Contact Labels if selected
    if (state.selectedLabels.length > 0) {
      await store.dispatch('contactLabels/update', {
        contactId,
        labels: state.selectedLabels,
      });
    }

    // Find target inbox details
    const targetInbox = inboxesList.value.find(
      i => i.id === state.targetInboxId
    );

    // Create conversation & message payload
    const conversationPayload = {
      inboxId: state.targetInboxId,
      sourceId: targetInbox?.source_id || targetInbox?.sourceId || '',
      contactId: Number(contactId),
      message: { content: state.message },
    };

    const conversationData = await store.dispatch(
      'contactConversations/create',
      {
        params: conversationPayload,
        isFromWhatsApp: false,
      }
    );

    if (!conversationData || !conversationData.id) {
      throw new Error('Failed to create conversation');
    }

    const conversationId = conversationData.id;

    // Assign Agent
    if (state.selectedAgentId) {
      await store.dispatch('assignAgent', {
        conversationId,
        agentId: Number(state.selectedAgentId),
      });
    }

    // Assign Team
    if (state.selectedTeamId) {
      await store.dispatch('assignTeam', {
        conversationId,
        teamId: Number(state.selectedTeamId),
      });
    }

    // Assign Priority
    if (state.selectedPriority) {
      await store.dispatch('assignPriority', {
        conversationId,
        priority: state.selectedPriority,
      });
    }

    useAlert(t('successMessage'));
    close();

    // Redirect user to newly created conversation
    const accountId =
      conversationData.account_id ||
      store.getters.getCurrentAccountId ||
      store.state.accounts.currentId;
    router.push(`/app/accounts/${accountId}/conversations/${conversationId}`);
  } catch (error) {
    useAlert(t('errorMessage'));
  } finally {
    isSubmitting.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    :title="t('modalTitle')"
    width="lg"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="close"
  >
    <form
      class="flex flex-col gap-4 max-h-[calc(100vh-14rem)] overflow-y-auto pr-1"
      @submit.prevent="onSubmit"
    >
      <!-- Contact Name input -->
      <div>
        <Input
          v-model="state.contactName"
          type="text"
          :label="t('contactNameLabel')"
          :placeholder="t('contactNamePlaceholder')"
        />
      </div>

      <!-- Phone Number input -->
      <div>
        <Input
          v-model="state.phoneNumber"
          type="text"
          :label="t('phoneNumberLabel')"
          :placeholder="t('phoneNumberPlaceholder')"
          :message="v$.phoneNumber.$error ? t('phoneNumberError') : ''"
          message-type="error"
        />
      </div>

      <!-- Existing Contact Alert Banner -->
      <div
        v-if="existingContact"
        class="p-3 bg-n-alpha-2 border border-n-weak rounded-xl text-sm flex flex-col gap-1 animate-in fade-in slide-in-from-top-1 duration-200"
      >
        <span class="font-medium text-n-slate-12 flex items-center gap-1.5">
          <span class="i-lucide-alert-triangle size-4 text-n-warning" />
          {{ t('existingContactFound') }}
        </span>
        <span class="text-n-slate-11">
          {{
            isPortuguese
              ? `O número digitado já está associado a "${existingContact.name}". Se você prosseguir, a mensagem será enviada para este contato existente.`
              : `The typed number is already associated with "${existingContact.name}". If you continue, the message will be sent to this existing contact.`
          }}
        </span>
      </div>

      <!-- Inbox Selector -->
      <div class="flex flex-col gap-1.5">
        <label class="text-heading-3 text-n-slate-12">{{
          t('inboxLabel')
        }}</label>
        <ComboBox
          v-model="state.targetInboxId"
          :options="inboxOptions"
          :placeholder="t('inboxPlaceholder')"
          :has-error="v$.targetInboxId.$error"
          :message="v$.targetInboxId.$error ? t('inboxError') : ''"
        />
      </div>

      <!-- Message Textarea -->
      <div>
        <TextArea
          v-model="state.message"
          :label="t('messageLabel')"
          :placeholder="t('messagePlaceholder')"
          :show-character-count="false"
          :message="v$.message.$error ? t('messageError') : ''"
          message-type="error"
          auto-height
          min-height="5rem"
        />
      </div>

      <!-- Contact Tags ComboBox -->
      <div class="flex flex-col gap-1.5">
        <label class="text-heading-3 text-n-slate-12">{{
          t('labelsLabel')
        }}</label>
        <TagMultiSelectComboBox
          v-model="state.selectedLabels"
          :options="labelOptions"
          :placeholder="t('labelsPlaceholder')"
        />
      </div>

      <!-- Optional Attributes (Agent, Team, Priority) -->
      <div
        class="grid grid-cols-1 md:grid-cols-2 gap-4 pt-2 border-t border-n-weak dark:border-n-strong/30"
      >
        <!-- Agent Assignee -->
        <div class="flex flex-col gap-1.5">
          <label class="text-heading-3 text-n-slate-12">{{
            t('agentLabel')
          }}</label>
          <ComboBox
            v-model="state.selectedAgentId"
            :options="agentOptions"
            :placeholder="t('agentPlaceholder')"
          />
        </div>

        <!-- Team Assignee -->
        <div class="flex flex-col gap-1.5">
          <label class="text-heading-3 text-n-slate-12">{{
            t('teamLabel')
          }}</label>
          <ComboBox
            v-model="state.selectedTeamId"
            :options="teamOptions"
            :placeholder="t('teamPlaceholder')"
          />
        </div>

        <!-- Priority Selector -->
        <div class="flex flex-col gap-1.5 md:col-span-2">
          <label class="text-heading-3 text-n-slate-12">{{
            t('priorityLabel')
          }}</label>
          <ComboBox
            v-model="state.selectedPriority"
            :options="priorityOptions"
            :placeholder="t('priorityPlaceholder')"
          />
        </div>
      </div>

      <!-- Action Buttons -->
      <div
        class="flex items-center gap-3 mt-4 pt-4 border-t border-n-weak dark:border-n-strong/30"
      >
        <button
          type="button"
          class="flex-1 h-10 px-4 rounded-lg text-sm font-medium border border-n-strong dark:border-n-strong hover:bg-n-slate-2 dark:hover:bg-n-slate-3/30 transition-colors"
          @click="close"
        >
          {{ t('cancelButton') }}
        </button>
        <button
          type="submit"
          :disabled="isSubmitting"
          class="flex-1 h-10 px-4 rounded-lg text-sm font-medium bg-n-brand hover:bg-n-brand/90 text-white disabled:opacity-50 disabled:cursor-not-allowed transition-all duration-300 flex items-center justify-center gap-2"
        >
          <span
            v-if="isSubmitting"
            class="i-lucide-loader-2 animate-spin size-4"
          />
          <span>{{ t('confirmButton') }}</span>
        </button>
      </div>
    </form>
  </Dialog>
</template>

<style scoped>
.reset-base {
  all: unset;
}
</style>
