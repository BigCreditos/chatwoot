<script>
import { mapGetters } from 'vuex';
import Avatar from 'next/avatar/Avatar.vue';

export default {
  components: {
    Avatar,
  },
  props: {
    contact: {
      type: Object,
      default: () => ({}),
    },
  },
  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
    }),
    groupName() {
      return this.currentChat.group_title || this.contact.name;
    },
    groupAvatar() {
      return (
        this.currentChat.group_picture ||
        this.currentChat.additional_attributes?.group_picture ||
        this.contact.thumbnail
      );
    },
    memberCount() {
      return this.currentChat.group_contacts_count || 0;
    },
  },
};
</script>

<template>
  <div class="flex flex-col items-center px-4 pt-4 pb-2">
    <Avatar
      :name="groupName"
      :src="groupAvatar"
      :size="64"
      class="mb-2"
      rounded-full
    />
    <h3 class="text-base font-semibold text-n-slate-12 text-center truncate max-w-full">
      {{ groupName }}
    </h3>
    <span v-if="memberCount" class="text-xs text-n-slate-11 mt-1">
      {{ memberCount }} membros
    </span>
  </div>
</template>
