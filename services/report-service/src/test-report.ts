import { createGitHubClient, type GitHubClient, type GitHubEnv, type GitHubIssueRef } from './github.ts';

export const TEST_CANONICAL_ID = '1|test|report-service|end_to_end|controlled_test';
const TEST_COMPONENT = 'report-service';
const TEST_ERROR = 'Controlled end-to-end test';
const CREATION_LEASE_MS = 60_000;

export type D1ResultLike = {
  success?: boolean;
  meta?: { changes?: number };
};

export type D1PreparedStatementLike = {
  bind(...values: unknown[]): D1PreparedStatementLike;
  run(): Promise<D1ResultLike>;
  first<T>(): Promise<T | null>;
};

export type D1DatabaseLike = {
  prepare(sql: string): D1PreparedStatementLike;
};

export type ReportServiceEnv = GitHubEnv & {
  DB: D1DatabaseLike;
  TEST_AUTH_TOKEN?: string;
};

type SignatureRow = {
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

export type ControlledTestResult =
  | {
      ok: true;
      created: boolean;
      deduplicated: boolean;
      issue_number: number;
      issue_url: string;
    }
  | { ok: true; pending: true }
  | { ok: false; error: 'github_issue_lookup_failed' | 'github_issue_creation_failed' };

type Overrides = {
  now?: () => Date;
  github?: GitHubClient;
};

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
}

function changes(result: D1ResultLike): number {
  return Number(result.meta?.changes ?? 0);
}

async function selectRow(db: D1DatabaseLike, fingerprint: string): Promise<SignatureRow | null> {
  return db.prepare(`
    SELECT fingerprint, component, normalized_error, first_seen, last_seen,
           first_version, last_version, occurrence_count,
           github_issue_number, github_issue_url, status
      FROM crash_signatures
     WHERE fingerprint = ?
  `).bind(fingerprint).first<SignatureRow>();
}

async function linkRecoveredIssue(
  db: D1DatabaseLike,
  fingerprint: string,
  issue: GitHubIssueRef,
  nowIso: string,
  increment: number,
): Promise<void> {
  await db.prepare(`
    UPDATE crash_signatures
       SET occurrence_count = occurrence_count + ?,
           github_issue_number = ?,
           github_issue_url = ?,
           status = 'open',
           last_seen = ?
     WHERE fingerprint = ?
  `).bind(increment, issue.number, issue.url, nowIso, fingerprint).run();
}

export async function runControlledTest(
  env: ReportServiceEnv,
  overrides: Overrides = {},
): Promise<ControlledTestResult> {
  const now = overrides.now?.() ?? new Date();
  const nowIso = now.toISOString();
  const staleCutoff = new Date(now.getTime() - CREATION_LEASE_MS).toISOString();
  const fingerprint = await sha256Hex(TEST_CANONICAL_ID);
  const github = overrides.github ?? createGitHubClient(env);

  const insert = await env.DB.prepare(`
    INSERT OR IGNORE INTO crash_signatures (
      fingerprint, component, normalized_error, first_seen, last_seen, status
    ) VALUES (?, ?, ?, ?, ?, ?)
  `).bind(
    fingerprint,
    TEST_COMPONENT,
    TEST_ERROR,
    nowIso,
    nowIso,
    'pending_issue',
  ).run();
  const inserted = changes(insert) > 0;

  const row = await selectRow(env.DB, fingerprint);
  if (!row) throw new Error('d1_signature_missing_after_insert');

  if (row.github_issue_number !== null && row.github_issue_url) {
    if (!inserted) {
      await env.DB.prepare(`
        UPDATE crash_signatures
           SET occurrence_count = occurrence_count + 1,
               last_seen = ?
         WHERE fingerprint = ?
           AND github_issue_number IS NOT NULL
      `).bind(nowIso, fingerprint).run();
    }
    return {
      ok: true,
      created: false,
      deduplicated: true,
      issue_number: row.github_issue_number,
      issue_url: row.github_issue_url,
    };
  }

  let recovered: GitHubIssueRef | null;
  try {
    recovered = await github.findIssueByFingerprint(fingerprint);
  } catch {
    await env.DB.prepare(`
      UPDATE crash_signatures
         SET status = 'issue_error',
             last_seen = ?
       WHERE fingerprint = ?
         AND github_issue_number IS NULL
         AND status IN ('pending_issue', 'issue_error')
    `).bind(nowIso, fingerprint).run();
    return { ok: false, error: 'github_issue_lookup_failed' };
  }

  if (recovered) {
    await linkRecoveredIssue(env.DB, fingerprint, recovered, nowIso, inserted ? 0 : 1);
    return {
      ok: true,
      created: false,
      deduplicated: true,
      issue_number: recovered.number,
      issue_url: recovered.url,
    };
  }

  const claim = await env.DB.prepare(`
    UPDATE crash_signatures
       SET status = 'creating_issue',
           last_seen = ?,
           occurrence_count = occurrence_count + ?
     WHERE fingerprint = ?
       AND github_issue_number IS NULL
       AND (
         status IN ('pending_issue', 'issue_error')
         OR (status = 'creating_issue' AND last_seen <= ?)
       )
  `).bind(nowIso, inserted ? 0 : 1, fingerprint, staleCutoff).run();

  if (changes(claim) === 0) {
    return { ok: true, pending: true };
  }

  let issue: GitHubIssueRef;
  try {
    issue = await github.createTestIssue(fingerprint);
  } catch {
    await env.DB.prepare(`
      UPDATE crash_signatures
         SET status = 'issue_error',
             last_seen = ?
       WHERE fingerprint = ?
         AND github_issue_number IS NULL
         AND status = 'creating_issue'
         AND last_seen = ?
    `).bind(nowIso, fingerprint, nowIso).run();
    return { ok: false, error: 'github_issue_creation_failed' };
  }

  await env.DB.prepare(`
    UPDATE crash_signatures
       SET github_issue_number = ?,
           github_issue_url = ?,
           status = 'open',
           last_seen = ?
     WHERE fingerprint = ?
  `).bind(issue.number, issue.url, nowIso, fingerprint).run();

  return {
    ok: true,
    created: true,
    deduplicated: false,
    issue_number: issue.number,
    issue_url: issue.url,
  };
}
