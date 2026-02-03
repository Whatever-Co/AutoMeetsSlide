import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import { appLocalDataDir } from '@tauri-apps/api/path';
import { readTextFile, writeTextFile, createDir, exists } from '@tauri-apps/api/fs';
import type { Settings, WindowState } from './types';
import { DEFAULT_SETTINGS } from './types';

const SETTINGS_FILE = 'settings.json';

// Custom storage adapter for Tauri filesystem
const createTauriStorage = () => {
  let basePath: string | null = null;

  const getBasePath = async () => {
    if (!basePath) {
      basePath = await appLocalDataDir();
    }
    return basePath;
  };

  return {
    getItem: async (name: string): Promise<string | null> => {
      try {
        const base = await getBasePath();
        const path = `${base}${name}`;
        if (await exists(path)) {
          return await readTextFile(path);
        }
      } catch (e) {
        console.warn('Failed to read settings:', e);
      }
      return null;
    },
    setItem: async (name: string, value: string): Promise<void> => {
      try {
        const base = await getBasePath();
        // Ensure directory exists
        if (!(await exists(base))) {
          await createDir(base, { recursive: true });
        }
        await writeTextFile(`${base}${name}`, value);
      } catch (e) {
        console.warn('Failed to save settings:', e);
      }
    },
    removeItem: async (_name: string): Promise<void> => {
      // Not implemented - we don't need to remove settings
    },
  };
};

interface SettingsState extends Settings {
  // Actions
  setSystemPrompt: (prompt: string) => void;
  setDownloadFolder: (folder: string) => void;
  setWindowState: (state: WindowState) => void;
  updateWindowPosition: (x: number, y: number) => void;
  updateWindowSize: (width: number, height: number) => void;
  resetToDefaults: () => void;
  _hasHydrated: boolean;
  setHasHydrated: (value: boolean) => void;
}

export const useSettingsStore = create<SettingsState>()(
  persist(
    (set) => ({
      ...DEFAULT_SETTINGS,
      _hasHydrated: false,

      setSystemPrompt: (prompt) => set({ systemPrompt: prompt }),
      setDownloadFolder: (folder) => set({ downloadFolder: folder }),
      setWindowState: (state) => set({ windowState: state }),
      updateWindowPosition: (x, y) =>
        set((state) => ({
          windowState: { ...state.windowState, x, y },
        })),
      updateWindowSize: (width, height) =>
        set((state) => ({
          windowState: { ...state.windowState, width, height },
        })),
      resetToDefaults: () => set(DEFAULT_SETTINGS),
      setHasHydrated: (value) => set({ _hasHydrated: value }),
    }),
    {
      name: SETTINGS_FILE,
      storage: createJSONStorage(() => createTauriStorage()),
      onRehydrateStorage: () => (state) => {
        state?.setHasHydrated(true);
      },
    }
  )
);
