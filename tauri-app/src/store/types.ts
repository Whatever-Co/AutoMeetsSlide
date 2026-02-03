export type FileStatus = 'pending' | 'processing' | 'completed' | 'error';
export type LogType = 'info' | 'error' | 'success' | 'warning';

export interface FileItem {
  id: string;
  path: string;
  name: string;
  format: string;
  size: number;
  duration?: number;
  status: FileStatus;
  outputPath?: string;
  error?: string;
  addedAt: number;
}

export interface LogEntry {
  id: string;
  type: LogType;
  message: string;
  timestamp: string;
}

export interface WindowState {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface Settings {
  systemPrompt: string;
  downloadFolder: string;
  windowState: WindowState;
}

export const DEFAULT_SETTINGS: Settings = {
  systemPrompt: 'Create a comprehensive slide deck from this content in Japanese.',
  downloadFolder: '',
  windowState: {
    x: 100,
    y: 100,
    width: 900,
    height: 700,
  },
};
