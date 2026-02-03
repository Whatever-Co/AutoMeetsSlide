import { useState, useEffect } from 'react';
import { open } from '@tauri-apps/api/dialog';
import { homeDir } from '@tauri-apps/api/path';
import { useSettingsStore } from '../../store/settingsStore';

interface Props {
  onClose: () => void;
}

export function SettingsModal({ onClose }: Props) {
  const { systemPrompt, downloadFolder, setSystemPrompt, setDownloadFolder } = useSettingsStore();
  const [localPrompt, setLocalPrompt] = useState(systemPrompt);
  const [localFolder, setLocalFolder] = useState(downloadFolder);

  useEffect(() => {
    // Set default download folder if empty
    if (!localFolder) {
      homeDir().then((home) => {
        setLocalFolder(`${home}Downloads`);
      });
    }
  }, []);

  const handleSelectFolder = async () => {
    const selected = await open({
      directory: true,
      multiple: false,
    });
    if (selected && typeof selected === 'string') {
      setLocalFolder(selected);
    }
  };

  const handleSave = () => {
    setSystemPrompt(localPrompt);
    setDownloadFolder(localFolder);
    onClose();
  };

  const handleCancel = () => {
    onClose();
  };

  // Close on escape
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onClose();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose]);

  return (
    <div className="modal-overlay" onClick={handleCancel}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h2 className="modal-title">Settings</h2>
          <button className="modal-close" onClick={handleCancel}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <line x1="18" y1="6" x2="6" y2="18" />
              <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
        </div>

        <div className="modal-content">
          <div className="form-group">
            <label className="form-label">System Prompt</label>
            <p className="form-hint">
              Instructions for NotebookLM when generating slides
            </p>
            <textarea
              className="form-textarea"
              value={localPrompt}
              onChange={(e) => setLocalPrompt(e.target.value)}
              rows={4}
              placeholder="e.g., Create a comprehensive slide deck from this content in Japanese..."
            />
          </div>

          <div className="form-group">
            <label className="form-label">Download Folder</label>
            <p className="form-hint">
              Where completed slide decks will be saved
            </p>
            <div className="folder-picker">
              <input
                className="form-input folder-path"
                type="text"
                value={localFolder}
                onChange={(e) => setLocalFolder(e.target.value)}
                readOnly
              />
              <button className="folder-button" onClick={handleSelectFolder}>
                Choose...
              </button>
            </div>
          </div>
        </div>

        <div className="modal-footer">
          <button className="button secondary" onClick={handleCancel}>
            Cancel
          </button>
          <button className="button primary" onClick={handleSave}>
            Save
          </button>
        </div>
      </div>
    </div>
  );
}
