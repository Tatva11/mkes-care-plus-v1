/**
 * MKES CARE+ WhatsApp Daemon — Session Persistence & Instance Locking Test Suite
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const instanceLock = require('../src/utils/instance_lock');

let totalTests = 0;
let passedTests = 0;

function assert(description, condition) {
  totalTests++;
  if (condition) {
    passedTests++;
    console.log(`  ✓ [PASS] ${description}`);
  } else {
    console.error(`  ✗ [FAIL] ${description}`);
  }
}

async function runTests() {
  console.log('====================================================');
  console.log('  MKES CARE+ WhatsApp Session Persistence Test Suite');
  console.log('====================================================\n');

  const testDir = path.join(os.tmpdir(), `mkes_test_wa_session_${Date.now()}`);
  fs.mkdirSync(testDir, { recursive: true });

  try {
    // Suite 1: PID Liveness Detection
    console.log('--- Suite 1: Process Liveness Checking ---');
    assert('Identifies current process PID as running', instanceLock.isPidRunning(process.pid) === true);
    assert('Rejects invalid or non-numeric PID', instanceLock.isPidRunning(null) === false && instanceLock.isPidRunning(-5) === false);
    assert('Correctly identifies non-existent PID as not running', instanceLock.isPidRunning(99999999) === false);

    // Suite 2: Single-Instance Lock Acquisition & Idempotency
    console.log('\n--- Suite 2: Lock Acquisition & Idempotency ---');
    const firstAcquire = instanceLock.acquireLock(testDir, 'TestDaemon');
    assert('Acquires instance lock successfully in clean directory', firstAcquire.success === true);

    const lockFilePath = path.join(testDir, 'whatsapp_instance.lock');
    assert('Creates whatsapp_instance.lock file on disk', fs.existsSync(lockFilePath));

    const lockData = JSON.parse(fs.readFileSync(lockFilePath, 'utf8'));
    assert('Lock payload contains current process.pid', lockData.pid === process.pid);
    assert('Lock payload records host and timestamp', typeof lockData.host === 'string' && typeof lockData.acquiredAt === 'string');

    const secondAcquire = instanceLock.acquireLock(testDir, 'TestDaemon');
    assert('Subsequent acquire from same process is idempotent (success: true)', secondAcquire.success === true);

    // Suite 3: Lock Contention Protection
    console.log('\n--- Suite 3: Lock Contention Protection ---');
    // Simulate lock owned by another running process (e.g. parent or current process pretending to be different running process)
    // We write a lock file with process.pid but create a second instance lock manager to test contention
    const InstanceLockManagerClass = instanceLock.constructor;
    const secondManager = new InstanceLockManagerClass();
    
    // Writing another active PID: since process.pid is alive, secondManager seeing another PID
    const contentionDir = path.join(os.tmpdir(), `mkes_contention_test_${Date.now()}`);
    fs.mkdirSync(contentionDir, { recursive: true });
    const contentionLockFile = path.join(contentionDir, 'whatsapp_instance.lock');
    fs.writeFileSync(contentionLockFile, JSON.stringify({
      pid: process.pid,
      serviceName: 'ExistingRunningService',
      host: os.hostname(),
      acquiredAt: new Date().toISOString(),
    }));

    // Another manager with different PID simulator
    // If it checks contention against process.pid (which is alive), it must reject
    // To simulate different PID from perspective of manager, stub process.pid check
    const originalPidRunning = secondManager.isPidRunning.bind(secondManager);
    secondManager.isPidRunning = (pid) => pid === 88888; // Pretend 88888 is alive
    fs.writeFileSync(contentionLockFile, JSON.stringify({
      pid: 88888,
      serviceName: 'ActiveProcess88888',
      host: os.hostname(),
      acquiredAt: new Date().toISOString(),
    }));

    const contentionResult = secondManager.acquireLock(contentionDir, 'NewProcess');
    assert('Refuses acquisition when another live process holds lock', contentionResult.success === false);
    assert('Reports existingPid in contention result', contentionResult.existingPid === 88888);

    // Suite 4: Stale Crash Lock Recovery
    console.log('\n--- Suite 4: Stale Crash Lock Recovery ---');
    // If PID is dead (not running), it should detect stale lock, remove it, and acquire
    secondManager.isPidRunning = () => false; // PID is dead
    const recoveryResult = secondManager.acquireLock(contentionDir, 'RecoveringProcess');
    assert('Recovers from stale lock when previous PID is terminated', recoveryResult.success === true);
    secondManager.releaseLock();
    try { fs.rmSync(contentionDir, { recursive: true, force: true }); } catch (_) {}

    // Suite 5: Chromium Singleton Lock Cleanup
    console.log('\n--- Suite 5: Chromium Lock Cleanup ---');
    const sessionSubdir = path.join(testDir, 'session');
    fs.mkdirSync(sessionSubdir, { recursive: true });

    const lockFiles = ['SingletonLock', 'SingletonCookie', 'SingletonSocket', 'DevToolsActivePort'];
    for (const f of lockFiles) {
      fs.writeFileSync(path.join(sessionSubdir, f), 'stale_data');
    }

    assert('Test files created in session directory', fs.existsSync(path.join(sessionSubdir, 'SingletonLock')));
    instanceLock.cleanupChromiumLocks(testDir);

    let anyRemaining = false;
    for (const f of lockFiles) {
      if (fs.existsSync(path.join(sessionSubdir, f))) anyRemaining = true;
    }
    assert('cleanupChromiumLocks removes all stale Chromium locks', anyRemaining === false);

    // Suite 6: Clean Release
    console.log('\n--- Suite 6: Lock Release ---');
    instanceLock.releaseLock();
    assert('releaseLock removes whatsapp_instance.lock from disk', !fs.existsSync(lockFilePath));

    // Suite 7: WhatsApp Client Session Reuse Invariants
    console.log('\n--- Suite 7: Client Session Reuse Invariants ---');
    const whatsappClient = require('../src/services/whatsapp_client');
    assert('Client sessionPath defaults to clinic storage (C:\\MKES_CARE_PLUS\\wa_session)', 
      whatsappClient.sessionPath.includes('wa_session'));

    // Check that client provides clean destroy() method
    assert('whatsappClient exposes destroy() method for clean shutdown', typeof whatsappClient.destroy === 'function');

    // Check that auto-reconnect backoff respects bounds
    assert('Max reconnect attempts is capped at 5', whatsappClient.maxReconnectAttempts === 5);

    // Suite 8: Host Session Persistence Status Verification
    console.log('\n--- Suite 8: Host Clinic Session Directory Verification ---');
    const clinicSessionDir = 'C:\\MKES_CARE_PLUS\\wa_session';
    const hasClinicSession = fs.existsSync(path.join(clinicSessionDir, 'session', 'Default'));
    assert('Host clinic session directory exists with Chromium Default profile', hasClinicSession);

    // Suite 9: DRY_RUN Safety Invariant
    console.log('\n--- Suite 9: DRY_RUN Safety Verification ---');
    const isDryRun = String(process.env.DRY_RUN || 'true').trim().toLowerCase() !== 'false';
    assert('DRY_RUN is strictly true (real WhatsApp dispatch blocked)', isDryRun === true);

  } finally {
    try {
      instanceLock.releaseLock();
      fs.rmSync(testDir, { recursive: true, force: true });
    } catch (_) {}
  }

  console.log('\n====================================================');
  console.log(`Session Persistence Suite Completed: ${passedTests} / ${totalTests} tests passed.`);
  console.log('====================================================\n');

  if (passedTests !== totalTests) {
    process.exit(1);
  }
}

runTests();
