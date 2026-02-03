import { useState, useCallback } from 'react';
import { useFileQueue } from '../../hooks/useFileQueue';
import { pickFiles } from '../../utils/filePicker';

export function FileDropZone() {
  const [isDragging, setIsDragging] = useState(false);
  const { addFilesToQueue, isProcessing } = useFileQueue();

  const handleSelectFiles = async () => {
    const files = await pickFiles();
    if (files.length > 0) {
      addFilesToQueue(files);
    }
  };

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(true);
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);
  }, []);

  const handleDrop = useCallback(
    async (e: React.DragEvent) => {
      e.preventDefault();
      e.stopPropagation();
      setIsDragging(false);

      // Note: Tauri drag-drop requires different handling
      // For now, use the file dialog
      await handleSelectFiles();
    },
    [handleSelectFiles]
  );

  return (
    <div
      className={`drop-zone ${isDragging ? 'dragging' : ''} ${isProcessing ? 'disabled' : ''}`}
      onClick={handleSelectFiles}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      <div className="drop-zone-content">
        <div className="drop-zone-icon">
          <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
            <polyline points="17 8 12 3 7 8" />
            <line x1="12" y1="3" x2="12" y2="15" />
          </svg>
        </div>
        <p className="drop-zone-title">
          {isProcessing ? 'Processing...' : 'Click to select files'}
        </p>
        <p className="drop-zone-subtitle">
          MP3, WAV, M4A, PDF, TXT, DOCX
        </p>
      </div>
    </div>
  );
}
