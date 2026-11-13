/**
 * MKES CARE+ WhatsApp Daemon — Single Instance & Session Lock Manager
 * 
 * Enforces strictly single-instance execution for WhatsApp Web Client.
 * Multiple simultaneous processes attempting to access the same Chromium
 * user profile directory (LocalAuth) cause LevelDB locks, IndexedDB corruption,
 * and immediate process termination.
 * 
 * Invariants:
 * 1. Exactly one active WhatsApp client instance may access the session directory.
 * 2. Stale locks from system crashes, power cuts, or terminated PIDs are automatically detected and cleared.
 * 3. Windows broken symlinks (SingletonLock, SingletonCookie, SingletonSocket) are cleaned via lstat/force-remove.
 * 4. Lock file is safely excluded from Git and automatically released upon clean process shutdown.
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const logger = require('./logger');

class InstanceLockManager {
  constructor() {
    this.currentLockFile = null;
    this.acquired = false;
    this._registeredShutdown = false;
  }

  /**
   * Checks if a process with the given PID is actively running.
   */
  isPidRunning(pid) {
    if (!pid || typeof pid !== 'number' || isNaN(pid) || pid <= 0) {
      return false;
    }
    try {
      process.kill(pid, 0);
      return true;
    } catch (e) {
      // EPERM means process exists but we do not have permission to signal it
      return e.code === 'EPERM';
    }
  }

  /**
   * Cleans up stale Chromium singleton lock files and dead ports from the session directory.
   * Handles Windows symbolic links/reparse points correctly (where fs.existsSync returns false).
   */
  cleanupChromiumLocks(sessionPath) {
    if (!sessionPath) return;

    try {
      const sessionSubdir = path.join(sessionPath, 'session');
      if (!fs.existsSync(sessionSubdir)) return;

      const lockFiles = [
        'SingletonLock',
        'SingletonCookie',
        'SingletonSocket',
        'DevToolsActivePort',
      ];

      for (const fileName of lockFiles) {
        const filePath = path.join(sessionSubdir, fileName);
        try {
          // Check if file or symlink exists via lstat (handles dead Windows symlinks)
          const stat = fs.lstatSync(filePath);
          if (stat) {
            fs.rmSync(filePath, { force: true });
            logger.info(`Removed stale Chromium lock artifact: ${fileName}`);
          }
        } catch (err) {
          if (err.code !== 'ENOENT') {
            try {
              fs.unlinkSync(filePath);
            } catch (_) {}
          }
        }
      }
    } catch (err) {
      logger.debug(`Chromium lock cleanup note: ${err.message}`);
    }
  }

  /**
   * Attempts to acquire exclusive single-instance lock for the given session directory.
   * Returns { success: boolean, existingPid?: number, error?: string }
   */
  acquireLock(sessionPath, serviceName = 'WhatsAppBridge') {
    if (this.acquired && this.currentLockFile) {
      return { success: true };
    }

    try {
      if (!fs.existsSync(sessionPath)) {
        fs.mkdirSync(sessionPath, { recursive: true });
      }

      const lockFilePath = path.join(sessionPath, 'whatsapp_instance.lock');

      // Check existing lock file
      if (fs.existsSync(lockFilePath)) {
        try {
          const raw = fs.readFileSync(lockFilePath, 'utf8');
          const data = JSON.parse(raw);
          const existingPid = parseInt(data.pid, 10);

          if (existingPid === process.pid) {
            this.currentLockFile = lockFilePath;
            this.acquired = true;
            return { success: true };
          }

          if (this.isPidRunning(existingPid)) {
            const msg = `Contention: Another WhatsApp instance is already running (PID: ${existingPid}, host: ${data.host || 'unknown'}, started: ${data.acquiredAt || 'unknown'}). Only one instance may access the session directory.`;
            logger.error(`[LOCK CONFLICT] ${msg}`);
            return {
              success: false,
              existingPid,
              error: msg,
            };
          } else {
            logger.warn(`Detected stale lock file from terminated PID ${existingPid}. Safely clearing stale lock.`);
            try {
              fs.unlinkSync(lockFilePath);
            } catch (_) {}
          }
        } catch (parseErr) {
          logger.warn(`Corrupt lock file detected. Resetting lock file.`);
          try {
            fs.unlinkSync(lockFilePath);
          } catch (_) {}
        }
      }

      // Write current lock
      const lockPayload = {
        pid: process.pid,
        serviceName,
        host: os.hostname(),
        sessionPath,
        acquiredAt: new Date().toISOString(),
      };

      fs.writeFileSync(lockFilePath, JSON.stringify(lockPayload, null, 2), 'utf8');
      this.currentLockFile = lockFilePath;
      this.acquired = true;

      // Clean stale Chromium profile locks
      this.cleanupChromiumLocks(sessionPath);

      // Register exit hook once
      if (!this._registeredShutdown) {
        this._registeredShutdown = true;
        const release = () => this.releaseLock();
        process.on('exit', release);
        process.on('SIGINT', release);
        process.on('SIGTERM', release);
      }

      logger.info(`Acquired exclusive WhatsApp instance lock (PID: ${process.pid}) at ${lockFilePath}`);
      return { success: true };
    } catch (err) {
      logger.error(`Failed to acquire instance lock: ${err.message}`);
      return { success: false, error: err.message };
    }
  }

  /**
   * Releases current instance lock if held by this process.
   */
  releaseLock() {
    if (!this.acquired || !this.currentLockFile) return;

    try {
      if (fs.existsSync(this.currentLockFile)) {
        try {
          const raw = fs.readFileSync(this.currentLockFile, 'utf8');
          const data = JSON.parse(raw);
          if (parseInt(data.pid, 10) === process.pid) {
            fs.unlinkSync(this.currentLockFile);
            logger.info(`Released WhatsApp instance lock for PID: ${process.pid}`);
          }
        } catch (_) {
          fs.unlinkSync(this.currentLockFile);
        }
      }
    } catch (err) {
      logger.debug(`Instance lock release note: ${err.message}`);
    } finally {
      this.acquired = false;
      this.currentLockFile = null;
    }
  }
}

module.exports = new InstanceLockManager();
