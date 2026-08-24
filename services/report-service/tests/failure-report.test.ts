import test from 'node:test';
import assert from 'node:assert/strict';
import { runFailureReport, validateFailurePayload, canonicalFailureId } from '../src/failure-report.ts';

type Row = {
  fingerprint: string;
  component: string;
  normalized_error: string;
  first_seen: string;
  last_seen: string;
  first_version: string | null;
  last_version: string | null;
  occurrence_count: number;
  github_issue_number: number | null;
  github_issue_url: string | null;
  status: string;
};

class FakeStatement {
  private args: unknown[] = [];
  private db: FakeD1;
  private sql: string;
  constructor(db: FakeD1, sql: string) {
    this.db = db;
    this.sql = sql;
  }
  bind(...args: unknown[]) { this.args = args; return this; }
  async run() { return this.db.run(this.sql, this.args); }
  async first<T>() { return this.db.first(this.sql, this.args) as T | null; }
}

class FakeD1 {
  rows = new Map<string, Row>();
  prepare(sql: string) { return new FakeStatement(this, sql); }

  async run(sql: string, args: unknown[]) {
    const normalized = sql.replace(/\s+/g, ' ').trim();
    if (normalized.startsWith('INSERT OR IGNORE INTO crash_signatures')) {
      const [fingerprint, component, error, firstSeen, lastSeen, firstVersion, lastVersion, status] = args as [string, string, string, string, string, string, string, string];
      if (this.rows.has(fingerprint)) return { success: true, meta: { changes: 0 } };
      this.rows.set(fingerprint, {
        fingerprint,
        component,
        normalized_error: error,
        first_seen: firstSeen,
        last_seen: lastSeen,
        first_version: firstVersion,
        last_version: lastVersion,
        occurrence_count: 1,
        github_issue_number: null,
        github_issue_url: null,
        status,
      });
      return { success: true, meta: { changes: 1 } };
    }
    if (normalized.startsWith('UPDATE crash_signatures SET occurrence_count = occurrence_count + 1,')) {
      const [lastSeen, lastVersion, fingerprint] = args as [string, string, string];
      const row = this.rows.get(fingerprint)!;
      if (row.github_issue_number == null) return { success: true, meta: { changes: 0 } };
      row.occurrence_count += 1;
      row.last_seen = lastSeen;
      row.last_version = lastVersion;
      return { success: true, meta: { changes: 1 } };
    }
    if (normalized.startsWith("UPDATE crash_signatures SET status = 'creating_issue'")) {
      const [lastSeen, lastVersion, increment, fingerprint, staleCutoff] = args as [string, string, number, string, string];
      const row = this.rows.get(fingerprint)!;
      const allowed = row.github_issue_number == null && (
        row.status === 'pending_issue' ||
        row.status === 'issue_error' ||
        (row.status === 'creating_issue' && row.last_seen <= staleCutoff)
      );
      if (!allowed) return { success: true, meta: { changes: 0 } };
      row.status = 'creating_issue';
      row.last_seen = lastSeen;
      row.last_version = lastVersion;
      row.occurrence_count += increment;
      return { success: true, meta: { changes: 1 } };
    }
    if (normalized.startsWith("UPDATE crash_signatures SET github_issue_number = ?,")) {
      const [number, url, lastSeen, lastVersion, fingerprint] = args as [number, string, string, string, string];
      const row = this.rows.get(fingerprint)!;
      row.github_issue_number = number;
      row.github_issue_url = url;
      row.status = 'open';
      row.last_seen = lastSeen;
      row.last_version = lastVersion;
      return { success: true, meta: { changes: 1 } };
    }
    if (normalized.startsWith("UPDATE crash_signatures SET status = 'issue_error'")) {
      const [lastSeen, lastVersion, fingerprint] = args as [string, string, string];
      const row = this.rows.get(fingerprint)!;
      row.status = 'issue_error';
      row.last_seen = lastSeen;
      row.last_version = lastVersion;
      return { success: true, meta: { changes: 1 } };
    }
    if (normalized.startsWith('UPDATE crash_signatures SET occurrence_count = occurrence_count + ?,')) {
      const [increment, number, url, lastSeen, lastVersion, fingerprint] = args as [number, number, string, string, string, string];
      const row = this.rows.get(fingerprint)!;
      row.occurrence_count += increment;
      row.github_issue_number = number;
      row.github_issue_url = url;
      row.status = 'open';
      row.last_seen = lastSeen;
      row.last_version = lastVersion;
      return { success: true, meta: { changes: 1 } };
    }
    throw new Error(`unexpected SQL: ${normalized}`);
  }

  first(sql: string, args: unknown[]) {
    const normalized = sql.replace(/\s+/g, ' ').trim();
    if (normalized.startsWith('SELECT fingerprint, component, normalized_error')) {
      return this.rows.get(String(args[0])) ?? null;
    }
    throw new Error(`unexpected SELECT: ${normalized}`);
  }
}

const valid = {
  schema_version: 1,
  report_type: 'failure',
  component: 'quickshell',
  failure_stage: 'restart_after_update',
  error_code: 'quickshell_not_ready',
  awtarchy_config_version: 'v3.1.6',
  awtarchy_command_revision: '0123456789abcdef0123456789abcdef01234567',
  hyprland_version: '0.51.1',
  quickshell_version: '0.2.0',
  kernel_version: '6.17.1-arch1-1',
  gpu_family: 'AMD',
  context: { recovery_attempted: true, recovery_succeeded: false },
} as const;

function fakeEnv(db: FakeD1) {
  return {
    DB: db,
    GITHUB_APP_ID: '4695629',
    GITHUB_APP_PRIVATE_KEY: 'unused-in-test',
    GITHUB_INSTALLATION_ID: '156041074',
    GITHUB_OWNER: 'dillacorn',
    GITHUB_REPO: 'awtarchy',
  };
}

test('strict validation accepts known sanitized payload', () => {
  assert.deepEqual(validateFailurePayload(valid), valid);
});

test('strict validation rejects unknown top-level fields and unknown failure class', () => {
  assert.throws(() => validateFailurePayload({ ...valid, title: 'attacker' }), /unknown_field/);
  assert.throws(() => validateFailurePayload({ ...valid, error_code: 'anything' }), /unknown_failure/);
});

test('strict validation rejects unsafe diagnostic text', () => {
  assert.throws(() => validateFailurePayload({ ...valid, kernel_version: '/home/alice/private' }), /invalid_kernel_version/);
  assert.throws(() => validateFailurePayload({ ...valid, awtarchy_command_revision: 'short' }), /invalid_awtarchy_command_revision/);
});

test('canonical id excludes diagnostic machine/version values', () => {
  const first = validateFailurePayload(valid);
  const second = validateFailurePayload({ ...valid, kernel_version: '6.18.0-arch1-1', gpu_family: 'NVIDIA' });
  assert.equal(canonicalFailureId(first), canonicalFailureId(second));
});

test('first production report creates issue; duplicate increments same fingerprint', async () => {
  const db = new FakeD1();
  let creates = 0;
  const github = {
    async findIssueByFingerprint() { return null; },
    async createTestIssue() { throw new Error('unused'); },
    async createFailureIssue() {
      creates += 1;
      return { number: 70, url: 'https://github.com/dillacorn/awtarchy/issues/70' };
    },
  };

  const first = await runFailureReport(fakeEnv(db), valid, {
    now: () => new Date('2026-08-24T00:00:00.000Z'),
    github,
  });
  const second = await runFailureReport(fakeEnv(db), valid, {
    now: () => new Date('2026-08-24T00:01:00.000Z'),
    github,
  });

  assert.equal(first.created, true);
  assert.equal(second.created, false);
  assert.equal(second.deduplicated, true);
  assert.equal(second.issue_number, 70);
  assert.equal(creates, 1);

  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(canonicalFailureId(valid)));
  const fingerprint = Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
  assert.equal(db.rows.get(fingerprint)!.occurrence_count, 2);
  assert.equal(db.rows.get(fingerprint)!.last_version, 'v3.1.6');
});
