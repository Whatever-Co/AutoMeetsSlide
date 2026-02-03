import { useEffect, useRef } from 'react';
import { appWindow } from '@tauri-apps/api/window';
import { PhysicalPosition, PhysicalSize } from '@tauri-apps/api/window';
import { useSettingsStore } from '../store/settingsStore';

const DEBOUNCE_MS = 500;

export function useWindowState() {
  const { windowState, updateWindowPosition, updateWindowSize, _hasHydrated } = useSettingsStore();
  const hasRestored = useRef(false);
  const debounceTimer = useRef<number | null>(null);

  // Restore window state on mount (only once, after settings are loaded)
  useEffect(() => {
    if (!_hasHydrated || hasRestored.current) return;

    const restoreState = async () => {
      try {
        const { x, y, width, height } = windowState;

        // Only restore if we have valid values
        if (x > 0 || y > 0) {
          await appWindow.setPosition(new PhysicalPosition(x, y));
        }
        if (width > 0 && height > 0) {
          await appWindow.setSize(new PhysicalSize(width, height));
        }

        hasRestored.current = true;
      } catch (e) {
        console.error('Failed to restore window state:', e);
      }
    };

    restoreState();
  }, [_hasHydrated, windowState]);

  // Listen for window move/resize events
  useEffect(() => {
    let unlistenMove: (() => void) | null = null;
    let unlistenResize: (() => void) | null = null;

    const setupListeners = async () => {
      // Listen for move events
      unlistenMove = await appWindow.onMoved((event) => {
        const { x, y } = event.payload;

        // Debounce the save
        if (debounceTimer.current) {
          clearTimeout(debounceTimer.current);
        }
        debounceTimer.current = window.setTimeout(() => {
          updateWindowPosition(x, y);
        }, DEBOUNCE_MS);
      });

      // Listen for resize events
      unlistenResize = await appWindow.onResized((event) => {
        const { width, height } = event.payload;

        // Debounce the save
        if (debounceTimer.current) {
          clearTimeout(debounceTimer.current);
        }
        debounceTimer.current = window.setTimeout(() => {
          updateWindowSize(width, height);
        }, DEBOUNCE_MS);
      });
    };

    setupListeners();

    return () => {
      if (unlistenMove) unlistenMove();
      if (unlistenResize) unlistenResize();
      if (debounceTimer.current) {
        clearTimeout(debounceTimer.current);
      }
    };
  }, [updateWindowPosition, updateWindowSize]);
}
