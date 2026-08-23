import test from 'node:test';
import assert from 'node:assert/strict';
import { handleRequest } from '../src/index.ts';

type Env = {
  TEST_AUTH_TOKEN?: string;
};

test('GET /health is public and side-effect free', async () => {
  let called = 0;
  const response = await handleRequest(
    new Request('https://example.test/health'),
    {} as Env,
    async () => {
      called += 1;
      throw new Error('must not run');
    },
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    ok: true,
    service: 'awtarchy-reports',
    version: 1,
  });
  assert.equal(called, 0);
});

test('unknown routes return JSON 404', async () => {
  const response = await handleRequest(
    new Request('https://example.test/nope'),
    {} as Env,
    async () => ({ ok: true }),
  );

  assert.equal(response.status, 404);
  assert.deepEqual(await response.json(), { ok: false, error: 'not_found' });
});

test('POST /v1/test is disabled when TEST_AUTH_TOKEN is missing', async () => {
  let called = 0;
  const response = await handleRequest(
    new Request('https://example.test/v1/test', { method: 'POST' }),
    {} as Env,
    async () => {
      called += 1;
      return { ok: true };
    },
  );

  assert.equal(response.status, 404);
  assert.deepEqual(await response.json(), { ok: false, error: 'not_found' });
  assert.equal(called, 0);
});

test('POST /v1/test rejects missing or wrong bearer token', async () => {
  for (const authorization of [undefined, 'Bearer wrong', 'Basic secret']) {
    let called = 0;
    const headers = new Headers();
    if (authorization) headers.set('Authorization', authorization);
    const response = await handleRequest(
      new Request('https://example.test/v1/test', { method: 'POST', headers }),
      { TEST_AUTH_TOKEN: 'correct-secret' } as Env,
      async () => {
        called += 1;
        return { ok: true };
      },
    );

    assert.equal(response.status, 401);
    assert.deepEqual(await response.json(), { ok: false, error: 'unauthorized' });
    assert.equal(called, 0);
  }
});

test('POST /v1/test invokes fixed controlled workflow after authorization', async () => {
  let called = 0;
  const response = await handleRequest(
    new Request('https://example.test/v1/test', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer correct-secret',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ title: 'attacker title', body: 'attacker body' }),
    }),
    { TEST_AUTH_TOKEN: 'correct-secret' } as Env,
    async () => {
      called += 1;
      return {
        ok: true,
        created: true,
        deduplicated: false,
        issue_number: 123,
        issue_url: 'https://github.com/dillacorn/awtarchy/issues/123',
      };
    },
  );

  assert.equal(response.status, 200);
  assert.equal(called, 1);
  assert.deepEqual(await response.json(), {
    ok: true,
    created: true,
    deduplicated: false,
    issue_number: 123,
    issue_url: 'https://github.com/dillacorn/awtarchy/issues/123',
  });
});
