import { useCallback } from 'react';
import { useAppStore } from '../store/appStore';

/**
 * Hook for file queue data and actions.
 * Does NOT contain processing logic - use useQueueProcessor for that.
 */
export function useFileQueue() {
  const {
    files,
    currentProcessingId,
    addFile,
    addFiles,
    removeFile,
  } = useAppStore();

  const addFileToQueue = useCallback(
    (file: { path: string; name: string; format: string; size: number; duration?: number }) => {
      addFile(file);
    },
    [addFile]
  );

  const addFilesToQueue = useCallback(
    (newFiles: { path: string; name: string; format: string; size: number; duration?: number }[]) => {
      addFiles(newFiles);
    },
    [addFiles]
  );

  const removeFromQueue = useCallback(
    (id: string) => {
      const file = files.find((f) => f.id === id);
      if (file && file.status === 'pending') {
        removeFile(id);
      }
    },
    [files, removeFile]
  );

  const pendingCount = files.filter((f) => f.status === 'pending').length;
  const processingCount = files.filter((f) => f.status === 'processing').length;
  const completedCount = files.filter((f) => f.status === 'completed').length;
  const errorCount = files.filter((f) => f.status === 'error').length;

  return {
    files,
    isProcessing: currentProcessingId !== null,
    addFileToQueue,
    addFilesToQueue,
    removeFromQueue,
    pendingCount,
    processingCount,
    completedCount,
    errorCount,
  };
}
