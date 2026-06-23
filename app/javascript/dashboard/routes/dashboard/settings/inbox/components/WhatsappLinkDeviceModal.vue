<script setup>
import { onMounted, computed, onUnmounted, ref, watchEffect } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import InboxName from 'dashboard/components/widgets/InboxName.vue';
import Spinner from 'shared/components/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import QRCode from 'qrcode';

const props = defineProps({
  show: { type: Boolean, required: true },
  onClose: { type: Function, required: true },
  isSetup: { type: Boolean, required: false },
  inbox: {
    type: Object,
    required: true,
  },
});

const store = useStore();

const providerConnection = computed(() => props.inbox.provider_connection);
const connection = computed(() => providerConnection.value?.connection);
const qrCodeImageUrl = ref('');
const error = computed(() => providerConnection.value?.error);

watchEffect(async () => {
  const rawQr = providerConnection.value?.qr_data_url;
  if (!rawQr) {
    qrCodeImageUrl.value = '';
    return;
  }
  if (rawQr.startsWith('data:image/')) {
    qrCodeImageUrl.value = rawQr;
  } else {
    try {
      qrCodeImageUrl.value = await QRCode.toDataURL(rawQr);
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error(err);
      qrCodeImageUrl.value = '';
    }
  }
});

const loading = ref(false);

const handleError = e => {
  useAlert(e.message);
  loading.value = false;
};
const setup = async () => {
  loading.value = true;
  try {
    await store.dispatch('inboxes/setupChannelProvider', props.inbox.id);
  } catch (e) {
    handleError(e);
  }
};
const disconnect = async () => {
  loading.value = true;
  try {
    await store.dispatch('inboxes/disconnectChannelProvider', props.inbox.id);
  } catch (e) {
    handleError(e);
  }
};

onMounted(() => {
  if (!connection.value || connection.value === 'close') {
    setup();
  }
});
onUnmounted(() => {
  if (
    connection.value === 'connecting' ||
    connection.value === 'reconnecting'
  ) {
    disconnect();
  }
});
watchEffect(() => {
  if (connection.value) {
    loading.value = false;
  }
});
</script>

<template>
  <woot-modal :show="show" size="small" @close="onClose">
    <div class="flex flex-col h-auto overflow-auto">
      <woot-modal-header
        :header-title="
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.TITLE'
          )
        "
        :header-content="
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.SUBTITLE'
          )
        "
      />

      <div class="flex flex-col gap-4 p-8 pt-4">
        <div class="flex flex-col gap-4 items-center">
          <InboxName
            :inbox="inbox"
            class="!text-lg"
            with-phone-number
            with-provider-connection-status
          />

          <template v-if="!connection || connection === 'close' || error">
            <p v-if="error" class="text-red-500 text-center">
              {{ error }}
            </p>
            <Button :is-loading="loading" @click="setup">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.LINK_DEVICE'
                )
              }}
            </Button>
          </template>

          <template v-else-if="connection === 'connecting'">
            <div
              v-if="!qrCodeImageUrl"
              class="flex flex-col gap-4 items-center"
            >
              <p>
                {{
                  $t(
                    'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.LOADING_QRCODE'
                  )
                }}
              </p>
              <Spinner />
            </div>
            <img
              v-else
              :src="qrCodeImageUrl"
              alt="QR Code"
              class="w-[276px] h-[276px]"
            />
          </template>

          <template v-else-if="connection === 'reconnecting'">
            <p>
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.RECONNECTING'
                )
              }}
            </p>
            <Spinner />
          </template>

          <template v-else-if="connection === 'open'">
            <p v-if="isSetup" class="text-center">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.CONNECTED'
                )
              }}
            </p>
            <div class="flex gap-2">
              <Button ghost :is-loading="loading" @click="disconnect">
                {{
                  $t(
                    'INBOX_MGMT.ADD.WHATSAPP.EXTERNAL_PROVIDER.LINK_DEVICE_MODAL.DISCONNECT'
                  )
                }}
              </Button>
              <router-link
                v-if="isSetup"
                :to="{
                  name: 'inbox_dashboard',
                  params: { inboxId: inbox.id },
                }"
              >
                <Button
                  solid
                  teal
                  :label="$t('INBOX_MGMT.FINISH.BUTTON_TEXT')"
                />
              </router-link>
            </div>
          </template>
        </div>
      </div>
    </div>
  </woot-modal>
</template>
