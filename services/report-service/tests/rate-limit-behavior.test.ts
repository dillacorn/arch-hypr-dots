import test from 'node:test';
import assert from 'node:assert/strict';
import { canonicalFailureId, runFailureReport } from '../src/failure-report.ts';

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

class Statement {
  private args: unknown[] = [];
  constructor(private db: FakeD1, private sql: string) {}
  bind(...args: unknown[]) { this.args = args; return this; }
  async run() { return this.db.run(this.sql, this.args); }
  async first<T>() { return this.db.first(this.sql, this.args) as T | null; }
}

class FakeD1 {
  rows = new Map<string, Row>();
  prepare(sql: string) { return new Statement(this, sql); }

  async run(sql: string, args: unknown[]) {
    const normalized = sql.replace(/\s+/g, ' ').trim();
    if (normalized.startsWith('INSERT OR IGNORE INTO crash_signatures')) {
      const [fingerprint, component, error, firstSeen, lastSeen, firstVersion, lastVersion, status] =
        args as [string, string, string, string, string, string, string, string];
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
      row.occurrence_count += 1;
      row.last_seen = lastSeen;
      row.last_version = lastVersion;
      return { success: true, meta: { changes: 1 } };
    }
    if (normalized.startsWith("UPDATE crash_signatures SET status = 'creating_issue'")) {
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
  failure_stage: 'start',
  error_code: 'quickshell_not_ready',
  awtarchy_config_version: 'v3.1.6',
  awtarchy_command_revision: 'unknown',
  hyprland_version: '0.51.1',
  quickshell_version: '0.2.0',
  kernel_version: '6.17.1-arch1-1',
  gpu_family: 'AMD',
} as const;

function env(db: FakeD1) {
  return {
    DB: db,
    GITHUB_APP_ID: '4695629',
    GITHUB_APP_PRIVATE_KEY: 'unused',
    GITHUB_INSTALLATION_ID: '156041074',
    GITHUB_OWNER: 'dillacorn',
    GITHUB_REPO: 'awtarchy',
  };
}

async function fingerprint(): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(canonicalFailureId(valid)),
  );
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
}

test('saturated signature still resolves an already-linked issue without another D1 write', async () => {
  const db = new FakeD1();
  const id = await fingerprint();
  db.rows.set(id, {
    fingerprint: id,
    component: 'quickshell',
    normalized_error: 'Quickshell did not become ready',
    first_seen: '2026-08-24T00:00:00.000Z',
    last_seen: '2026-08-24T00:00:00.000Z',
    first_version: 'v3.1.6',
    last_version: 'v3.1.6',
    occurrence_count: 4,
    github_issue_number: 88,
    github_issue_url: 'https://github.com/dillacorn/awtarchy/issues/88',
    status: 'open',
  });
  let githubCalls = 0;
  const github = {
    async findIssueByFingerprint() { githubCalls += 1; return null; },
    async createTestIssue() { throw new Error('unused'); },
    async createFailureIssue() { githubCalls += 1; throw new Error('must not create'); },
  };

  const result = await runFailureReport(env(db), valid, {
    now: () => new Date('2026-08-24T00:01:00.000Z'),
    github,
    rateLimitAllowed: false,
  });

  assert.equal(result.ok, true);
  assert.equal('deduplicated' in result && result.deduplicated, true);
  assert.equal('issue_number' in result && result.issue_number, 88);
  assert.equal(db.rows.get(id)!.occurrence_count, 4, 'rate-limited duplicate still wrote D1');
  assert.equal(githubCalls, 0);
});

test('saturated unlinked signature stops before GitHub work', async () => {
  const db = new FakeD1();
  let githubCalls = 0;
  const github = {
    async findIssueByFingerprint() { githubCalls += 1; return null; },
    async createTestIssue() { throw new Error('unused'); },
    async createFailureIssue() { githubCalls += 1; throw new Error('must not create'); },
  };

  const result = await runFailureReport(env(db), valid, {
    now: () => new Date('2026-08-24T00:00:00.000Z'),
    github,
    rateLimitAllowed: false,
  });

  assert.deepEqual(result, { ok: false, error: 'rate_limited' });
  assert.equal(githubCalls, 0);
});
