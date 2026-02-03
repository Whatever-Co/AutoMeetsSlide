import { useState, useCallback } from 'react';
import { useFileQueue } from '../../hooks/useFileQueue';
import { FileListItem } from './FileListItem';
import { pickFiles } from '../../utils/filePicker';

export function FileList() {
  const { files, addFilesToQueue } = useFileQueue();
  const [isDragging, setIsDragging] = useState(false);

  if (files.length === 0) {
    return null;
  }

  // Sort: processing first, then pending, then completed, then error
  const sortedFiles = [...files].sort((a, b) => {
    const order = { processing: 0, pending: 1, completed: 2, error: 3 };
    return order[a.status] - order[b.status];
  });

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

  const handleDrop = useCallback(async (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);

    const newFiles = await pickFiles();
    if (newFiles.length > 0) {
      addFilesToQueue(newFiles);
    }
  }, [addFilesToQueue]);

  return (
    <div
      className={`file-list ${isDragging ? 'dragging' : ''}`}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      <h2 className="file-list-title">Files</h2>
      <div className="file-list-items">
        {sortedFiles.map((file) => (
          <FileListItem key={file.id} file={file} />
        ))}
      </div>
    </div>
  );
}
