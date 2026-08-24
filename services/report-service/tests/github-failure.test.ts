import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { createGitHubClient } from '../src/github.ts';

test('GitHub client creates production issue from server-owned structured content', async () => {
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
        number: 88,
        html_url: 'https://github.com/dillacorn/awtarchy/issues/88',
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

  const issue = await client.createFailureIssue({
    fingerprint: 'c'.repeat(64),
    description: 'Quickshell did not become ready after update',
    component: 'quickshell',
    failureStage: 'restart_after_update',
    errorCode: 'quickshell_not_ready',
    awtarchyConfigVersion: 'v3.1.6',
    awtarchyCommandRevision: 'unknown',
    hyprlandVersion: '0.51.1',
    quickshellVersion: '0.2.0',
    kernelVersion: '6.17.1-arch1-1',
    gpuFamily: 'AMD',
  });

  assert.deepEqual(issue, {
    number: 88,
    url: 'https://github.com/dillacorn/awtarchy/issues/88',
  });
  assert.equal(posted.title, 'Automatic failure report: Quickshell did not become ready after update');
  assert.match(posted.body, /Component: `quickshell`/);
  assert.match(posted.body, /no username/i);
  assert.match(posted.body, /<!-- awtarchy-report-fingerprint:c{64} -->/);
  assert.equal(posted.body.includes('/home/'), false);
});
