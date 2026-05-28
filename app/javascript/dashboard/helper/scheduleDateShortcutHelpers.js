import addDays from 'date-fns/addDays';
import addHours from 'date-fns/addHours';
import addMinutes from 'date-fns/addMinutes';
import format from 'date-fns/format';

export const SHORTCUT_KEYS = [
  { key: 'in_30_min', label: 'Em 30 minutos' },
  { key: 'in_1_hour', label: 'Em 1 hora' },
  { key: 'in_2_hours', label: 'Em 2 horas' },
  { key: 'in_3_hours', label: 'Em 3 horas' },
  { key: 'in_6_hours', label: 'Em 6 horas' },
  { key: 'tomorrow', label: 'Amanhã' },
  { key: 'next_week', label: 'Próxima semana' },
];

export const getScheduleShortcuts = () => {
  const now = new Date();
  const hours = now.getHours();
  const minutes = now.getMinutes();
  const remainderToNextHour = 60 - minutes;

  const shortcuts = [
    {
      key: 'in_30_min',
      label: 'Em 30 minutos',
      getDate: () => addMinutes(now, 30),
    },
    {
      key: 'in_1_hour',
      label: 'Em 1 hora',
      getDate: () => addHours(now, 1),
    },
    {
      key: 'in_2_hours',
      label: 'Em 2 horas',
      getDate: () => addHours(now, 2),
    },
    {
      key: 'in_3_hours',
      label: 'Em 3 horas',
      getDate: () => addHours(now, 3),
    },
    {
      key: 'in_6_hours',
      label: 'Em 6 horas',
      getDate: () => addHours(now, 6),
    },
    {
      key: 'tomorrow',
      label: 'Amanhã',
      getDate: () => addDays(now, 1),
    },
    {
      key: 'next_week',
      label: 'Próxima semana',
      getDate: () => addDays(now, 7),
    },
  ];

  return shortcuts;
};

export const parseNaturalDate = dateTime => {
  if (!dateTime) return null;
  const date = new Date(dateTime);
  return isNaN(date.getTime()) ? null : date;
};

export const formatFullDateTime = date => {
  if (!date) return '';
  const d = new Date(date);
  if (isNaN(d.getTime())) return '';
  return format(d, "dd/MM/yyyy 'às' HH:mm");
};
