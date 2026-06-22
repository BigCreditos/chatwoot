import { format, isValid } from 'date-fns';

export const isReachoutRestricted = (lock, connection, now = Date.now()) => {
  if (!lock?.is_active) return false;
  if (connection !== 'open') return false;
  if (!lock.time_enforcement_ends) return true;
  const deadline = new Date(lock.time_enforcement_ends);
  if (!isValid(deadline)) return true;
  return deadline.getTime() > now;
};

export const reachoutRestrictionDeadline = lock => {
  if (!lock?.time_enforcement_ends) return '';
  const deadline = new Date(lock.time_enforcement_ends);
  return isValid(deadline) ? format(deadline, 'dd/MM/yyyy HH:mm') : '';
};

const CAP_BANNER_STATUSES = ['FIRST_WARNING', 'SECOND_WARNING', 'CAPPED'];

export const isMessageCapped = (cap, connection) => {
  if (connection !== 'open') return false;
  return CAP_BANNER_STATUSES.includes(cap?.capping_status);
};

export const isMessageCapReached = cap => cap?.capping_status === 'CAPPED';

export const messageCapQuota = cap => {
  const total = Number(cap?.total_quota);
  if (!Number.isFinite(total) || total <= 0) return null;
  const used = Number(cap?.used_quota) || 0;
  return { used, total };
};
