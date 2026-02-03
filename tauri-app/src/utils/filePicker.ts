import { open } from '@tauri-apps/api/dialog';
import { SUPPORTED_FORMATS, getFileExtension } from './fileUtils';

export async function pickFiles() {
  const selected = await open({
    multiple: true,
    filters: [
      {
        name: 'Audio/Document',
        extensions: SUPPORTED_FORMATS,
      },
    ],
  });

  if (!selected) {
    return [];
  }

  const paths = Array.isArray(selected) ? selected : [selected];
  return paths.map((path) => {
    const name = path.split('/').pop() || path;
    const format = getFileExtension(name);
    return { path, name, format, size: 0 };
  });
}
