<script setup>
import { ref } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import DatePicker from 'vue-datepicker-next';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
});

const emit = defineEmits(['close']);

const store = useStore();

const reminderTime = ref(null);
const note = ref('');
const sendMessage = ref(false);
const isCreating = ref(false);

const lang = {
  days: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
  yearFormat: 'YYYY',
  monthFormat: 'MMMM',
};

const disabledDate = date => {
  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);
  return date < yesterday;
};

const disabledTime = date => {
  const now = new Date();
  now.setMinutes(now.getMinutes() + 5);
  return date < now;
};

const resetForm = () => {
  reminderTime.value = null;
  note.value = '';
  sendMessage.value = false;
};

const onSubmit = async hide => {
  if (!reminderTime.value) {
    useAlert('Por favor, selecione uma data e hora válidas.');
    return;
  }
  
  isCreating.value = true;
  try {
    await store.dispatch('contactReminders/create', {
      contactId: props.contactId,
      reminder_time: reminderTime.value.toISOString(),
      note: note.value,
      send_message: sendMessage.value,
    });
    useAlert('Lembrete criado com sucesso!');
    resetForm();
    hide();
    emit('close');
  } catch (error) {
    useAlert('Erro ao criar lembrete. Tente novamente.');
  } finally {
    isCreating.value = false;
  }
};
</script>

<template>
  <Popover @hide="resetForm(); $emit('close')">
    <slot name="trigger" />
    <template #content="{ hide }">
      <div class="w-full md:w-96 p-6 flex flex-col gap-4">
        <div class="flex flex-col gap-2">
          <h3 class="text-base font-medium leading-6 text-n-slate-12">
            Criar Lembrete
          </h3>
          <p class="mb-0 text-sm text-n-slate-11">
            Escolha uma data e horário para receber um lembrete sobre este contato. Você também pode enviar uma mensagem automática.
          </p>
        </div>
        
        <form class="flex flex-col gap-4" @submit.prevent="onSubmit(hide)">
          <div class="flex flex-col gap-1">
            <label class="text-sm font-medium text-n-slate-12">Data e Hora</label>
            <DatePicker
              v-model:value="reminderTime"
              type="datetime"
              input-class="mx-input"
              :lang="lang"
              :disabled-date="disabledDate"
              :disabled-time="disabledTime"
              placeholder="Selecione data e hora"
              style="width: 100%"
            />
          </div>
          
          <div class="flex flex-col gap-1">
            <label class="text-sm font-medium text-n-slate-12">Nota / Mensagem</label>
            <textarea
              v-model="note"
              rows="3"
              class="w-full px-3 py-2 border rounded-md border-n-slate-3 bg-white text-n-slate-12 focus:ring-1 focus:ring-w-500 focus:border-w-500"
              placeholder="Digite uma anotação ou a mensagem que será enviada"
            />
          </div>
          
          <div class="flex items-center gap-2">
            <input
              v-model="sendMessage"
              type="checkbox"
              id="send-message-checkbox"
              class="w-4 h-4 rounded text-w-500 border-n-slate-3 focus:ring-w-500"
            />
            <label for="send-message-checkbox" class="text-sm text-n-slate-11 cursor-pointer">
              Enviar esta mensagem para o cliente no horário agendado
            </label>
          </div>

          <div class="flex flex-row justify-end w-full gap-2 mt-2">
            <NextButton
              faded
              slate
              type="reset"
              label="Cancelar"
              @click.prevent="hide"
            />
            <NextButton
              type="submit"
              label="Salvar Lembrete"
              :is-loading="isCreating"
            />
          </div>
        </form>
      </div>
    </template>
  </Popover>
</template>
