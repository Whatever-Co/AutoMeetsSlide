import { useEffect } from 'react';
import { register, unregister } from '@tauri-apps/api/globalShortcut';
import { WebviewWindow } from '@tauri-apps/api/window';
import { useAppStore } from '../store/appStore';
import { useFileQueue } from '../hooks/useFileQueue';
import { useQueueProcessor } from '../hooks/useQueueProcessor';
import { useWindowState } from '../hooks/useWindowState';
import { FileList } from './FileList/FileList';
import { FileDropZone } from './FileList/FileDropZone';
import { SettingsModal } from './Settings/SettingsModal';
import { openLatestSlidesPdf } from '../utils/fileUtils';
import { logger } from '../utils/logger';
import '../styles/index.css';

export function MainApp() {
  const { isSettingsOpen, setSettingsOpen } = useAppStore();

  // Handle window position/size persistence
  useWindowState();

  // Process file queue - ONLY called here to prevent duplicate processing
  useQueueProcessor();

  const { files } = useFileQueue();

  // Register Cmd+Shift+D for debug window
  useEffect(() => {
    const shortcut = 'CommandOrControl+Shift+D';

    const openDebugWindow = async () => {
      try {
        let debugWindow = WebviewWindow.getByLabel('debug');
        if (debugWindow) {
          await debugWindow.show();
          await debugWindow.setFocus();
        } else {
          debugWindow = new WebviewWindow('debug', {
            url: 'debug.html',
            title: 'Debug Console',
            width: 700,
            height: 500,
            resizable: true,
          });
        }
      } catch (e) {
        console.error('Failed to open debug window:', e);
      }
    };

    register(shortcut, openDebugWindow).catch(console.error);

    return () => {
      unregister(shortcut).catch(console.error);
    };
  }, []);

  return (
    <div className="main-app">
      {/* Header */}
      <header className="app-header">
        <div className="header-right">
          {import.meta.env.DEV && (
            <button
              className="debug-button"
              onClick={() => {
                logger.info('Debug open latest slides start');
                openLatestSlidesPdf().then(() => {
                  logger.success('Debug open latest slides resolved');
                });
              }}
              title="Debug: open latest *_slides.pdf in Downloads"
            >
              Debug Open Latest PDF
            </button>
          )}
          <button
            className="icon-button"
            onClick={() => setSettingsOpen(true)}
            title="Settings"
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <circle cx="12" cy="12" r="3" />
              <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z" />
            </svg>
          </button>
        </div>
      </header>

      {/* Main Content */}
      <main className="app-content">
        {files.length === 0 && <FileDropZone />}
        {files.length > 0 && <FileList />}
      </main>

      {/* Settings Modal */}
      {isSettingsOpen && <SettingsModal onClose={() => setSettingsOpen(false)} />}
    </div>
  );
}
