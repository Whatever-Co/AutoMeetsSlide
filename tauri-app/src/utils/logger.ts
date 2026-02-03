import { emit } from '@tauri-apps/api/event';
import { useAppStore } from '../store/appStore';
import type { LogType } from '../store/types';

export const logger = {
  log: (type: LogType, message: string) => {
    const store = useAppStore.getState();
    store.addLog(type, message);
    // Broadcast to debug window
    emit('log-entry', { type, message, timestamp: new Date().toISOString() });
  },
  info: (message: string) => logger.log('info', message),
  error: (message: string) => logger.log('error', message),
  success: (message: string) => logger.log('success', message),
  warning: (message: string) => logger.log('warning', message),
};
