import test from 'node:test';
import assert from 'node:assert/strict';
import { runControlledTest, TEST_CANONICAL_ID } from '../src/test-report.ts';

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
      const [fingerprint, component, error, firstSeen, lastSeen, status] = args as string[];
      if (this.rows.has(fingerprint)) return { success: true, meta: { changes: 0 } };
      this.rows.set(fingerprint, {
        fingerprint,
        component,
        normalized_error: error,
        first_seen: firstSeen,
        last_seen: lastSeen,
        first_version: null,
        last_version: null,
        occurrence_count: 1,
        github_issue_number: null,
        github_issue_url: null,
        status,
      });
      return { success: true, meta: { changes: 1 } };
    }
    if (normalized.startsWith('UPDATE crash_signatures SET occurrence_count = occurrence_count + 1, last_seen = ? WHERE fingerprint = ? AND github_issue_number IS NOT NULL')) {
      const [lastSeen, fingerprint] = args as string[];
      const row = this.rows.get(fingerprint)!;
      if (row.github_issue_number == null) return { success: true, meta: { changes: 0 } };
      row.occurrence_count += 1;
      row.last_seen = lastSeen;
      return { success: true, meta: { changes: 1 } };
    }
    if (normalized.startsWith("UPDATE crash_signatures SET status = 'creating_issue'")) {
      const [lastSeen, increment, fingerprint, staleCutoff] = args as [string, number, string, string];
      const row = this.rows.get(fingerprint)!;
      const allowed = row.github_issue_number == null && (
        row.status === 'pending_issue' ||
        row.status === 'issue_error' ||
        (row.status === 'creating_issue' && row.last_seen <= staleCutoff)
      );
      if (!allowed) return { success: true, meta: { changes: 0 } };
      row.status = 'creating_issue';
      row.last_seen = lastSeen;
      row.occurrence_count += increment;
      return { success: true, meta: { changes: 1 } };
    }
    if (normalized.startsWith("UPDATE crash_signatures SET github_issue_number = ?, github_issue_url = ?, status = 'open'")) {
      const [number, url, lastSeen, fingerprint] = args as [number, string, string, string];
      const row = this.rows.get(fingerprint)!;
      row.github_issue_number = number;
      row.github_issue_url = url;
      row.status = 'open';
      row.last_seen = lastSeen;
      return { success: true, meta: { changes: 1 } };
    }
    if (normalized.startsWith("UPDATE crash_signatures SET status = 'issue_error'")) {
      const [lastSeen, fingerprint] = args as string[];
      const row = this.rows.get(fingerprint)!;
      row.status = 'issue_error';
      row.last_seen = lastSeen;
      return { success: true, meta: { changes: 1 } };
    }
    if (normalized.startsWith('UPDATE crash_signatures SET occurrence_count = occurrence_count + ?, github_issue_number = ?')) {
      const [increment, number, url, lastSeen, fingerprint] = args as [number, number, string, string, string];
      const row = this.rows.get(fingerprint)!;
      row.occurrence_count += increment;
      row.github_issue_number = number;
      row.github_issue_url = url;
      row.status = 'open';
      row.last_seen = lastSeen;
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

function fakeEnv(db: FakeD1) {
  return {
    DB: db,
    GITHUB_APP_ID: '4695629',
    GITHUB_APP_PRIVATE_KEY: 'unused-in-test',
    GITHUB_INSTALLATION_ID: '156041074',
    GITHUB_OWNER: 'dillacorn',
    GITHUB_REPO: 'awtarchy',
    TEST_AUTH_TOKEN: 'unused-in-test',
  };
}

async function expectedFingerprint(): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(TEST_CANONICAL_ID));
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
}

test('first controlled test creates one issue and stores it', async () => {
  const db = new FakeD1();
  let creates = 0;
  const result = await runControlledTest(fakeEnv(db), {
    now: () => new Date('2026-08-23T23:30:00.000Z'),
    github: {
      async findIssueByFingerprint() { return null; },
      async createTestIssue() {
        creates += 1;
        return { number: 21, url: 'https://github.com/dillacorn/awtarchy/issues/21' };
      },
    },
  });

  assert.equal(creates, 1);
  assert.deepEqual(result, {
    ok: true,
    created: true,
    deduplicated: false,
    issue_number: 21,
    issue_url: 'https://github.com/dillacorn/awtarchy/issues/21',
  });
  const row = db.rows.get(await expectedFingerprint())!;
  assert.equal(row.github_issue_number, 21);
  assert.equal(row.status, 'open');
  assert.equal(row.occurrence_count, 1);
});

test('second controlled test deduplicates and increments without creating', async () => {
  const db = new FakeD1();
  let creates = 0;
  const github = {
    async findIssueByFingerprint() { return null; },
    async createTestIssue() {
      creates += 1;
      return { number: 22, url: 'https://github.com/dillacorn/awtarchy/issues/22' };
    },
  };

  await runControlledTest(fakeEnv(db), { now: () => new Date('2026-08-23T23:30:00.000Z'), github });
  const second = await runControlledTest(fakeEnv(db), { now: () => new Date('2026-08-23T23:31:00.000Z'), github });

  assert.equal(creates, 1);
  assert.equal(second.created, false);
  assert.equal(second.deduplicated, true);
  const row = db.rows.get(await expectedFingerprint())!;
  assert.equal(row.occurrence_count, 2);
  assert.equal(row.github_issue_number, 22);
});

test('missing D1 link recovers an already-created GitHub issue by marker', async () => {
  const db = new FakeD1();
  const fingerprint = await expectedFingerprint();
  db.rows.set(fingerprint, {
    fingerprint,
    component: 'report-service',
    normalized_error: 'Controlled end-to-end test',
    first_seen: '2026-08-23T23:00:00.000Z',
    last_seen: '2026-08-23T23:00:00.000Z',
    first_version: null,
    last_version: null,
    occurrence_count: 1,
    github_issue_number: null,
    github_issue_url: null,
    status: 'creating_issue',
  });
  let creates = 0;

  const result = await runControlledTest(fakeEnv(db), {
    now: () => new Date('2026-08-23T23:31:00.000Z'),
    github: {
      async findIssueByFingerprint() {
        return { number: 30, url: 'https://github.com/dillacorn/awtarchy/issues/30' };
      },
      async createTestIssue() { creates += 1; throw new Error('must not create'); },
    },
  });

  assert.equal(creates, 0);
  assert.equal(result.issue_number, 30);
  assert.equal(result.deduplicated, true);
  assert.equal(db.rows.get(fingerprint)!.github_issue_number, 30);
  assert.equal(db.rows.get(fingerprint)!.occurrence_count, 2);
});

test('active creating_issue lease does not create concurrently', async () => {
  const db = new FakeD1();
  const fingerprint = await expectedFingerprint();
  db.rows.set(fingerprint, {
    fingerprint,
    component: 'report-service',
    normalized_error: 'Controlled end-to-end test',
    first_seen: '2026-08-23T23:30:00.000Z',
    last_seen: '2026-08-23T23:30:30.000Z',
    first_version: null,
    last_version: null,
    occurrence_count: 1,
    github_issue_number: null,
    github_issue_url: null,
    status: 'creating_issue',
  });
  let creates = 0;

  const result = await runControlledTest(fakeEnv(db), {
    now: () => new Date('2026-08-23T23:31:00.000Z'),
    github: {
      async findIssueByFingerprint() { return null; },
      async createTestIssue() { creates += 1; throw new Error('must not create'); },
    },
  });

  assert.equal(creates, 0);
  assert.deepEqual(result, { ok: true, pending: true });
});

test('stale creating_issue lease may be reclaimed after marker check', async () => {
  const db = new FakeD1();
  const fingerprint = await expectedFingerprint();
  db.rows.set(fingerprint, {
    fingerprint,
    component: 'report-service',
    normalized_error: 'Controlled end-to-end test',
    first_seen: '2026-08-23T23:00:00.000Z',
    last_seen: '2026-08-23T23:00:00.000Z',
    first_version: null,
    last_version: null,
    occurrence_count: 1,
    github_issue_number: null,
    github_issue_url: null,
    status: 'creating_issue',
  });
  let creates = 0;

  const result = await runControlledTest(fakeEnv(db), {
    now: () => new Date('2026-08-23T23:31:00.000Z'),
    github: {
      async findIssueByFingerprint() { return null; },
      async createTestIssue() {
        creates += 1;
        return { number: 31, url: 'https://github.com/dillacorn/awtarchy/issues/31' };
      },
    },
  });

  assert.equal(creates, 1);
  assert.equal(result.issue_number, 31);
});

test('GitHub creation failure becomes non-secret issue_error', async () => {
  const db = new FakeD1();
  const result = await runControlledTest(fakeEnv(db), {
    now: () => new Date('2026-08-23T23:31:00.000Z'),
    github: {
      async findIssueByFingerprint() { return null; },
      async createTestIssue() { throw new Error('installation-token-super-secret'); },
    },
  });

  assert.deepEqual(result, { ok: false, error: 'github_issue_creation_failed' });
  const row = db.rows.get(await expectedFingerprint())!;
  assert.equal(row.status, 'issue_error');
  assert.equal(JSON.stringify(result).includes('installation-token-super-secret'), false);
});
