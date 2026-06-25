<script>
import { useAlert } from 'dashboard/composables';
import inboxMixin from 'shared/mixins/inboxMixin';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import SettingsAccordion from 'dashboard/components-next/Settings/SettingsAccordion.vue';
import ImapSettings from '../ImapSettings.vue';
import SmtpSettings from '../SmtpSettings.vue';
import { useVuelidate } from '@vuelidate/core';
import { requiredIf } from '@vuelidate/validators';
import NextButton from 'dashboard/components-next/button/Button.vue';
import TextArea from 'next/textarea/TextArea.vue';
import WhatsappReauthorize from '../channels/whatsapp/Reauthorize.vue';
import { sanitizeAllowedDomains, isValidURL } from 'dashboard/helper/URLHelper';
import NextInput from 'dashboard/components-next/input/Input.vue';
import WhatsappLinkDeviceModal from '../components/WhatsappLinkDeviceModal.vue';
import InboxName from 'dashboard/components/widgets/InboxName.vue';
import NextSwitch from 'dashboard/components-next/switch/Switch.vue';

export default {
  components: {
    SettingsFieldSection,
    SettingsToggleSection,
    SettingsAccordion,
    ImapSettings,
    SmtpSettings,
    NextButton,
    TextArea,
    WhatsappReauthorize,
    NextInput,
    WhatsappLinkDeviceModal,
    InboxName,
    NextSwitch,
  },
  mixins: [inboxMixin],
  props: {
    inbox: {
      type: Object,
      default: () => ({}),
    },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      hmacMandatory: false,
      allowMobileWebview: false,
      whatsAppInboxAPIKey: '',
      isRequestingReauthorization: false,
      isSyncingTemplates: false,
      allowedDomains: '',
      isUpdatingAllowedDomains: false,
      isUpdatingVoiceConfig: false,
      customVoiceConfig: {
        webrtcWsUrl: '',
        sipDomain: '',
        sipOutboundProxy: '',
        sipTransport: 'wss',
        stunServers: '',
        turnUrl: '',
        turnUsername: '',
        turnPassword: '',
        authType: 'jwt',
        transferMode: 'sip_refer',
        transferApiUrl: '',
        transferApiToken: '',
        useAgentJwt: true,
        jwtIssuer: '',
        jwtAudience: '',
        jwtSecret: '',
        jwtTtl: '3600',
      },
      isSettingDefaults: false,
      baileysProviderUrl: '',
      showLinkDeviceModal: false,
      markAsRead: true,
      presenceSubscribe: false,
      zapiInstanceId: '',
      zapiToken: '',
      zapiClientToken: '',
      zapiInstanceIdUpdate: '',
      zapiTokenUpdate: '',
      zapiClientTokenUpdate: '',
      wuzapiProviderUrl: '',
      wuzapiApiKey: '',
      wuzapiAdminToken: '',
      wuzapiApiKeyUpdate: '',
      wuzapiAdminTokenUpdate: '',
    };
  },
  validations() {
    return {
      whatsAppInboxAPIKey: {
        requiredIf: requiredIf(
          !this.isAWhatsAppBaileysChannel && !this.isAWhatsAppWuzapiChannel && !this.isAWhatsAppZapiChannel
        ),
      },
      baileysProviderUrl: { isValidURL: value => !value || isValidURL(value) },
      zapiInstanceIdUpdate: {},
      zapiTokenUpdate: {},
      zapiClientTokenUpdate: {},
      wuzapiProviderUrl: { isValidURL: value => !value || isValidURL(value) },
      wuzapiApiKeyUpdate: {},
      wuzapiAdminTokenUpdate: {},
    };
  },
  computed: {
    isEmbeddedSignupWhatsApp() {
      return this.inbox.provider_config?.source === 'embedded_signup';
    },
    whatsappAppId() {
      return window.chatwootConfig?.whatsappAppId;
    },
    isForwardingEnabled() {
      return !!this.inbox.forwarding_enabled;
    },
    isCustomVoiceChannel() {
      return this.isAVoiceChannel && this.inbox.provider === 'custom';
    },
    hasDefaultBaileysConfig() {
      return !!(window.globalConfig?.BAILEYS_PROVIDER_DEFAULT_URL && window.globalConfig?.BAILEYS_PROVIDER_DEFAULT_API_KEY);
    },
    hasDefaultWuzapiConfig() {
      return !!(window.globalConfig?.BAILEYS_PROVIDER_DEFAULT_URL && window.globalConfig?.BAILEYS_PROVIDER_DEFAULT_API_KEY);
    },
  },
  watch: {
    inbox() {
      this.setDefaults();
    },
    allowMobileWebview() {
      if (!this.isSettingDefaults) this.handleMobileWebviewFlag();
    },
    hmacMandatory() {
      if (!this.isSettingDefaults && this.isAWebWidgetInbox)
        this.handleHmacFlag();
    },
  },
  mounted() {
    this.setDefaults();
  },
  methods: {
    setDefaults() {
      this.isSettingDefaults = true;
      this.hmacMandatory = this.inbox.hmac_mandatory || false;
      this.allowMobileWebview = (
        this.inbox.selected_feature_flags || []
      ).includes('allow_mobile_webview');
      this.allowedDomains = this.inbox.allowed_domains || '';
      if (this.isCustomVoiceChannel) {
        const config = this.inbox.provider_config || {};
        this.customVoiceConfig = {
          webrtcWsUrl: config.webrtc_ws_url || '',
          sipDomain: config.sip_domain || '',
          sipOutboundProxy: config.sip_outbound_proxy || '',
          sipTransport: config.sip_transport || 'wss',
          stunServers: (config.stun_servers || []).join('\n'),
          turnUrl: (config.turn_servers || [])[0]?.urls || '',
          turnUsername: (config.turn_servers || [])[0]?.username || '',
          turnPassword: (config.turn_servers || [])[0]?.credential || '',
          authType: config.auth_type || 'jwt',
          transferMode: config.transfer_mode || 'sip_refer',
          transferApiUrl: config.transfer_api_url || '',
          transferApiToken: '',
          useAgentJwt: config.use_agent_jwt !== false,
          jwtIssuer: config.jwt_issuer || '',
          jwtAudience: config.jwt_audience || '',
          jwtSecret: '',
          jwtTtl: config.jwt_ttl ? config.jwt_ttl.toString() : '3600',
        };
      }
      const defaultProviderUrl = window.globalConfig?.BAILEYS_PROVIDER_DEFAULT_URL || '';
      this.baileysProviderUrl = this.inbox.provider_config?.provider_url || defaultProviderUrl;
      this.markAsRead = this.inbox.provider_config?.mark_as_read ?? true;
      this.presenceSubscribe =
        this.inbox.provider_config?.presence_subscribe ?? false;
      this.zapiInstanceId = this.inbox.provider_config?.instance_id ?? '';
      this.zapiToken = this.inbox.provider_config?.token ?? '';
      this.zapiClientToken = this.inbox.provider_config?.client_token ?? '';
      this.zapiInstanceIdUpdate = this.zapiInstanceId;
      this.zapiTokenUpdate = this.zapiToken;
      this.zapiClientTokenUpdate = this.zapiClientToken;
      const defaultWuzapiUrl = window.globalConfig?.BAILEYS_PROVIDER_DEFAULT_URL || '';
      this.wuzapiProviderUrl = this.inbox.provider_config?.provider_url || defaultWuzapiUrl;
      this.wuzapiApiKey = this.inbox.provider_config?.api_key || '';
      this.wuzapiAdminToken = this.inbox.provider_config?.admin_token || '';
      this.wuzapiApiKeyUpdate = this.wuzapiApiKey;
      this.wuzapiAdminTokenUpdate = this.wuzapiAdminToken;
      this.$nextTick(() => {
        this.isSettingDefaults = false;
      });
    },
    handleHmacFlag() {
      this.updateInbox();
    },
    async updateInbox() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            hmac_mandatory: this.hmacMandatory,
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async handleMobileWebviewFlag() {
      try {
        const currentFlags = this.inbox.selected_feature_flags || [];
        const selectedFlags = this.allowMobileWebview
          ? [...currentFlags, 'allow_mobile_webview']
          : currentFlags.filter(f => f !== 'allow_mobile_webview');

        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            selected_feature_flags: selectedFlags,
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async updateAllowedDomains() {
      this.isUpdatingAllowedDomains = true;
      const sanitizedAllowedDomains = sanitizeAllowedDomains(
        this.allowedDomains
      );
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            allowed_domains: sanitizedAllowedDomains,
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        this.allowedDomains = sanitizedAllowedDomains;
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isUpdatingAllowedDomains = false;
      }
    },
    async updateVoiceConfig() {
      this.isUpdatingVoiceConfig = true;
      try {
        const config = {
          webrtc_ws_url: this.customVoiceConfig.webrtcWsUrl,
          sip_domain: this.customVoiceConfig.sipDomain,
          sip_outbound_proxy: this.customVoiceConfig.sipOutboundProxy,
          sip_transport: this.customVoiceConfig.sipTransport,
          stun_servers: this.customVoiceConfig.stunServers
            .split('\n')
            .map(item => item.trim())
            .filter(item => item),
          auth_type: this.customVoiceConfig.authType,
          transfer_mode: this.customVoiceConfig.transferMode,
          transfer_api_url:
            this.customVoiceConfig.transferMode === 'ari'
              ? this.customVoiceConfig.transferApiUrl
              : '',
          transfer_api_token:
            this.customVoiceConfig.transferMode === 'ari'
              ? this.customVoiceConfig.transferApiToken
              : '',
        };
        if (this.customVoiceConfig.turnUrl) {
          config.turn_servers = [
            {
              urls: this.customVoiceConfig.turnUrl.trim(),
              username: this.customVoiceConfig.turnUsername || undefined,
              credential: this.customVoiceConfig.turnPassword || undefined,
            },
          ].filter(server => server.urls);
        }
        if (Array.isArray(config.stun_servers) && !config.stun_servers.length) {
          delete config.stun_servers;
        }
        if (Array.isArray(config.turn_servers) && !config.turn_servers.length) {
          delete config.turn_servers;
        }

        if (this.customVoiceConfig.authType === 'jwt') {
          config.use_agent_jwt = this.customVoiceConfig.useAgentJwt;
          config.jwt_issuer = this.customVoiceConfig.useAgentJwt
            ? ''
            : this.customVoiceConfig.jwtIssuer;
          config.jwt_audience = this.customVoiceConfig.useAgentJwt
            ? ''
            : this.customVoiceConfig.jwtAudience;
          config.jwt_secret = this.customVoiceConfig.useAgentJwt
            ? ''
            : this.customVoiceConfig.jwtSecret;
          config.jwt_ttl = this.customVoiceConfig.useAgentJwt
            ? ''
            : this.customVoiceConfig.jwtTtl;
        }

        const providerConfig = Object.fromEntries(
          Object.entries(config).filter(([, value]) => value !== '')
        );

        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            provider_config: providerConfig,
          },
        };

        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isUpdatingVoiceConfig = false;
      }
    },
    async updateWhatsAppInboxAPIKey() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {},
        };

        payload.channel.provider_config = {
          ...this.inbox.provider_config,
          api_key: this.whatsAppInboxAPIKey,
        };

        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async handleReconfigure() {
      if (this.$refs.whatsappReauth) {
        await this.$refs.whatsappReauth.requestAuthorization();
      }
    },
    async syncTemplates() {
      this.isSyncingTemplates = true;
      try {
        await this.$store.dispatch('inboxes/syncTemplates', this.inbox.id);
        useAlert(
          this.$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_SUCCESS')
        );
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isSyncingTemplates = false;
      }
    },
    async updateBaileysProviderUrl() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            provider_config: {
              ...this.inbox.provider_config,
              provider_url: this.baileysProviderUrl,
            },
          },
        };

        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async updateWhatsAppMarkAsRead() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            provider_config: {
              ...this.inbox.provider_config,
              mark_as_read: this.markAsRead,
            },
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async updatePresenceSubscribe() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            provider_config: {
              ...this.inbox.provider_config,
              presence_subscribe: this.presenceSubscribe,
            },
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    onOpenLinkDeviceModal() {
      this.showLinkDeviceModal = true;
    },
    onCloseLinkDeviceModal() {
      this.showLinkDeviceModal = false;
    },
    async updateZapiInstanceId() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            provider_config: {
              ...this.inbox.provider_config,
              instance_id: this.zapiInstanceIdUpdate,
            },
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async updateZapiToken() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            provider_config: {
              ...this.inbox.provider_config,
              token: this.zapiTokenUpdate,
            },
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async updateZapiClientToken() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            provider_config: {
              ...this.inbox.provider_config,
              client_token: this.zapiClientTokenUpdate,
            },
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async setupWuzapiConnection() {
      try {
        await this.$store.dispatch('inboxes/setupChannelProvider', this.inbox.id);
        useAlert(this.$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_CONNECTION_SETUP_SUCCESS'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_CONNECTION_SETUP_ERROR'));
      }
    },
    async updateWuzapiProviderUrl() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            provider_config: {
              ...this.inbox.provider_config,
              provider_url: this.wuzapiProviderUrl,
            },
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async updateWuzapiApiKey() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            provider_config: {
              ...this.inbox.provider_config,
              api_key: this.wuzapiApiKeyUpdate,
            },
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async updateWuzapiAdminToken() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            provider_config: {
              ...this.inbox.provider_config,
              admin_token: this.wuzapiAdminTokenUpdate,
            },
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
  },
};
</script>

<template>
  <div v-if="isATwilioChannel">
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.ADD.TWILIO.API_CALLBACK.TITLE')"
      :help-text="$t('INBOX_MGMT.ADD.TWILIO.API_CALLBACK.SUBTITLE')"
    >
      <woot-code :script="inbox.callback_webhook_url" lang="html" />
    </SettingsFieldSection>
    <SettingsFieldSection
      v-if="isATwilioWhatsAppChannel"
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_TITLE')"
      :help-text="
        $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_SUBHEADER')
      "
    >
      <NextButton :disabled="isSyncingTemplates" @click="syncTemplates">
        {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_BUTTON') }}
      </NextButton>
    </SettingsFieldSection>
  </div>
  <div v-else-if="isAVoiceChannel" class="mx-8">
    <template v-if="inbox.provider === 'twilio'">
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.ADD.VOICE.CONFIGURATION.TWILIO_VOICE_URL_TITLE')"
        :help-text="
          $t('INBOX_MGMT.ADD.VOICE.CONFIGURATION.TWILIO_VOICE_URL_SUBTITLE')
        "
      >
        <woot-code :script="inbox.voice_call_webhook_url" lang="html" />
      </SettingsFieldSection>
      <SettingsFieldSection
        :label="
          $t('INBOX_MGMT.ADD.VOICE.CONFIGURATION.TWILIO_STATUS_URL_TITLE')
        "
        :help-text="
          $t('INBOX_MGMT.ADD.VOICE.CONFIGURATION.TWILIO_STATUS_URL_SUBTITLE')
        "
      >
        <woot-code :script="inbox.voice_status_webhook_url" lang="html" />
      </SettingsFieldSection>
    </template>

    <template v-else-if="isCustomVoiceChannel">
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.ADD.VOICE.PROVIDERS.CUSTOM')"
        :help-text="$t('INBOX_MGMT.ADD.VOICE.DESC')"
      >
        <div class="flex flex-col gap-4 max-w-3xl">
          <NextInput
            v-model="customVoiceConfig.webrtcWsUrl"
            :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.WEBRTC_WS_URL.LABEL')"
            :placeholder="
              $t('INBOX_MGMT.ADD.VOICE.CUSTOM.WEBRTC_WS_URL.PLACEHOLDER')
            "
          />
          <NextInput
            v-model="customVoiceConfig.sipDomain"
            :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_DOMAIN.LABEL')"
            :placeholder="
              $t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_DOMAIN.PLACEHOLDER')
            "
          />
          <NextInput
            v-model="customVoiceConfig.sipOutboundProxy"
            :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_OUTBOUND_PROXY.LABEL')"
            :placeholder="
              $t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_OUTBOUND_PROXY.PLACEHOLDER')
            "
          />
          <label class="flex flex-col gap-1 text-sm text-n-slate-11">
            {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_TRANSPORT.LABEL') }}
            <select
              v-model="customVoiceConfig.sipTransport"
              class="rounded-md border-n-strong"
            >
              <option value="wss">
                {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_TRANSPORT.WSS') }}
              </option>
              <option value="ws">
                {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_TRANSPORT.WS') }}
              </option>
            </select>
          </label>
          <TextArea
            v-model="customVoiceConfig.stunServers"
            auto-height
            :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.STUN_SERVERS.LABEL')"
            :placeholder="
              $t('INBOX_MGMT.ADD.VOICE.CUSTOM.STUN_SERVERS.PLACEHOLDER')
            "
          />
          <NextInput
            v-model="customVoiceConfig.turnUrl"
            :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.TURN_URL.LABEL')"
            :placeholder="
              $t('INBOX_MGMT.ADD.VOICE.CUSTOM.TURN_URL.PLACEHOLDER')
            "
          />
          <NextInput
            v-model="customVoiceConfig.turnUsername"
            :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.TURN_USERNAME.LABEL')"
            :placeholder="
              $t('INBOX_MGMT.ADD.VOICE.CUSTOM.TURN_USERNAME.PLACEHOLDER')
            "
          />
          <NextInput
            v-model="customVoiceConfig.turnPassword"
            type="password"
            :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.TURN_PASSWORD.LABEL')"
            :placeholder="
              $t('INBOX_MGMT.ADD.VOICE.CUSTOM.TURN_PASSWORD.PLACEHOLDER')
            "
          />
          <label class="flex flex-col gap-1 text-sm text-n-slate-11">
            {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.AUTH_TYPE.LABEL') }}
            <select
              v-model="customVoiceConfig.authType"
              class="rounded-md border-n-strong"
            >
              <option value="jwt">
                {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.AUTH_TYPE.JWT') }}
              </option>
              <option value="password">
                {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.AUTH_TYPE.PASSWORD') }}
              </option>
            </select>
          </label>
          <label class="flex flex-col gap-1 text-sm text-n-slate-11">
            {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_MODE.LABEL') }}
            <select
              v-model="customVoiceConfig.transferMode"
              class="rounded-md border-n-strong"
            >
              <option value="sip_refer">
                {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_MODE.SIP_REFER') }}
              </option>
              <option value="ari">
                {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_MODE.ARI') }}
              </option>
            </select>
          </label>
          <template v-if="customVoiceConfig.transferMode === 'ari'">
            <NextInput
              v-model="customVoiceConfig.transferApiUrl"
              :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_API_URL.LABEL')"
              :placeholder="
                $t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_API_URL.PLACEHOLDER')
              "
            />
            <NextInput
              v-model="customVoiceConfig.transferApiToken"
              type="password"
              :label="
                $t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_API_TOKEN.LABEL')
              "
              :placeholder="
                $t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_API_TOKEN.PLACEHOLDER')
              "
            />
          </template>
          <template v-if="customVoiceConfig.authType === 'jwt'">
            <label class="flex items-center gap-2 text-sm text-n-slate-11">
              <input v-model="customVoiceConfig.useAgentJwt" type="checkbox" />
              {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.USE_AGENT_JWT') }}
            </label>
            <template v-if="!customVoiceConfig.useAgentJwt">
              <NextInput
                v-model="customVoiceConfig.jwtIssuer"
                :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_ISSUER.LABEL')"
                :placeholder="
                  $t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_ISSUER.PLACEHOLDER')
                "
              />
              <NextInput
                v-model="customVoiceConfig.jwtAudience"
                :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_AUDIENCE.LABEL')"
                :placeholder="
                  $t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_AUDIENCE.PLACEHOLDER')
                "
              />
              <NextInput
                v-model="customVoiceConfig.jwtSecret"
                type="password"
                :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_SECRET.LABEL')"
                :placeholder="
                  $t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_SECRET.PLACEHOLDER')
                "
              />
              <NextInput
                v-model="customVoiceConfig.jwtTtl"
                :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_TTL.LABEL')"
                :placeholder="
                  $t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_TTL.PLACEHOLDER')
                "
              />
            </template>
          </template>
          <div>
            <NextButton
              :label="$t('INBOX_MGMT.SETTINGS_POPUP.UPDATE')"
              :is-loading="isUpdatingVoiceConfig"
              @click="updateVoiceConfig"
            />
          </div>
        </div>
      </SettingsFieldSection>
    </template>
  </div>

  <div v-else-if="isALineChannel">
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.ADD.LINE_CHANNEL.API_CALLBACK.TITLE')"
      :help-text="$t('INBOX_MGMT.ADD.LINE_CHANNEL.API_CALLBACK.SUBTITLE')"
    >
      <woot-code :script="inbox.callback_webhook_url" lang="html" />
    </SettingsFieldSection>
  </div>
  <div v-else-if="isAWebWidgetInbox">
    <div class="space-y-4">
      <SettingsToggleSection
        :header="$t('INBOX_MGMT.SETTINGS_POPUP.ALLOWED_DOMAINS.TITLE')"
        :description="
          $t('INBOX_MGMT.SETTINGS_POPUP.ALLOWED_DOMAINS.DESCRIPTION')
        "
        hide-toggle
      >
        <template #editor>
          <woot-code
            :script="inbox.web_widget_script"
            lang="html"
            :codepen-title="`${inbox.name} - ViperChat Widget Test`"
            enable-code-pen
          />
          <TextArea
            v-model="allowedDomains"
            :placeholder="
              $t('INBOX_MGMT.SETTINGS_POPUP.ALLOWED_DOMAINS.PLACEHOLDER')
            "
            auto-height
            resize
            class="w-full [&>div]:!bg-transparent [&>div]:!border-none [&>div]:!border-0 [&>div]:px-0 [&>div]:pb-0 [&>div]:pt-0"
          />
          <div class="mt-3 flex justify-end">
            <NextButton
              :label="$t('INBOX_MGMT.SETTINGS_POPUP.UPDATE')"
              :is-loading="isUpdatingAllowedDomains"
              @click="updateAllowedDomains"
            />
          </div>
        </template>
      </SettingsToggleSection>
      <SettingsToggleSection
        v-model="allowMobileWebview"
        :header="$t('INBOX_MGMT.SETTINGS_POPUP.ALLOW_MOBILE_WEBVIEW.LABEL')"
        :description="
          $t('INBOX_MGMT.SETTINGS_POPUP.ALLOW_MOBILE_WEBVIEW.SUBTITLE')
        "
      />
    </div>

    <SettingsAccordion
      :title="$t('INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.TITLE')"
      class="mt-6"
    >
      <SettingsToggleSection
        :header="$t('INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.TITLE')"
        :description="
          $t('INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.DESCRIPTION')
        "
        hide-toggle
      >
        <template #editor>
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.SECRET_KEY') }}
          </p>
          <woot-code :script="inbox.hmac_token" />
          <p class="mt-1.5 text-label-small text-n-slate-11">
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.HMAC_DESCRIPTION') }}
            <a
              target="_blank"
              rel="noopener noreferrer"
              href="https://www.chatwoot.com/docs/product/channels/live-chat/sdk/identity-validation/"
              class="text-n-blue-11 hover:underline text-label-small"
            >
              {{
                $t('INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.VIEW_DOCS')
              }}
            </a>
          </p>
        </template>
      </SettingsToggleSection>

      <SettingsToggleSection
        v-model="hmacMandatory"
        :header="
          $t('INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.REQUIRE_LABEL')
        "
        :description="
          $t(
            'INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.REQUIRE_DESCRIPTION'
          )
        "
      />
    </SettingsAccordion>
  </div>
  <div v-else-if="isAPIInbox">
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.INBOX_IDENTIFIER')"
      :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.INBOX_IDENTIFIER_SUB_TEXT')"
    >
      <woot-code :script="inbox.inbox_identifier" />
    </SettingsFieldSection>

    <SettingsFieldSection
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_VERIFICATION')"
      :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_DESCRIPTION')"
    >
      <woot-code :script="inbox.hmac_token" />
    </SettingsFieldSection>
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_MANDATORY_VERIFICATION')"
      :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_MANDATORY_DESCRIPTION')"
    >
      <div class="flex gap-2 items-center">
        <input
          id="hmacMandatory"
          v-model="hmacMandatory"
          type="checkbox"
          @change="handleHmacFlag"
        />
        <label for="hmacMandatory" class="text-body-main text-n-slate-12">
          {{ $t('INBOX_MGMT.EDIT.ENABLE_HMAC.LABEL') }}
        </label>
      </div>
    </SettingsFieldSection>
  </div>
  <div v-else-if="isAnEmailChannel">
    <div>
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.FORWARD_EMAIL_TITLE')"
        :help-text="
          isForwardingEnabled
            ? $t('INBOX_MGMT.SETTINGS_POPUP.FORWARD_EMAIL_SUB_TEXT')
            : ''
        "
      >
        <woot-code
          v-if="isForwardingEnabled"
          :script="inbox.forward_to_email"
        />
        <div
          v-else
          class="py-2 px-3 bg-n-amber-3 outline-n-amber-4 text-n-amber-11 outline outline-1 -outline-offset-1 rounded-xl"
        >
          <p class="text-body-para mb-0">
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.FORWARD_EMAIL_NOT_CONFIGURED') }}
          </p>
        </div>
      </SettingsFieldSection>
    </div>
    <ImapSettings :inbox="inbox" />
    <SmtpSettings v-if="inbox.imap_enabled" :inbox="inbox" />
  </div>
  <div
    v-else-if="
      isAWhatsAppChannel &&
      !isATwilioChannel &&
      !isAWhatsAppBaileysChannel &&
      !isAWhatsAppWuzapiChannel &&
      !isAWhatsAppZapiChannel
    "
  >
    <div v-if="inbox.provider_config">
      <!-- Embedded Signup Section -->
      <template v-if="isEmbeddedSignupWhatsApp">
        <SettingsFieldSection
          v-if="whatsappAppId"
          :label="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_EMBEDDED_SIGNUP_TITLE')
          "
          :help-text="`${$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_EMBEDDED_SIGNUP_SUBHEADER')} ${$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_EMBEDDED_SIGNUP_DESCRIPTION')}`"
        >
          <div class="flex flex-col gap-1 items-start">
            <NextButton @click="handleReconfigure">
              {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_RECONFIGURE_BUTTON') }}
            </NextButton>
          </div>
        </SettingsFieldSection>
      </template>

      <!-- Manual Setup Section -->
      <template v-else>
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_WEBHOOK_TITLE')"
          :help-text="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_WEBHOOK_SUBHEADER')
          "
        >
          <woot-code :script="inbox.provider_config.webhook_verify_token" />
        </SettingsFieldSection>
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_TITLE')"
          :help-text="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_SUBHEADER')
          "
        >
          <woot-code :script="inbox.provider_config.api_key" />
        </SettingsFieldSection>
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_TITLE')"
          :help-text="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_SUBHEADER')
          "
        >
          <div
            class="flex flex-1 justify-between items-center whatsapp-settings--content"
          >
            <woot-input
              v-model="whatsAppInboxAPIKey"
              type="text"
              class="flex-1 mr-2 [&>input]:!mb-0"
              :placeholder="
                $t(
                  'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_PLACEHOLDER'
                )
              "
            />
            <NextButton
              :disabled="v$.whatsAppInboxAPIKey.$invalid"
              @click="updateWhatsAppInboxAPIKey"
            >
              {{
                $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_BUTTON')
              }}
            </NextButton>
          </div>
        </SettingsFieldSection>
      </template>
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_TITLE')"
        :help-text="
          $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_SUBHEADER')
        "
      >
        <NextButton :disabled="isSyncingTemplates" @click="syncTemplates">
          {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_BUTTON') }}
        </NextButton>
      </SettingsFieldSection>
    </div>
    <WhatsappReauthorize
      v-if="isEmbeddedSignupWhatsApp"
      ref="whatsappReauth"
      :inbox="inbox"
      class="hidden"
    />
  </div>
      <div v-else-if="isAWhatsAppBaileysChannel">
    <WhatsappLinkDeviceModal
      v-if="showLinkDeviceModal"
      :show="showLinkDeviceModal"
      :on-close="onCloseLinkDeviceModal"
      :inbox="inbox"
    />
    <div class="mx-8">
      <SettingsFieldSection
        :label="
          $t(
            'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_MANAGE_PROVIDER_CONNECTION_TITLE'
          )
        "
        :help-text="
          $t(
            'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_MANAGE_PROVIDER_CONNECTION_SUBHEADER'
          )
        "
      >
        <div class="flex flex-col gap-2">
          <InboxName
            :inbox="inbox"
            class="!text-lg !m-0"
            with-phone-number
            with-provider-connection-status
          />
          <NextButton class="w-fit" @click="onOpenLinkDeviceModal">
            {{
              $t(
                'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_MANAGE_PROVIDER_CONNECTION_BUTTON'
              )
            }}
          </NextButton>
        </div>
        <!-- Baileys QR Code Display -->
        <div v-if="isAWhatsAppBaileysChannel && inbox.provider_connection?.qr_data_url" class="flex flex-col gap-3 items-center mt-8">
          <p class="mt-2 text-sm text-n-slate-9">
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_BAILEYS_QR_CODE_TITLE') }}
          </p>
          <div class="rounded-lg shadow outline-1 outline-n-strong outline">
            <img
              :src="inbox.provider_connection.qr_data_url"
              alt="WhatsApp Baileys QR Code"
              class="rounded-lg size-48 dark:invert"
            />
          </div>
          <p class="text-sm text-n-slate-11">
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_BAILEYS_QR_CODE_INSTRUCTION') }}
          </p>
        </div>
      </SettingsFieldSection>
      <template v-if="!hasDefaultBaileysConfig && !inbox.provider_config?.provider_url">
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_PROVIDER_URL_TITLE')"
          :help-text="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_PROVIDER_URL_SUBHEADER')
          "
        >
          <div
            class="flex items-center justify-between flex-1 mt-2 whatsapp-settings--content"
          >
            <woot-input
              v-model="baileysProviderUrl"
              type="text"
              class="flex-1 mr-2 items-center"
              :placeholder="
                $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_PROVIDER_URL_PLACEHOLDER')
              "
              @keydown="v$.baileysProviderUrl.$touch"
            />
            <NextButton
              :disabled="
                v$.baileysProviderUrl.$invalid ||
                baileysProviderUrl === inbox.provider_config.provider_url
              "
              @click="updateBaileysProviderUrl"
            >
              {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_BUTTON') }}
            </NextButton>
          </div>
          <span v-if="v$.baileysProviderUrl.$error" class="text-red-400">
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_PROVIDER_URL_ERROR') }}
          </span>
        </SettingsFieldSection>
        <template v-if="inbox.provider_config.api_key">
          <SettingsFieldSection
            :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_TITLE')"
            :help-text="
              $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_SUBHEADER')
            "
          >
            <woot-code :script="inbox.provider_config.api_key" />
          </SettingsFieldSection>
        </template>
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_TITLE')"
          :help-text="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_SUBHEADER')
          "
        >
          <div
            class="flex items-center justify-between flex-1 mt-2 whatsapp-settings--content"
          >
            <woot-input
              v-model="whatsAppInboxAPIKey"
              type="text"
              class="flex-1 mr-2"
              :placeholder="
                $t(
                  'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_PLACEHOLDER'
                )
              "
            />
            <NextButton
              :disabled="
                v$.whatsAppInboxAPIKey.$invalid ||
                (!inbox.provider_config.api_key && !whatsAppInboxAPIKey) ||
                whatsAppInboxAPIKey === inbox.provider_config.api_key
              "
              @click="updateWhatsAppInboxAPIKey"
            >
              {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_BUTTON') }}
            </NextButton>
          </div>
        </SettingsFieldSection>
      </template>
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_MARK_AS_READ_TITLE')"
        :help-text="
          $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_MARK_AS_READ_SUBHEADER')
        "
      >
        <div class="flex items-center gap-2">
          <NextSwitch
            id="markAsRead"
            v-model="markAsRead"
            @change="updateWhatsAppMarkAsRead"
          />
          <label for="markAsRead">
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_MARK_AS_READ_LABEL') }}
          </label>
        </div>
      </SettingsFieldSection>
      <SettingsFieldSection
        :label="
          $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_PRESENCE_SUBSCRIBE_TITLE')
        "
        :help-text="
          $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_PRESENCE_SUBSCRIBE_SUBHEADER')
        "
      >
        <div class="flex items-center gap-2">
          <NextSwitch
            id="presenceSubscribe"
            v-model="presenceSubscribe"
            @change="updatePresenceSubscribe"
          />
          <label for="presenceSubscribe">
            {{
              $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_PRESENCE_SUBSCRIBE_LABEL')
            }}
          </label>
        </div>
      </SettingsFieldSection>
    </div>
  </div>
  <div v-else-if="isAWhatsAppZapiChannel">
    <WhatsappLinkDeviceModal
      v-if="showLinkDeviceModal"
      :show="showLinkDeviceModal"
      :on-close="onCloseLinkDeviceModal"
      :inbox="inbox"
    />
    <div class="mx-8">
      <SettingsFieldSection
        :label="
          $t(
            'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_MANAGE_PROVIDER_CONNECTION_TITLE'
          )
        "
        :help-text="
          $t(
            'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_MANAGE_PROVIDER_CONNECTION_SUBHEADER'
          )
        "
      >
        <div class="flex flex-col gap-2">
          <InboxName
            :inbox="inbox"
            class="!text-lg !m-0"
            with-phone-number
            with-provider-connection-status
          />
          <NextButton class="w-fit" @click="onOpenLinkDeviceModal">
            {{
              $t(
                'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_MANAGE_PROVIDER_CONNECTION_BUTTON'
              )
            }}
          </NextButton>
        </div>
      </SettingsFieldSection>

      <template v-if="inbox.provider_config.instance_id">
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_INSTANCE_ID_TITLE')"
          :help-text="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_INSTANCE_ID_SUBHEADER')
          "
        >
          <woot-code :script="inbox.provider_config.instance_id" />
        </SettingsFieldSection>
      </template>
      <SettingsFieldSection
        :label="
          $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_INSTANCE_ID_UPDATE_TITLE')
        "
        :help-text="
          $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_INSTANCE_ID_UPDATE_SUBHEADER')
        "
      >
        <div
          class="flex items-center justify-between flex-1 mt-2 whatsapp-settings--content"
        >
          <woot-input
            v-model="zapiInstanceIdUpdate"
            type="text"
            class="flex-1 mr-2"
          />
          <NextButton
            :disabled="
              v$.zapiInstanceIdUpdate.$invalid ||
              (!inbox.provider_config.instance_id && !zapiInstanceIdUpdate) ||
              zapiInstanceIdUpdate === inbox.provider_config.instance_id
            "
            @click="updateZapiInstanceId"
          >
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_BUTTON') }}
          </NextButton>
        </div>
      </SettingsFieldSection>

      <template v-if="inbox.provider_config.token">
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TOKEN_TITLE')"
          :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TOKEN_SUBHEADER')"
        >
          <woot-code :script="inbox.provider_config.token" secure />
        </SettingsFieldSection>
      </template>
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TOKEN_UPDATE_TITLE')"
        :help-text="
          $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TOKEN_UPDATE_SUBHEADER')
        "
      >
        <div
          class="flex items-center justify-between flex-1 mt-2 whatsapp-settings--content"
        >
          <woot-input
            v-model="zapiTokenUpdate"
            type="password"
            class="flex-1 mr-2"
          />
          <NextButton
            :disabled="
              v$.zapiTokenUpdate.$invalid ||
              (!inbox.provider_config.token && !zapiTokenUpdate) ||
              zapiTokenUpdate === inbox.provider_config.token
            "
            @click="updateZapiToken"
          >
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_BUTTON') }}
          </NextButton>
        </div>
      </SettingsFieldSection>

      <template v-if="inbox.provider_config.client_token">
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_CLIENT_TOKEN_TITLE')"
          :help-text="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_CLIENT_TOKEN_SUBHEADER')
          "
        >
          <woot-code :script="inbox.provider_config.client_token" secure />
        </SettingsFieldSection>
      </template>
      <SettingsFieldSection
        :label="
          $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_CLIENT_TOKEN_UPDATE_TITLE')
        "
        :help-text="
          $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_CLIENT_TOKEN_UPDATE_SUBHEADER')
        "
      >
        <div
          class="flex items-center justify-between flex-1 mt-2 whatsapp-settings--content"
        >
          <woot-input
            v-model="zapiClientTokenUpdate"
            type="password"
            class="flex-1 mr-2"
          />
          <NextButton
            :disabled="
              v$.zapiClientTokenUpdate.$invalid ||
              (!inbox.provider_config.client_token && !zapiClientTokenUpdate) ||
              zapiClientTokenUpdate === inbox.provider_config.client_token
            "
            @click="updateZapiClientToken"
          >
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_BUTTON') }}
          </NextButton>
        </div>
      </SettingsFieldSection>
    </div>
  </div>
  <div v-else-if="isAWhatsAppWuzapiChannel">
    <div class="mx-8">
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_MANAGE_PROVIDER_CONNECTION_TITLE')"
        :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_MANAGE_PROVIDER_CONNECTION_SUBHEADER')"
      >
        <div class="flex flex-col gap-2">
          <InboxName
            :inbox="inbox"
            class="!text-lg !m-0"
            with-phone-number
            with-provider-connection-status
          />
          <NextButton class="w-fit" @click="setupWuzapiConnection">
            {{
              $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_MANAGE_PROVIDER_CONNECTION_BUTTON')
            }}
          </NextButton>
        </div>
        <!-- Wuzapi QR Code Display -->
        <div v-if="inbox.provider_connection?.qr_data_url" class="flex flex-col gap-3 items-center mt-8">
          <p class="mt-2 text-sm text-n-slate-9">
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_WUZAPI_QR_CODE_TITLE') }}
          </p>
          <div class="rounded-lg shadow outline-1 outline-n-strong outline">
            <img
              :src="inbox.provider_connection.qr_data_url"
              alt="WhatsApp Wuzapi QR Code"
              class="rounded-lg size-48 dark:invert"
            />
          </div>
          <p class="text-sm text-n-slate-11">
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_WUZAPI_QR_CODE_INSTRUCTION') }}
          </p>
        </div>
      </SettingsFieldSection>
      <template v-if="!hasDefaultWuzapiConfig && !inbox.provider_config?.provider_url">
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_PROVIDER_URL_TITLE')"
          :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_PROVIDER_URL_SUBHEADER')"
        >
          <div class="flex items-center justify-between flex-1 mt-2 whatsapp-settings--content">
            <woot-input
              v-model="wuzapiProviderUrl"
              type="text"
              class="flex-1 mr-2 items-center"
              :placeholder="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_PROVIDER_URL_PLACEHOLDER')"
              @keydown="v$.wuzapiProviderUrl.$touch"
            />
            <NextButton
              :disabled="v$.wuzapiProviderUrl.$invalid || wuzapiProviderUrl === inbox.provider_config.provider_url"
              @click="updateWuzapiProviderUrl"
            >
              {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_BUTTON') }}
            </NextButton>
          </div>
          <span v-if="v$.wuzapiProviderUrl.$error" class="text-red-400">
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_PROVIDER_URL_ERROR') }}
          </span>
        </SettingsFieldSection>
      </template>
      <template v-if="inbox.provider_config.api_key">
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_TITLE')"
          :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_SUBHEADER')"
        >
          <woot-code :script="inbox.provider_config.api_key" />
        </SettingsFieldSection>
      </template>
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_TITLE')"
        :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_SUBHEADER')"
      >
        <div class="flex items-center justify-between flex-1 mt-2 whatsapp-settings--content">
          <woot-input
            v-model="wuzapiApiKeyUpdate"
            type="text"
            class="flex-1 mr-2"
            :placeholder="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_PLACEHOLDER')"
          />
          <NextButton
            :disabled="v$.wuzapiApiKeyUpdate.$invalid || (!inbox.provider_config.api_key && !wuzapiApiKeyUpdate) || wuzapiApiKeyUpdate === inbox.provider_config.api_key"
            @click="updateWuzapiApiKey"
          >
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_BUTTON') }}
          </NextButton>
        </div>
      </SettingsFieldSection>
      <template v-if="inbox.provider_config.admin_token">
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_ADMIN_TOKEN_TITLE')"
          :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_ADMIN_TOKEN_SUBHEADER')"
        >
          <woot-code :script="inbox.provider_config.admin_token" secure />
        </SettingsFieldSection>
      </template>
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_ADMIN_TOKEN_UPDATE_TITLE')"
        :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_ADMIN_TOKEN_UPDATE_SUBHEADER')"
      >
        <div class="flex items-center justify-between flex-1 mt-2 whatsapp-settings--content">
          <woot-input
            v-model="wuzapiAdminTokenUpdate"
            type="password"
            class="flex-1 mr-2"
          />
          <NextButton
            :disabled="v$.wuzapiAdminTokenUpdate.$invalid || (!inbox.provider_config.admin_token && !wuzapiAdminTokenUpdate) || wuzapiAdminTokenUpdate === inbox.provider_config.admin_token"
            @click="updateWuzapiAdminToken"
          >
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_BUTTON') }}
          </NextButton>
        </div>
      </SettingsFieldSection>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.whatsapp-settings--content {
  ::v-deep input {
    margin-bottom: 0;
  }
}
</style>
