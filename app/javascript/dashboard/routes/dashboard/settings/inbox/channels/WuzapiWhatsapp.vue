<script setup>
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { required } from '@vuelidate/validators';
import { isPhoneE164OrEmpty } from 'shared/helpers/Validators';
import { isValidURL } from '../../../../../helper/URLHelper';

import NextButton from 'dashboard/components-next/button/Button.vue';

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

const router = useRouter();
const store = useStore();
const { t } = useI18n();

const inboxName = ref(isConvertMode.value ? props.inbox?.name || '' : '');
const phoneNumber = ref(
  isConvertMode.value ? props.inbox?.phone_number || '' : ''
);
const defaultProviderUrl = window.globalConfig?.BAILEYS_PROVIDER_DEFAULT_URL || '';

const providerUrl = ref(
  isConvertMode.value
    ? props.inbox?.provider_config?.provider_url || defaultProviderUrl
    : defaultProviderUrl
);
const adminToken = ref('');

const uiFlags = computed(() => store.getters['inboxes/getUIFlags']);

const rules = computed(() => ({
  inboxName: { required },
  phoneNumber: { required, isPhoneE164OrEmpty },
  providerUrl: {
    isValidURL: value => !value || isValidURL(value),
    required,
  },
  adminToken: { required },
}));

const v$ = useVuelidate(rules, {
  inboxName,
  phoneNumber,
  providerUrl,
  adminToken,
});

const buildProviderConfig = () => {
  const providerConfig = {};

  if (providerUrl.value) {
    providerConfig.provider_url = providerUrl.value;
  }

  if (adminToken.value) {
    providerConfig.admin_token = adminToken.value;
  }

  return providerConfig;
};

const createChannel = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) {
    return;
  }

  try {
    if (isConvertMode.value) {
      await store.dispatch('inboxes/convertProvider', {
        inboxId: props.inbox.id,
        provider: 'wuzapi',
        providerConfig: buildProviderConfig(),
      });

      useAlert(t('INBOX_MGMT.CONVERT.API.SUCCESS_MESSAGE'));
      router.replace({
        name: 'settings_inbox_show',
        params: {
          accountId: router.currentRoute.value.params.accountId,
          inboxId: props.inbox.id,
        },
      });
      return;
    }

    const whatsappChannel = await store.dispatch('inboxes/createChannel', {
      name: inboxName.value,
      channel: {
        type: 'whatsapp',
        phone_number: phoneNumber.value,
        provider: 'wuzapi',
        provider_config: buildProviderConfig(),
      },
    });

    router.replace({
      name: 'settings_inboxes_add_agents',
      params: {
        page: 'new',
        inbox_id: whatsappChannel.id,
      },
    });
  } catch (error) {
    useAlert(
      error.message ||
        t(
          isConvertMode.value
            ? 'INBOX_MGMT.CONVERT.API.ERROR_MESSAGE'
            : 'INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE'
        )
    );
  }
};


</script>

<template>
  <form class="flex flex-wrap mx-0" @submit.prevent="createChannel()">
    <div class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]">
      <label :class="{ error: v$.inboxName.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.LABEL') }}
        <input
          v-model="inboxName"
          type="text"
          :disabled="isConvertMode"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.PLACEHOLDER')"
          @blur="v$.inboxName.$touch"
        />
        <span v-if="v$.inboxName.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.ERROR') }}
        </span>
      </label>
    </div>

    <div class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]">
      <label :class="{ error: v$.phoneNumber.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.LABEL') }}
        <input
          v-model="phoneNumber"
          type="text"
          :disabled="isConvertMode"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.PLACEHOLDER')"
          @blur="v$.phoneNumber.$touch"
        />
        <span v-if="v$.phoneNumber.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.ERROR') }}
        </span>
      </label>
    </div>

    <div class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]">
      <label :class="{ error: v$.providerUrl.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PROVIDER_URL.LABEL') }}
        <input
          v-model="providerUrl"
          type="text"
          :placeholder="
            $t('INBOX_MGMT.ADD.WHATSAPP.PROVIDER_URL.PLACEHOLDER')
          "
        />
        <span v-if="v$.providerUrl.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.PROVIDER_URL.ERROR') }}
        </span>
      </label>
    </div>

    <div class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]">
      <label :class="{ error: v$.adminToken.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.ADMIN_TOKEN.LABEL') }}
        <input
          v-model="adminToken"
          type="password"
          :placeholder="
            $t('INBOX_MGMT.ADD.WHATSAPP.ADMIN_TOKEN.PLACEHOLDER')
          "
        />
        <span v-if="v$.adminToken.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.ADMIN_TOKEN.ERROR') }}
        </span>
      </label>
    </div>

    <div class="w-full">
      <NextButton
        :is-loading="uiFlags.isCreating || uiFlags.isUpdating"
        type="submit"
        solid
        blue
        :label="
          isConvertMode
            ? $t('INBOX_MGMT.CONVERT.SUBMIT_BUTTON')
            : $t('INBOX_MGMT.ADD.WHATSAPP.SUBMIT_BUTTON')
        "
      />
    </div>
  </form>
</template>
