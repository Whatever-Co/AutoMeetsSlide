import { create } from 'zustand';
import type { FileItem, LogEntry, FileStatus } from './types';

interface AppState {
  // Auth
  isAuthenticated: boolean | null;
  setIsAuthenticated: (value: boolean | null) => void;

  // Files
  files: FileItem[];
  addFile: (file: Omit<FileItem, 'id' | 'status' | 'addedAt'>) => void;
  addFiles: (files: Omit<FileItem, 'id' | 'status' | 'addedAt'>[]) => void;
  updateFileStatus: (id: string, status: FileStatus, extra?: Partial<FileItem>) => void;
  removeFile: (id: string) => void;
  clearCompletedFiles: () => void;

  // Processing
  currentProcessingId: string | null;
  setCurrentProcessingId: (id: string | null) => void;

  // Status
  status: string;
  setStatus: (status: string) => void;

  // Logs
  logs: LogEntry[];
  addLog: (type: LogEntry['type'], message: string) => void;
  clearLogs: () => void;

  // Settings modal
  isSettingsOpen: boolean;
  setSettingsOpen: (open: boolean) => void;
}

export const useAppStore = create<AppState>((set) => ({
  // Auth
  isAuthenticated: null,
  setIsAuthenticated: (value) => set({ isAuthenticated: value }),

  // Files
  files: [],
  addFile: (file) =>
    set((state) => ({
      files: [
        ...state.files,
        {
          ...file,
          id: crypto.randomUUID(),
          status: 'pending',
          addedAt: Date.now(),
        },
      ],
    })),
  addFiles: (files) =>
    set((state) => ({
      files: [
        ...state.files,
        ...files.map((file) => ({
          ...file,
          id: crypto.randomUUID(),
          status: 'pending' as const,
          addedAt: Date.now(),
        })),
      ],
    })),
  updateFileStatus: (id, status, extra) =>
    set((state) => ({
      files: state.files.map((f) =>
        f.id === id ? { ...f, status, ...extra } : f
      ),
    })),
  removeFile: (id) =>
    set((state) => ({
      files: state.files.filter((f) => f.id !== id),
    })),
  clearCompletedFiles: () =>
    set((state) => ({
      files: state.files.filter((f) => f.status !== 'completed'),
    })),

  // Processing
  currentProcessingId: null,
  setCurrentProcessingId: (id) => set({ currentProcessingId: id }),

  // Status
  status: 'Ready',
  setStatus: (status) => set({ status }),

  // Logs
  logs: [],
  addLog: (type, message) =>
    set((state) => ({
      logs: [
        ...state.logs,
        {
          id: crypto.randomUUID(),
          type,
          message,
          timestamp: new Date().toISOString(),
        },
      ],
    })),
  clearLogs: () => set({ logs: [] }),

  // Settings modal
  isSettingsOpen: false,
  setSettingsOpen: (open) => set({ isSettingsOpen: open }),
}));
