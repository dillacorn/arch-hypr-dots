import test from 'node:test';
import assert from 'node:assert/strict';
import { handleRequest } from '../src/index.ts';

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
};

const env = {} as any;

function reportRequest(): Request {
  return new Request('https://example.test/v1/report', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify(valid),
  });
}

test('POST /v1/report requires application/json', async () => {
  let called = 0;
  const response = await handleRequest(
    new Request('https://example.test/v1/report', { method: 'POST', body: '{}' }),
    env,
    undefined,
    async () => {
      called += 1;
      return { ok: true, created: true, deduplicated: false, issue_number: 1, issue_url: 'x' };
    },
  );
  assert.equal(response.status, 415);
  assert.equal(called, 0);
});

test('POST /v1/report rejects malformed and unknown fields', async () => {
  for (const body of ['{', JSON.stringify({ ...valid, fingerprint: 'a'.repeat(64) })]) {
    let called = 0;
    const response = await handleRequest(
      new Request('https://example.test/v1/report', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body,
      }),
      env,
      undefined,
      async () => {
        called += 1;
        return { ok: true, created: true, deduplicated: false, issue_number: 1, issue_url: 'x' };
      },
    );
    assert.equal(response.status, 400);
    assert.equal(called, 0);
  }
});

test('POST /v1/report rejects bodies over 32 KiB', async () => {
  const response = await handleRequest(
    new Request('https://example.test/v1/report', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: ' '.repeat(32769),
    }),
    env,
    undefined,
    async () => ({ ok: true, created: true, deduplicated: false, issue_number: 1, issue_url: 'x' }),
  );
  assert.equal(response.status, 413);
});

test('POST /v1/report fails closed when rate limiting is unavailable', async () => {
  let called = 0;
  const response = await handleRequest(
    reportRequest(),
    env,
    undefined,
    async () => {
      called += 1;
      return { ok: true, created: true, deduplicated: false, issue_number: 1, issue_url: 'x' };
    },
  );

  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { ok: false, error: 'service_unavailable' });
  assert.equal(called, 0);
});

test('POST /v1/report rate limits by canonical failure signature before D1 workflow', async () => {
  let called = 0;
  let key = '';
  const limitedEnv = {
    REPORT_RATE_LIMITER: {
      async limit(input: { key: string }) {
        key = input.key;
        return { success: false };
      },
    },
  } as any;

  const response = await handleRequest(
    reportRequest(),
    limitedEnv,
    undefined,
    async () => {
      called += 1;
      return { ok: true, created: true, deduplicated: false, issue_number: 1, issue_url: 'x' };
    },
  );

  assert.equal(response.status, 429);
  assert.deepEqual(await response.json(), { ok: false, error: 'rate_limited' });
  assert.equal(key, '1|failure|quickshell|start|quickshell_not_ready');
  assert.equal(called, 0);
});

test('POST /v1/report invokes production workflow with validated payload', async () => {
  let received: any = null;
  let limiterCalls = 0;
  const allowedEnv = {
    REPORT_RATE_LIMITER: {
      async limit() {
        limiterCalls += 1;
        return { success: true };
      },
    },
  } as any;

  const response = await handleRequest(
    reportRequest(),
    allowedEnv,
    undefined,
    async (_env, payload) => {
      received = payload;
      return {
        ok: true,
        created: true,
        deduplicated: false,
        issue_number: 71,
        issue_url: 'https://github.com/dillacorn/awtarchy/issues/71',
      };
    },
  );

  assert.equal(response.status, 201);
  assert.equal(limiterCalls, 1);
  assert.equal(received.component, 'quickshell');
  assert.equal(received.failure_stage, 'start');
});
