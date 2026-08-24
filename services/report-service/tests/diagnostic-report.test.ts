import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { canonicalFailureId, validateFailurePayload } from '../src/failure-report.ts';
import { createGitHubClient } from '../src/github.ts';

const base = {
  schema_version: 1,
  report_type: 'failure',
  component: 'quickshell',
  failure_stage: 'restart_after_update',
  error_code: 'quickshell_not_ready',
  awtarchy_config_version: 'night-light-schedule-report-testing@0123456789abcdef0123456789abcdef01234567',
  awtarchy_command_revision: '0123456789abcdef0123456789abcdef01234567',
  hyprland_version: '0.56.1',
  quickshell_version: '0.3.0',
  kernel_version: '7.1.5-arch1-2',
  gpu_family: 'AMD',
} as const;

const diagnostic = {
  kind: 'qml_parse_error',
  managed_file: 'Theme.qml',
  line: 65,
  column: 1,
} as const;

test('accepts a tightly structured managed-QML diagnostic', () => {
  const payload = validateFailurePayload({ ...base, diagnostic });
  assert.deepEqual(payload.diagnostic, diagnostic);
});

test('rejects arbitrary diagnostic text, paths, filenames, kinds, and invalid locations', () => {
  assert.throws(
    () => validateFailurePayload({ ...base, diagnostic: { ...diagnostic, message: 'secret raw log text' } }),
    /unknown_diagnostic_field/,
  );
  assert.throws(
    () => validateFailurePayload({ ...base, diagnostic: { ...diagnostic, managed_file: '/home/alice/Theme.qml' } }),
    /invalid_diagnostic_managed_file/,
  );
  assert.throws(
    () => validateFailurePayload({ ...base, diagnostic: { ...diagnostic, managed_file: 'JohnDoe.qml' } }),
    /invalid_diagnostic_managed_file/,
  );
  assert.throws(
    () => validateFailurePayload({ ...base, diagnostic: { ...diagnostic, kind: 'anything_the_client_wants' } }),
    /invalid_diagnostic_kind/,
  );
  assert.throws(
    () => validateFailurePayload({ ...base, diagnostic: { ...diagnostic, line: 0 } }),
    /invalid_diagnostic_line/,
  );
});

test('safe diagnostic class refines the bug signature without using location', () => {
  const withoutDiagnostic = validateFailurePayload(base);
  const withDiagnostic = validateFailurePayload({ ...base, diagnostic });
  const movedDiagnostic = validateFailurePayload({
    ...base,
    diagnostic: { ...diagnostic, line: 999, column: 17 },
  });
  const importDiagnostic = validateFailurePayload({
    ...base,
    diagnostic: { ...diagnostic, kind: 'qml_import_error' },
  });
  const otherManagedFile = validateFailurePayload({
    ...base,
    diagnostic: { ...diagnostic, managed_file: 'QuickSettings.qml' },
  });

  assert.notEqual(canonicalFailureId(withDiagnostic), canonicalFailureId(withoutDiagnostic));
  assert.equal(canonicalFailureId(withDiagnostic), canonicalFailureId(movedDiagnostic));
  assert.notEqual(canonicalFailureId(withDiagnostic), canonicalFailureId(importDiagnostic));
  assert.notEqual(canonicalFailureId(withDiagnostic), canonicalFailureId(otherManagedFile));

  assert.equal(canonicalFailureId(withDiagnostic).includes('65'), false);
  assert.equal(canonicalFailureId(withDiagnostic).includes('17'), false);
  assert.equal(canonicalFailureId(withDiagnostic).includes(base.awtarchy_config_version), false);
  assert.equal(canonicalFailureId(withDiagnostic).includes(base.awtarchy_command_revision), false);
});

test('GitHub issue renders only the structured diagnostic fields', async () => {
  const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const pem = privateKey.export({ format: 'pem', type: 'pkcs1' }).toString();
  let posted: any = null;

  const fakeFetch: typeof fetch = async (input, init) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    if (url.endsWith('/app/installations/156041074/access_tokens')) {
      return Response.json({ token: 'installation-token' }, { status: 201 });
    }
    if (url.endsWith('/repos/dillacorn/awtarchy/issues')) {
      posted = JSON.parse(String(init?.body));
      return Response.json({
        number: 89,
        html_url: 'https://github.com/dillacorn/awtarchy/issues/89',
      }, { status: 201 });
    }
    throw new Error(`unexpected URL ${url}`);
  };

  const client = createGitHubClient({
    GITHUB_APP_ID: '4695629',
    GITHUB_APP_PRIVATE_KEY: pem,
    GITHUB_INSTALLATION_ID: '156041074',
    GITHUB_OWNER: 'dillacorn',
    GITHUB_REPO: 'awtarchy',
  }, fakeFetch);

  await client.createFailureIssue({
    fingerprint: 'd'.repeat(64),
    description: 'Quickshell did not become ready after update',
    component: 'quickshell',
    failureStage: 'restart_after_update',
    errorCode: 'quickshell_not_ready',
    awtarchyConfigVersion: base.awtarchy_config_version,
    awtarchyCommandRevision: base.awtarchy_command_revision,
    hyprlandVersion: base.hyprland_version,
    quickshellVersion: base.quickshell_version,
    kernelVersion: base.kernel_version,
    gpuFamily: base.gpu_family,
    diagnostic,
  });

  assert.match(posted.body, /Diagnostic: `qml_parse_error`/);
  assert.match(posted.body, /Managed file: `Theme\.qml`/);
  assert.match(posted.body, /Location: `65:1`/);
  assert.equal(posted.body.includes('/home/'), false);
  assert.equal(posted.body.includes('secret raw log text'), false);
});
