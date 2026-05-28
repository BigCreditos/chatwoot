<script>
import addDays from 'date-fns/addDays';
import DatePicker from 'vue-datepicker-next';
export default {
  components: { DatePicker },
  props: {
    confirmText: {
      type: String,
      default: '',
    },
    placeholder: {
      type: String,
      default: '',
    },
    value: {
      type: Date,
      default: [],
    },
  },
  emits: ['change'],

  methods: {
    handleChange(value) {
      this.$emit('change', value);
    },
    disableBeforeToday(date) {
      const startOfToday = new Date();
      startOfToday.setHours(0, 0, 0, 0);
      return date < startOfToday;
    },
  },
};
</script>

<template>
  <div class="date-picker">
    <DatePicker
      type="datetime"
      confirm
      :clearable="false"
      :editable="false"
      :confirm-text="confirmText"
      :placeholder="placeholder"
      :value="value"
      :disabled-date="disableBeforeToday"
      @change="handleChange"
    />
  </div>
</template>
