import { open } from '@tauri-apps/api/shell';
import { readDir } from '@tauri-apps/api/fs';
import { downloadDir } from '@tauri-apps/api/path';
import { appWindow } from '@tauri-apps/api/window';

export const SUPPORTED_FORMATS = ['mp3', 'wav', 'm4a', 'pdf', 'txt', 'docx'];

export function getFileExtension(filename: string): string {
  const parts = filename.split('.');
  return parts.length > 1 ? parts.pop()!.toLowerCase() : '';
}

export function formatFileSize(bytes: number): string {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`;
}

export function formatDuration(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}:${secs.toString().padStart(2, '0')}`;
}

export function getFileIcon(format: string): string {
  switch (format.toLowerCase()) {
    case 'mp3':
    case 'wav':
    case 'm4a':
      return '🎵';
    case 'pdf':
      return '📄';
    case 'txt':
      return '📝';
    case 'docx':
      return '📃';
    default:
      return '📁';
  }
}

export function isAudioFormat(format: string): boolean {
  return ['mp3', 'wav', 'm4a'].includes(format.toLowerCase());
}

export async function openInFinder(filePath: string): Promise<void> {
  await open(encodeURI(filePath));
}

export async function openFileAndMinimize(filePath: string): Promise<void> {
  await appWindow.minimize();
  await openInFinder(filePath);
}

export async function openLatestSlidesPdf(): Promise<void> {
  const downloads = await downloadDir();
  const entries = await readDir(downloads);
  const slides = entries.filter((entry) => `${entry.path}`.endsWith('_slides.pdf'));
  slides.sort((a, b) => `${a.path}`.localeCompare(`${b.path}`));
  const latest = slides[slides.length - 1];
  await openFileAndMinimize(latest.path);
}

export async function revealFile(filePath: string): Promise<void> {
  try {
    // macOS: use 'open -R' to reveal file in Finder
    await open(`file://${filePath}`);
  } catch (e) {
    console.error('Failed to reveal file:', e);
  }
}
