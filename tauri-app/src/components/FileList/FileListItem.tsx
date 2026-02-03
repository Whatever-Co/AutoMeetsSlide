import type { FileItem } from '../../store/types';
import { useFileQueue } from '../../hooks/useFileQueue';
import { getFileIcon, formatFileSize, formatDuration, openFileAndMinimize } from '../../utils/fileUtils';

interface Props {
  file: FileItem;
}

export function FileListItem({ file }: Props) {
  const { removeFromQueue } = useFileQueue();

  const statusInfo = {
    pending: { label: 'Pending', className: 'status-pending' },
    processing: { label: 'Processing...', className: 'status-processing' },
    completed: { label: 'Completed', className: 'status-completed' },
    error: { label: 'Failed', className: 'status-error' },
  };

  const { label, className } = statusInfo[file.status];

  return (
    <div className={`file-item ${className}`}>
      <div className="file-icon">{getFileIcon(file.format)}</div>

      <div className="file-info">
        <div className="file-name">{file.name}</div>
        <div className="file-meta">
          <span className="file-format">{file.format.toUpperCase()}</span>
          {file.duration !== undefined && (
            <span className="file-duration">{formatDuration(file.duration)}</span>
          )}
          {file.size > 0 && <span className="file-size">{formatFileSize(file.size)}</span>}
        </div>
        {file.error && <div className="file-error">{file.error}</div>}
      </div>

      <div className="file-actions">
        <span className={`status-badge ${className}`}>{label}</span>

        {file.status === 'completed' && file.outputPath && (
          <button
            className="action-button"
            onClick={() => openFileAndMinimize(file.outputPath!)}
            title="Show in Finder"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z" />
            </svg>
            Open
          </button>
        )}

        {file.status === 'pending' && (
          <button
            className="action-button remove"
            onClick={() => removeFromQueue(file.id)}
            title="Remove"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <line x1="18" y1="6" x2="6" y2="18" />
              <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
        )}
      </div>
    </div>
  );
}
