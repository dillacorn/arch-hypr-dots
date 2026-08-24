import {
  createGitHubClient,
  type FailureIssueData,
  type GitHubClient,
  type GitHubIssueRef,
} from './github.ts';
import type {
  D1DatabaseLike,
  D1ResultLike,
  ReportServiceEnv,
} from './test-report.ts';

const CREATION_LEASE_MS = 60_000;

const CANONICAL_FAILURES = new Map<string, string>([
  ['quickshell|start|quickshell_not_ready', 'Quickshell did not become ready'],
  ['quickshell|restart|quickshell_not_ready', 'Quickshell did not become ready after restart'],
  ['quickshell|restart_after_update|quickshell_not_ready', 'Quickshell did not become ready after update'],
  ['resume_recovery|start|quickshell_start_failed', 'Quickshell failed to start after resume'],
  ['resume_recovery|restart|quickshell_restart_failed', 'Quickshell restart failed during resume recovery'],
  ['resume_recovery|final_validation|expected_bars_missing', 'Expected Quickshell bar layers remained absent after recovery'],
]);

const TOP_LEVEL_KEYS = new Set([
  'schema_version',
  'report_type',
  'component',
  'failure_stage',
  'error_code',
  'awtarchy_config_version',
  'awtarchy_command_revision',
  'hyprland_version',
  'quickshell_version',
  'kernel_version',
  'gpu_family',
  'context',
  'diagnostic',
]);

const CONTEXT_KEYS = new Set(['recovery_attempted', 'recovery_succeeded']);
const DIAGNOSTIC_KEYS = new Set(['kind', 'managed_file', 'line', 'column']);
const DIAGNOSTIC_KINDS = new Set([
  'qml_parse_error',
  'qml_import_error',
  'qml_type_error',
  'qml_load_error',
]);
const SAFE_VERSION = /^[A-Za-z0-9._+@\/-]{1,128}$/;
const SAFE_RUNTIME_VERSION = /^[A-Za-z0-9._+-]{1,96}$/;
const SAFE_MANAGED_QML = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,95}\.qml$/;
const REVISION = /^(?:unknown|[0-9a-f]{40})$/;
const GPU_FAMILIES = new Set(['AMD', 'Intel', 'NVIDIA', 'Other', 'Unknown']);

export type FailureContext = {
  recovery_attempted?: boolean;
  recovery_succeeded?: boolean;
};

export type FailureDiagnostic = {
  kind: 'qml_parse_error' | 'qml_import_error' | 'qml_type_error' | 'qml_load_error';
  managed_file: string;
  line: number;
  column: number;
};

export type FailurePayload = {
  schema_version: 1;
  report_type: 'failure';
  component: string;
  failure_stage: string;
  error_code: string;
  awtarchy_config_version: string;
  awtarchy_command_revision: string;
  hyprland_version: string;
  quickshell_version: string;
  kernel_version: string;
  gpu_family: 'AMD' | 'Intel' | 'NVIDIA' | 'Other' | 'Unknown';
  context?: FailureContext;
  diagnostic?: FailureDiagnostic;
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

export type FailureReportResult =
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

export class FailureValidationError extends Error {
  readonly code: string;
  constructor(code: string) {
    super(code);
    this.name = 'FailureValidationError';
    this.code = code;
  }
}

function plainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function requiredString(
  input: Record<string, unknown>,
  key: string,
  pattern: RegExp,
): string {
  const value = input[key];
  if (typeof value !== 'string' || !pattern.test(value)) {
    throw new FailureValidationError(`invalid_${key}`);
  }
  return value;
}

function canonicalKey(component: string, stage: string, code: string): string {
  return `${component}|${stage}|${code}`;
}

function validateDiagnostic(value: unknown): FailureDiagnostic {
  if (!plainObject(value)) throw new FailureValidationError('invalid_diagnostic');
  for (const key of Object.keys(value)) {
    if (!DIAGNOSTIC_KEYS.has(key)) {
      throw new FailureValidationError(`unknown_diagnostic_field:${key}`);
    }
  }

  if (typeof value.kind !== 'string' || !DIAGNOSTIC_KINDS.has(value.kind)) {
    throw new FailureValidationError('invalid_diagnostic_kind');
  }
  if (typeof value.managed_file !== 'string' || !SAFE_MANAGED_QML.test(value.managed_file)) {
    throw new FailureValidationError('invalid_diagnostic_managed_file');
  }
  if (!Number.isInteger(value.line) || Number(value.line) < 1 || Number(value.line) > 1_000_000) {
    throw new FailureValidationError('invalid_diagnostic_line');
  }
  if (!Number.isInteger(value.column) || Number(value.column) < 1 || Number(value.column) > 1_000_000) {
    throw new FailureValidationError('invalid_diagnostic_column');
  }

  return {
    kind: value.kind as FailureDiagnostic['kind'],
    managed_file: value.managed_file,
    line: Number(value.line),
    column: Number(value.column),
  };
}

export function validateFailurePayload(value: unknown): FailurePayload {
  if (!plainObject(value)) throw new FailureValidationError('invalid_payload');

  for (const key of Object.keys(value)) {
    if (!TOP_LEVEL_KEYS.has(key)) throw new FailureValidationError(`unknown_field:${key}`);
  }

  if (value.schema_version !== 1) throw new FailureValidationError('unsupported_schema_version');
  if (value.report_type !== 'failure') throw new FailureValidationError('invalid_report_type');

  const component = requiredString(value, 'component', /^[a-z][a-z0-9_]{0,31}$/);
  const failureStage = requiredString(value, 'failure_stage', /^[a-z][a-z0-9_]{0,47}$/);
  const errorCode = requiredString(value, 'error_code', /^[a-z][a-z0-9_]{0,63}$/);
  if (!CANONICAL_FAILURES.has(canonicalKey(component, failureStage, errorCode))) {
    throw new FailureValidationError('unknown_failure');
  }

  const awtarchyConfigVersion = requiredString(value, 'awtarchy_config_version', SAFE_VERSION);
  const awtarchyCommandRevision = requiredString(value, 'awtarchy_command_revision', REVISION);
  const hyprlandVersion = requiredString(value, 'hyprland_version', SAFE_RUNTIME_VERSION);
  const quickshellVersion = requiredString(value, 'quickshell_version', SAFE_RUNTIME_VERSION);
  const kernelVersion = requiredString(value, 'kernel_version', SAFE_RUNTIME_VERSION);

  if (typeof value.gpu_family !== 'string' || !GPU_FAMILIES.has(value.gpu_family)) {
    throw new FailureValidationError('invalid_gpu_family');
  }

  let context: FailureContext | undefined;
  if (value.context !== undefined) {
    if (!plainObject(value.context)) throw new FailureValidationError('invalid_context');
    for (const key of Object.keys(value.context)) {
      if (!CONTEXT_KEYS.has(key)) throw new FailureValidationError(`unknown_context_field:${key}`);
      if (typeof value.context[key] !== 'boolean') {
        throw new FailureValidationError(`invalid_context_${key}`);
      }
    }
    context = { ...value.context } as FailureContext;
  }

  const diagnostic = value.diagnostic === undefined
    ? undefined
    : validateDiagnostic(value.diagnostic);

  return {
    schema_version: 1,
    report_type: 'failure',
    component,
    failure_stage: failureStage,
    error_code: errorCode,
    awtarchy_config_version: awtarchyConfigVersion,
    awtarchy_command_revision: awtarchyCommandRevision,
    hyprland_version: hyprlandVersion,
    quickshell_version: quickshellVersion,
    kernel_version: kernelVersion,
    gpu_family: value.gpu_family as FailurePayload['gpu_family'],
    ...(context ? { context } : {}),
    ...(diagnostic ? { diagnostic } : {}),
  };
}

export function canonicalFailureId(payload: FailurePayload): string {
  return [
    payload.schema_version,
    payload.report_type,
    payload.component,
    payload.failure_stage,
    payload.error_code,
  ].join('|');
}

export function canonicalFailureDescription(payload: FailurePayload): string {
  const description = CANONICAL_FAILURES.get(
    canonicalKey(payload.component, payload.failure_stage, payload.error_code),
  );
  if (!description) throw new FailureValidationError('unknown_failure');
  return description;
}

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
  version: string,
  increment: number,
): Promise<void> {
  await db.prepare(`
    UPDATE crash_signatures
       SET occurrence_count = occurrence_count + ?,
           github_issue_number = ?,
           github_issue_url = ?,
           status = 'open',
           last_seen = ?,
           last_version = ?
     WHERE fingerprint = ?
  `).bind(increment, issue.number, issue.url, nowIso, version, fingerprint).run();
}

function issueData(payload: FailurePayload, fingerprint: string): FailureIssueData {
  return {
    fingerprint,
    description: canonicalFailureDescription(payload),
    component: payload.component,
    failureStage: payload.failure_stage,
    errorCode: payload.error_code,
    awtarchyConfigVersion: payload.awtarchy_config_version,
    awtarchyCommandRevision: payload.awtarchy_command_revision,
    hyprlandVersion: payload.hyprland_version,
    quickshellVersion: payload.quickshell_version,
    kernelVersion: payload.kernel_version,
    gpuFamily: payload.gpu_family,
    context: payload.context,
    diagnostic: payload.diagnostic,
  };
}

export async function runFailureReport(
  env: ReportServiceEnv,
  rawPayload: unknown,
  overrides: Overrides = {},
): Promise<FailureReportResult> {
  const payload = validateFailurePayload(rawPayload);
  const now = overrides.now?.() ?? new Date();
  const nowIso = now.toISOString();
  const staleCutoff = new Date(now.getTime() - CREATION_LEASE_MS).toISOString();
  const fingerprint = await sha256Hex(canonicalFailureId(payload));
  const description = canonicalFailureDescription(payload);
  const version = payload.awtarchy_config_version;
  const github = overrides.github ?? createGitHubClient(env);

  const insert = await env.DB.prepare(`
    INSERT OR IGNORE INTO crash_signatures (
      fingerprint, component, normalized_error, first_seen, last_seen,
      first_version, last_version, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    fingerprint,
    payload.component,
    description,
    nowIso,
    nowIso,
    version,
    version,
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
               last_seen = ?,
               last_version = ?
         WHERE fingerprint = ?
           AND github_issue_number IS NOT NULL
      `).bind(nowIso, version, fingerprint).run();
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
             last_seen = ?,
             last_version = ?
       WHERE fingerprint = ?
         AND github_issue_number IS NULL
         AND status IN ('pending_issue', 'issue_error')
    `).bind(nowIso, version, fingerprint).run();
    return { ok: false, error: 'github_issue_lookup_failed' };
  }

  if (recovered) {
    await linkRecoveredIssue(env.DB, fingerprint, recovered, nowIso, version, inserted ? 0 : 1);
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
           last_version = ?,
           occurrence_count = occurrence_count + ?
     WHERE fingerprint = ?
       AND github_issue_number IS NULL
       AND (
         status IN ('pending_issue', 'issue_error')
         OR (status = 'creating_issue' AND last_seen <= ?)
       )
  `).bind(nowIso, version, inserted ? 0 : 1, fingerprint, staleCutoff).run();

  if (changes(claim) === 0) return { ok: true, pending: true };

  let issue: GitHubIssueRef;
  try {
    issue = await github.createFailureIssue(issueData(payload, fingerprint));
  } catch {
    await env.DB.prepare(`
      UPDATE crash_signatures
         SET status = 'issue_error',
             last_seen = ?,
             last_version = ?
       WHERE fingerprint = ?
         AND github_issue_number IS NULL
         AND status = 'creating_issue'
         AND last_seen = ?
    `).bind(nowIso, version, fingerprint, nowIso).run();
    return { ok: false, error: 'github_issue_creation_failed' };
  }

  await env.DB.prepare(`
    UPDATE crash_signatures
       SET github_issue_number = ?,
           github_issue_url = ?,
           status = 'open',
           last_seen = ?,
           last_version = ?
     WHERE fingerprint = ?
  `).bind(issue.number, issue.url, nowIso, version, fingerprint).run();

  return {
    ok: true,
    created: true,
    deduplicated: false,
    issue_number: issue.number,
    issue_url: issue.url,
  };
}
