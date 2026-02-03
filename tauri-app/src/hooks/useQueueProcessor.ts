import { useEffect, useRef } from 'react';
import { homeDir } from '@tauri-apps/api/path';
import { useAppStore } from '../store/appStore';
import { useSettingsStore } from '../store/settingsStore';
import { useSidecar } from './useSidecar';
import { logger } from '../utils/logger';

/**
 * Hook that processes the file queue.
 * IMPORTANT: This should only be used in ONE component (MainApp).
 */
export function useQueueProcessor() {
  const {
    files,
    currentProcessingId,
    setCurrentProcessingId,
    updateFileStatus,
  } = useAppStore();
  const { downloadFolder, systemPrompt } = useSettingsStore();
  const { processFile } = useSidecar();

  // Use ref to prevent race conditions
  const isProcessingRef = useRef(false);

  useEffect(() => {
    // Skip if already processing (using ref for immediate check)
    if (isProcessingRef.current) return;
    if (currentProcessingId) return;

    const nextPending = files.find((f) => f.status === 'pending');
    if (!nextPending) return;

    // Mark as processing immediately via ref
    isProcessingRef.current = true;

    const processNext = async () => {
      setCurrentProcessingId(nextPending.id);
      updateFileStatus(nextPending.id, 'processing');

      try {
        // Get download folder or default to ~/Downloads
        let outputDir = downloadFolder;
        if (!outputDir) {
          const home = await homeDir();
          outputDir = `${home}Downloads`;
        }

        logger.info(`Processing file: ${nextPending.name}`);
        const outputPath = await processFile(
          nextPending.path,
          outputDir,
          systemPrompt || undefined
        );

        if (outputPath) {
          updateFileStatus(nextPending.id, 'completed', { outputPath });
          logger.success(`Completed: ${nextPending.name}`);
        } else {
          updateFileStatus(nextPending.id, 'error', {
            error: 'Processing failed - no output',
          });
          logger.error(`Failed: ${nextPending.name}`);
        }
      } catch (e) {
        const errorMsg = e instanceof Error ? e.message : String(e);
        updateFileStatus(nextPending.id, 'error', { error: errorMsg });
        logger.error(`Error processing ${nextPending.name}: ${errorMsg}`);
      } finally {
        setCurrentProcessingId(null);
        isProcessingRef.current = false;
      }
    };

    processNext();
  }, [files, currentProcessingId, downloadFolder, systemPrompt, setCurrentProcessingId, updateFileStatus, processFile]);
}
