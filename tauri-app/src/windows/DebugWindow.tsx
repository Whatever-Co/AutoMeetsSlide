import { useState, useEffect, useRef } from 'react';
import { listen } from '@tauri-apps/api/event';
import type { LogEntry } from '../store/types';
import '../styles/index.css';

export function DebugWindow() {
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [filter, setFilter] = useState<string>('all');
  const logsEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const unlisten = listen<LogEntry>('log-entry', (event) => {
      setLogs((prev) => [
        ...prev,
        {
          ...event.payload,
          id: crypto.randomUUID(),
        },
      ]);
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);

  // Auto-scroll to bottom
  useEffect(() => {
    logsEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [logs]);

  const handleClear = () => {
    setLogs([]);
  };

  const filteredLogs =
    filter === 'all' ? logs : logs.filter((log) => log.type === filter);

  const formatTime = (timestamp: string) => {
    const date = new Date(timestamp);
    const time = date.toLocaleTimeString('en-US', {
      hour12: false,
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
    const ms = date.getMilliseconds().toString().padStart(3, '0');
    return `${time}.${ms}`;
  };

  return (
    <div className="debug-window">
      <div className="debug-header">
        <span className="debug-title">Debug Console</span>
        <div className="debug-actions">
          <select
            className="debug-button"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
          >
            <option value="all">All</option>
            <option value="info">Info</option>
            <option value="success">Success</option>
            <option value="warning">Warning</option>
            <option value="error">Error</option>
          </select>
          <button className="debug-button" onClick={handleClear}>
            Clear
          </button>
        </div>
      </div>
      <div className="debug-logs">
        {filteredLogs.length === 0 ? (
          <div style={{ color: '#6a6a6a' }}>Waiting for logs...</div>
        ) : (
          filteredLogs.map((log) => (
            <div key={log.id} className={`debug-entry ${log.type}`}>
              <span className="debug-timestamp">{formatTime(log.timestamp)}</span>
              {log.message}
            </div>
          ))
        )}
        <div ref={logsEndRef} />
      </div>
    </div>
  );
}
