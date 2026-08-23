import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, verify } from 'node:crypto';
import { createAppJwt, createGitHubClient } from '../src/github.ts';

function decodeBase64Url(value: string): Buffer {
  return Buffer.from(value.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

for (const format of ['pkcs1', 'pkcs8'] as const) {
  test(`createAppJwt signs a verifiable RS256 JWT from ${format} PEM`, async () => {
    const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
    const pem = privateKey.export({
      format: 'pem',
      type: format,
    }).toString();

    const jwt = await createAppJwt('4695629', pem, 1_800_000_000);
    const [headerPart, payloadPart, signaturePart] = jwt.split('.');
    assert.ok(headerPart && payloadPart && signaturePart);

    assert.deepEqual(JSON.parse(decodeBase64Url(headerPart).toString('utf8')), {
      alg: 'RS256',
      typ: 'JWT',
    });
    assert.deepEqual(JSON.parse(decodeBase64Url(payloadPart).toString('utf8')), {
      iat: 1_799_999_940,
      exp: 1_800_000_540,
      iss: '4695629',
    });

    const valid = verify(
      'RSA-SHA256',
      Buffer.from(`${headerPart}.${payloadPart}`),
      publicKey,
      decodeBase64Url(signaturePart),
    );
    assert.equal(valid, true);
  });
}

test('GitHub client exchanges app JWT and creates only fixed test issue content', async () => {
  const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const pem = privateKey.export({ format: 'pem', type: 'pkcs1' }).toString();
  const calls: Array<{ url: string; init?: RequestInit }> = [];

  const fakeFetch: typeof fetch = async (input, init) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    calls.push({ url, init });

    if (url.endsWith('/app/installations/156041074/access_tokens')) {
      assert.match(String(init?.headers && new Headers(init.headers).get('Authorization')), /^Bearer [^.]+\.[^.]+\.[^.]+$/);
      return Response.json({ token: 'installation-token' }, { status: 201 });
    }

    if (url.includes('/repos/dillacorn/awtarchy/issues?')) {
      assert.equal(new Headers(init?.headers).get('Authorization'), 'Bearer installation-token');
      return Response.json([], { status: 200 });
    }

    if (url.endsWith('/repos/dillacorn/awtarchy/issues')) {
      assert.equal(new Headers(init?.headers).get('Authorization'), 'Bearer installation-token');
      const body = JSON.parse(String(init?.body));
      assert.equal(body.title, '[TEST] Awtarchy anonymous crash reporting');
      assert.match(body.body, /No user diagnostic data is included/);
      assert.match(body.body, /<!-- awtarchy-report-fingerprint:[0-9a-f]{64} -->/);
      assert.equal(body.body.includes('attacker'), false);
      return Response.json({
        number: 77,
        html_url: 'https://github.com/dillacorn/awtarchy/issues/77',
        body: body.body,
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

  assert.equal(await client.findIssueByFingerprint('a'.repeat(64)), null);
  const issue = await client.createTestIssue('a'.repeat(64));
  assert.deepEqual(issue, {
    number: 77,
    url: 'https://github.com/dillacorn/awtarchy/issues/77',
  });
  assert.equal(calls.length, 4, 'each GitHub operation gets a fresh installation token');
});

test('GitHub client recovers an existing issue by exact fingerprint marker', async () => {
  const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const pem = privateKey.export({ format: 'pem', type: 'pkcs8' }).toString();
  const fingerprint = 'b'.repeat(64);
  const fakeFetch: typeof fetch = async (input) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    if (url.includes('/access_tokens')) {
      return Response.json({ token: 'installation-token' }, { status: 201 });
    }
    if (url.includes('/issues?')) {
      return Response.json([
        { number: 8, html_url: 'https://github.com/dillacorn/awtarchy/issues/8', body: 'unrelated' },
        {
          number: 9,
          html_url: 'https://github.com/dillacorn/awtarchy/issues/9',
          body: `test\n<!-- awtarchy-report-fingerprint:${fingerprint} -->`,
        },
      ]);
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

  assert.deepEqual(await client.findIssueByFingerprint(fingerprint), {
    number: 9,
    url: 'https://github.com/dillacorn/awtarchy/issues/9',
  });
});
