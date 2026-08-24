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
const CLIENT_IP = '203.0.113.7';
const SIGNATURE = '1|failure|quickshell|start|quickshell_not_ready';

function reportRequest(includeClientIp = true): Request {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json; charset=utf-8',
  };
  if (includeClientIp) headers['CF-Connecting-IP'] = CLIENT_IP;
  return new Request('https://example.test/v1/report', {
    method: 'POST',
    headers,
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

test('POST /v1/report stops reading an oversized streamed body at 32 KiB', async () => {
  let pulls = 0;
  const stream = new ReadableStream<Uint8Array>({
    pull(controller) {
      pulls += 1;
      if (pulls === 1) {
        controller.enqueue(new Uint8Array(32769));
        return;
      }
      throw new Error('oversized request body was read past the limit');
    },
  });
  const init = {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: stream,
    duplex: 'half',
  } as RequestInit & { duplex: 'half' };

  const response = await handleRequest(
    new Request('https://example.test/v1/report', init),
    env,
    undefined,
    async () => ({ ok: true, created: true, deduplicated: false, issue_number: 1, issue_url: 'x' }),
  );

  assert.equal(response.status, 413);
  assert.equal(pulls, 1);
});

test('POST /v1/report fails closed when client rate limiting is unavailable', async () => {
  let called = 0;
  const response = await handleRequest(
    reportRequest(),
    {
      REPORT_SIGNATURE_RATE_LIMITER: { async limit() { return { success: true }; } },
    } as any,
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

test('POST /v1/report fails closed when signature rate limiting is unavailable', async () => {
  let called = 0;
  const response = await handleRequest(
    reportRequest(),
    {
      REPORT_CLIENT_RATE_LIMITER: { async limit() { return { success: true }; } },
    } as any,
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

test('POST /v1/report fails closed when Cloudflare client IP is unavailable', async () => {
  let clientCalls = 0;
  let signatureCalls = 0;
  const response = await handleRequest(
    reportRequest(false),
    {
      REPORT_CLIENT_RATE_LIMITER: {
        async limit() { clientCalls += 1; return { success: true }; },
      },
      REPORT_SIGNATURE_RATE_LIMITER: {
        async limit() { signatureCalls += 1; return { success: true }; },
      },
    } as any,
  );

  assert.equal(response.status, 503);
  assert.equal(clientCalls, 0);
  assert.equal(signatureCalls, 0);
});

test('POST /v1/report client limiter blocks before global signature limiter and D1 workflow', async () => {
  let clientKey = '';
  let signatureCalls = 0;
  let called = 0;
  const response = await handleRequest(
    reportRequest(),
    {
      REPORT_CLIENT_RATE_LIMITER: {
        async limit(input: { key: string }) {
          clientKey = input.key;
          return { success: false };
        },
      },
      REPORT_SIGNATURE_RATE_LIMITER: {
        async limit() { signatureCalls += 1; return { success: true }; },
      },
    } as any,
    undefined,
    async () => {
      called += 1;
      return { ok: true, created: true, deduplicated: false, issue_number: 1, issue_url: 'x' };
    },
  );

  assert.equal(response.status, 429);
  assert.deepEqual(await response.json(), { ok: false, error: 'rate_limited' });
  assert.equal(clientKey, `${CLIENT_IP}|${SIGNATURE}`);
  assert.equal(signatureCalls, 0);
  assert.equal(called, 0);
});

test('POST /v1/report global signature limiter blocks before D1 workflow', async () => {
  let clientCalls = 0;
  let signatureKey = '';
  let called = 0;
  const response = await handleRequest(
    reportRequest(),
    {
      REPORT_CLIENT_RATE_LIMITER: {
        async limit() { clientCalls += 1; return { success: true }; },
      },
      REPORT_SIGNATURE_RATE_LIMITER: {
        async limit(input: { key: string }) {
          signatureKey = input.key;
          return { success: false };
        },
      },
    } as any,
    undefined,
    async () => {
      called += 1;
      return { ok: true, created: true, deduplicated: false, issue_number: 1, issue_url: 'x' };
    },
  );

  assert.equal(response.status, 429);
  assert.deepEqual(await response.json(), { ok: false, error: 'rate_limited' });
  assert.equal(clientCalls, 1);
  assert.equal(signatureKey, SIGNATURE);
  assert.equal(called, 0);
});

test('POST /v1/report invokes production workflow only after both limiters allow it', async () => {
  let received: any = null;
  let clientKey = '';
  let signatureKey = '';
  const allowedEnv = {
    REPORT_CLIENT_RATE_LIMITER: {
      async limit(input: { key: string }) {
        clientKey = input.key;
        return { success: true };
      },
    },
    REPORT_SIGNATURE_RATE_LIMITER: {
      async limit(input: { key: string }) {
        signatureKey = input.key;
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
  assert.equal(clientKey, `${CLIENT_IP}|${SIGNATURE}`);
  assert.equal(signatureKey, SIGNATURE);
  assert.equal(received.component, 'quickshell');
  assert.equal(received.failure_stage, 'start');
});
