<script setup>
import { useI18n } from 'vue-i18n';

import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';

defineProps({
  labelMenuItems: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['updateLabel']);

const { t } = useI18n();
</script>

<template>
  <Popover align="end" :show-content-border="false">
    <template #default="{ isOpen }">
      <button
        class="flex items-center gap-1 px-2 py-1 rounded-md outline-dashed h-6 outline-1 outline-n-slate-6 hover:bg-n-alpha-2"
        :class="{ 'bg-n-alpha-2': isOpen }"
      >
        <span class="i-lucide-plus" />
        <span class="text-sm text-n-slate-11">
          {{ t('LABEL.TAG_BUTTON') }}
        </span>
      </button>
    </template>
    <template #content="{ hide }">
      <DropdownMenu
        :menu-items="labelMenuItems"
        show-search
        class="w-48 overflow-y-auto max-h-52 !border-none !outline-none !shadow-none !static !backdrop-blur-none !bg-transparent"
        @action="
          val => {
            emit('updateLabel', val);
            hide();
          }
        "
      >
        <template #thumbnail="{ item }">
          <div
            class="rounded-sm size-2"
            :style="{ backgroundColor: item.thumbnail.color }"
          />
        </template>
      </DropdownMenu>
    </template>
  </Popover>
</template>
