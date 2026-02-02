import { useState, useEffect } from "react";
import { Command } from "@tauri-apps/api/shell";
import { open } from "@tauri-apps/api/dialog";
import { homeDir } from "@tauri-apps/api/path";
import { writeTextFile } from "@tauri-apps/api/fs";

const DEBUG_LOG_PATH = "/tmp/tauri-debug.log";

interface LogEntry {
  type: "info" | "error" | "success";
  message: string;
  time: string;
}

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState<boolean | null>(null);
  const [status, setStatus] = useState("Checking authentication...");
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [isProcessing, setIsProcessing] = useState(false);

  // Write all logs to file whenever logs change
  useEffect(() => {
    if (logs.length > 0) {
      const content = logs
        .map((l) => `[${l.time}] [${l.type.toUpperCase()}] ${l.message}`)
        .join("\n");
      writeTextFile(DEBUG_LOG_PATH, content).catch(() => {});
    }
  }, [logs]);

  const addLog = (type: LogEntry["type"], message: string) => {
    const time = new Date().toISOString();
    setLogs((prev) => [...prev, { type, message, time }]);
  };

  const runSidecar = async (args: string[]): Promise<void> => {
    addLog("info", `[CMD] Running: notebooklm-cli ${args.join(" ")}`);

    return new Promise((resolve, reject) => {
      try {
        const command = Command.sidecar("binaries/notebooklm-cli", args);
        addLog("info", "[CMD] Sidecar command created");

        const handleLine = (line: string) => {
          addLog("info", `[stdout] ${line}`);
          try {
            const json = JSON.parse(line);
            if (json.error) {
              addLog("error", `[error] ${json.error}`);
              setStatus(`Error: ${json.error}`);
            } else if (json.status) {
              setStatus(json.message);
              if (json.status === "done") {
                addLog("success", json.message);
              }
              if (json.authenticated !== undefined) {
                addLog("info", `[auth] authenticated=${json.authenticated}`);
                setIsAuthenticated(json.authenticated);
              }
              if (json.output_path) {
                addLog("success", `Output: ${json.output_path}`);
              }
            }
          } catch {
            addLog("info", `[raw] ${line}`);
          }
        };

        command.stdout.on("data", handleLine);
        command.stderr.on("data", (line: string) => {
          addLog("error", `[stderr] ${line}`);
        });

        command.on("close", (data: { code: number }) => {
          addLog("info", `[close] code=${data.code}`);
          resolve();
        });

        command.on("error", (error: Error) => {
          addLog("error", `[CMD error] ${error}`);
          reject(error);
        });

        command.spawn();
        addLog("info", "[CMD] Process spawned");
      } catch (e) {
        addLog("error", `[CMD error] ${e}`);
        reject(e);
      }
    });
  };

  const checkAuth = async () => {
    addLog("info", "[checkAuth] Starting...");
    setStatus("Checking authentication...");
    try {
      await runSidecar(["check-auth"]);
      addLog("info", "[checkAuth] Completed");
    } catch (e) {
      addLog("error", `[checkAuth] Exception: ${e}`);
    }
  };

  const handleLogin = async () => {
    setIsProcessing(true);
    setLogs([]);
    addLog("info", "Starting login process...");
    setStatus("Opening browser for login...");

    try {
      await runSidecar(["login"]);
      await checkAuth();
    } finally {
      setIsProcessing(false);
    }
  };

  const handleSelectFile = async () => {
    const selected = await open({
      multiple: false,
      filters: [
        {
          name: "Audio/Document",
          extensions: ["mp3", "wav", "m4a", "pdf", "txt", "docx"],
        },
      ],
    });

    if (selected && typeof selected === "string") {
      await handleProcess(selected);
    }
  };

  const handleProcess = async (filePath: string) => {
    setIsProcessing(true);
    setLogs([]);
    addLog("info", `Processing: ${filePath}`);

    try {
      const home = await homeDir();
      const outputDir = `${home}Downloads`;
      await runSidecar(["process", filePath, outputDir]);
    } finally {
      setIsProcessing(false);
    }
  };

  useEffect(() => {
    addLog("info", "App mounted, initializing...");
    checkAuth().catch((e) => {
      setStatus(`Init error: ${e}`);
      addLog("error", `Init error: ${String(e)}`);
    });
  }, []);

  return (
    <div style={{ padding: 20, fontFamily: "system-ui, sans-serif", maxWidth: 800, margin: "0 auto" }}>
      <h1 style={{ marginBottom: 8 }}>NotebookLM Slide Generator</h1>
      <p style={{ color: "#666", marginTop: 0 }}>
        Upload audio/document → Generate slides via NotebookLM → Download PDF
      </p>

      {/* Auth Status */}
      <div
        style={{
          padding: 12,
          marginBottom: 20,
          borderRadius: 8,
          background: isAuthenticated === null ? "#f5f5f5" : isAuthenticated ? "#e8f5e9" : "#fff3e0",
          border: `1px solid ${isAuthenticated === null ? "#ddd" : isAuthenticated ? "#4caf50" : "#ff9800"}`,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <span>
            {isAuthenticated === null
              ? "⏳ Checking..."
              : isAuthenticated
              ? "✅ Logged in to NotebookLM"
              : "⚠️ Not logged in"}
          </span>
          {!isAuthenticated && (
            <button
              onClick={handleLogin}
              disabled={isProcessing}
              style={{
                padding: "8px 16px",
                background: "#1976d2",
                color: "white",
                border: "none",
                borderRadius: 4,
                cursor: isProcessing ? "not-allowed" : "pointer",
                opacity: isProcessing ? 0.6 : 1,
              }}
            >
              Login with Google
            </button>
          )}
        </div>
      </div>

      {/* File Drop Zone */}
      <div
        style={{
          border: "2px dashed #ccc",
          padding: 40,
          textAlign: "center",
          borderRadius: 8,
          background: isAuthenticated && !isProcessing ? "#fafafa" : "#f0f0f0",
          cursor: isAuthenticated && !isProcessing ? "pointer" : "not-allowed",
          opacity: isAuthenticated && !isProcessing ? 1 : 0.6,
        }}
        onClick={isAuthenticated && !isProcessing ? handleSelectFile : undefined}
      >
        <p style={{ fontSize: 18, margin: 0 }}>
          {isProcessing ? "Processing..." : "Click to select file"}
        </p>
        <p style={{ color: "#888", marginTop: 8 }}>
          Supported: MP3, WAV, M4A, PDF, TXT, DOCX
        </p>
      </div>

      {/* Status */}
      <div style={{ marginTop: 20 }}>
        <h3 style={{ marginBottom: 8 }}>Status: {status}</h3>
        <div
          style={{
            background: "#1e1e1e",
            color: "#fff",
            padding: 12,
            borderRadius: 4,
            height: 250,
            overflowY: "auto",
            fontFamily: "monospace",
            fontSize: 13,
          }}
        >
          {logs.length === 0 ? (
            <div style={{ color: "#888" }}>Waiting for action...</div>
          ) : (
            logs.map((log, i) => (
              <div
                key={i}
                style={{
                  color:
                    log.type === "error"
                      ? "#ff6b6b"
                      : log.type === "success"
                      ? "#69db7c"
                      : "#adb5bd",
                  marginBottom: 4,
                }}
              >
                {log.message}
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
}

export default App;
