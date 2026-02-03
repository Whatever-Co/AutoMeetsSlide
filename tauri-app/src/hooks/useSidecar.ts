import { Command } from '@tauri-apps/api/shell';
import { useAppStore } from '../store/appStore';
import { logger } from '../utils/logger';

interface SidecarResponse {
  status?: string;
  message?: string;
  error?: string;
  authenticated?: boolean;
  output_path?: string;
}

export function useSidecar() {
  const { setIsAuthenticated, setStatus } = useAppStore();

  const runSidecar = async (args: string[]): Promise<SidecarResponse | null> => {
    logger.info(`[CMD] Running: notebooklm-cli ${args.join(' ')}`);

    return new Promise((resolve, reject) => {
      try {
        const command = Command.sidecar('binaries/notebooklm-cli', args);
        let lastResponse: SidecarResponse | null = null;

        const handleLine = (line: string) => {
          logger.info(`[stdout] ${line}`);
          try {
            const json: SidecarResponse = JSON.parse(line);
            lastResponse = json;

            if (json.error) {
              logger.error(`[error] ${json.error}`);
              setStatus(`Error: ${json.error}`);
            } else if (json.status) {
              setStatus(json.message || json.status);
              if (json.status === 'done') {
                logger.success(json.message || 'Completed');
              }
              if (json.authenticated !== undefined) {
                setIsAuthenticated(json.authenticated);
              }
              if (json.output_path) {
                logger.success(`Output: ${json.output_path}`);
              }
            }
          } catch {
            // Non-JSON output
          }
        };

        command.stdout.on('data', handleLine);
        command.stderr.on('data', (line: string) => {
          logger.error(`[stderr] ${line}`);
        });

        command.on('close', (data: { code: number }) => {
          logger.info(`[close] code=${data.code}`);
          resolve(lastResponse);
        });

        command.on('error', (error: Error) => {
          logger.error(`[CMD error] ${error}`);
          reject(error);
        });

        command.spawn();
      } catch (e) {
        logger.error(`[CMD error] ${e}`);
        reject(e);
      }
    });
  };

  const checkAuth = async (): Promise<boolean> => {
    logger.info('[checkAuth] Starting...');
    setStatus('Checking authentication...');
    try {
      await runSidecar(['check-auth']);
      return useAppStore.getState().isAuthenticated ?? false;
    } catch (e) {
      logger.error(`[checkAuth] Exception: ${e}`);
      return false;
    }
  };

  const login = async (): Promise<boolean> => {
    logger.info('Starting login process...');
    setStatus('Opening browser for login...');
    try {
      await runSidecar(['login']);
      await checkAuth();
      return useAppStore.getState().isAuthenticated ?? false;
    } catch (e) {
      logger.error(`[login] Exception: ${e}`);
      return false;
    }
  };

  const processFile = async (
    filePath: string,
    outputDir: string,
    systemPrompt?: string
  ): Promise<string | null> => {
    logger.info(`Processing: ${filePath}`);
    setStatus('Processing file...');

    const args = ['process', filePath, outputDir];
    if (systemPrompt) {
      args.push('--system-prompt', systemPrompt);
    }

    try {
      const response = await runSidecar(args);
      return response?.output_path || null;
    } catch (e) {
      logger.error(`[process] Exception: ${e}`);
      return null;
    }
  };

  return { runSidecar, checkAuth, login, processFile };
}
