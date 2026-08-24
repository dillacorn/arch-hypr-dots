export type GitHubEnv = {
  GITHUB_APP_ID: string;
  GITHUB_APP_PRIVATE_KEY: string;
  GITHUB_INSTALLATION_ID: string;
  GITHUB_OWNER: string;
  GITHUB_REPO: string;
};

export type GitHubIssueRef = {
  number: number;
  url: string;
};

export type FailureIssueData = {
  fingerprint: string;
  description: string;
  component: string;
  failureStage: string;
  errorCode: string;
  awtarchyConfigVersion: string;
  awtarchyCommandRevision: string;
  hyprlandVersion: string;
  quickshellVersion: string;
  kernelVersion: string;
  gpuFamily: string;
  context?: { recovery_attempted?: boolean; recovery_succeeded?: boolean };
};

export type GitHubClient = {
  findIssueByFingerprint(fingerprint: string): Promise<GitHubIssueRef | null>;
  createTestIssue(fingerprint: string): Promise<GitHubIssueRef>;
  createFailureIssue(data: FailureIssueData): Promise<GitHubIssueRef>;
};

const GITHUB_API = 'https://api.github.com';
const GITHUB_API_VERSION = '2026-03-10';
const encoder = new TextEncoder();

function concatBytes(...parts: Uint8Array[]): Uint8Array {
  const size = parts.reduce((total, part) => total + part.length, 0);
  const output = new Uint8Array(size);
  let offset = 0;
  for (const part of parts) {
    output.set(part, offset);
    offset += part.length;
  }
  return output;
}

function derLength(length: number): Uint8Array {
  if (length < 0x80) return Uint8Array.of(length);
  const bytes: number[] = [];
  let remaining = length;
  while (remaining > 0) {
    bytes.unshift(remaining & 0xff);
    remaining >>>= 8;
  }
  return Uint8Array.of(0x80 | bytes.length, ...bytes);
}

function derWrap(tag: number, value: Uint8Array): Uint8Array {
  return concatBytes(Uint8Array.of(tag), derLength(value.length), value);
}

function pkcs1ToPkcs8(pkcs1: Uint8Array): Uint8Array {
  const version = Uint8Array.of(0x02, 0x01, 0x00);
  const rsaAlgorithmIdentifier = Uint8Array.of(
    0x30, 0x0d,
    0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
    0x05, 0x00,
  );
  const privateKey = derWrap(0x04, pkcs1);
  return derWrap(0x30, concatBytes(version, rsaAlgorithmIdentifier, privateKey));
}

function decodePemBody(pem: string): Uint8Array {
  const base64 = pem
    .replace(/-----BEGIN [^-]+-----/g, '')
    .replace(/-----END [^-]+-----/g, '')
    .replace(/\s+/g, '');
  if (!base64) throw new Error('github_private_key_invalid');

  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function privateKeyPkcs8Der(pem: string): Uint8Array {
  if (pem.includes('-----BEGIN PRIVATE KEY-----')) return decodePemBody(pem);
  if (pem.includes('-----BEGIN RSA PRIVATE KEY-----')) return pkcs1ToPkcs8(decodePemBody(pem));
  throw new Error('github_private_key_format_unsupported');
}

function base64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function base64UrlJson(value: unknown): string {
  return base64Url(encoder.encode(JSON.stringify(value)));
}

function assertFingerprint(fingerprint: string): void {
  if (!/^[0-9a-f]{64}$/.test(fingerprint)) throw new Error('invalid_fingerprint');
}

export async function createAppJwt(
  appId: string,
  privateKeyPem: string,
  nowSeconds = Math.floor(Date.now() / 1000),
): Promise<string> {
  if (!/^\d+$/.test(appId)) throw new Error('github_app_id_invalid');

  const header = base64UrlJson({ alg: 'RS256', typ: 'JWT' });
  const payload = base64UrlJson({
    iat: nowSeconds - 60,
    exp: nowSeconds + 540,
    iss: appId,
  });
  const signingInput = `${header}.${payload}`;

  const key = await crypto.subtle.importKey(
    'pkcs8',
    privateKeyPkcs8Der(privateKeyPem),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, encoder.encode(signingInput));
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

function githubHeaders(token: string): Headers {
  return new Headers({
    Accept: 'application/vnd.github+json',
    Authorization: `Bearer ${token}`,
    'User-Agent': 'awtarchy-report-service',
    'X-GitHub-Api-Version': GITHUB_API_VERSION,
  });
}

async function responseJson<T>(response: Response, errorCode: string): Promise<T> {
  if (!response.ok) throw new Error(errorCode);
  try {
    return await response.json() as T;
  } catch {
    throw new Error(errorCode);
  }
}

export function createGitHubClient(env: GitHubEnv, fetchImpl: typeof fetch = fetch): GitHubClient {
  const owner = encodeURIComponent(env.GITHUB_OWNER);
  const repo = encodeURIComponent(env.GITHUB_REPO);

  async function installationToken(): Promise<string> {
    const jwt = await createAppJwt(env.GITHUB_APP_ID, env.GITHUB_APP_PRIVATE_KEY);
    const response = await fetchImpl(
      `${GITHUB_API}/app/installations/${encodeURIComponent(env.GITHUB_INSTALLATION_ID)}/access_tokens`,
      {
        method: 'POST',
        headers: githubHeaders(jwt),
      },
    );
    const body = await responseJson<{ token?: unknown }>(response, 'github_installation_token_failed');
    if (typeof body.token !== 'string' || body.token.length === 0) {
      throw new Error('github_installation_token_failed');
    }
    return body.token;
  }

  return {
    async findIssueByFingerprint(fingerprint: string): Promise<GitHubIssueRef | null> {
      assertFingerprint(fingerprint);
      const token = await installationToken();
      const response = await fetchImpl(
        `${GITHUB_API}/repos/${owner}/${repo}/issues?state=all&per_page=100&sort=created&direction=desc`,
        { headers: githubHeaders(token) },
      );
      const issues = await responseJson<Array<{
        number?: unknown;
        html_url?: unknown;
        body?: unknown;
        pull_request?: unknown;
      }>>(response, 'github_issue_lookup_failed');
      const marker = `<!-- awtarchy-report-fingerprint:${fingerprint} -->`;
      for (const issue of issues) {
        if (issue.pull_request !== undefined) continue;
        if (typeof issue.body !== 'string' || !issue.body.includes(marker)) continue;
        if (typeof issue.number !== 'number' || typeof issue.html_url !== 'string') continue;
        return { number: issue.number, url: issue.html_url };
      }
      return null;
    },

    async createTestIssue(fingerprint: string): Promise<GitHubIssueRef> {
      assertFingerprint(fingerprint);
      const token = await installationToken();
      const marker = `<!-- awtarchy-report-fingerprint:${fingerprint} -->`;
      const body = [
        'This is a controlled end-to-end test of Awtarchy\'s anonymous failure-reporting path.',
        '',
        'No user diagnostic data is included.',
        '',
        `Report fingerprint: \`${fingerprint}\``,
        '',
        marker,
      ].join('\n');
      const response = await fetchImpl(
        `${GITHUB_API}/repos/${owner}/${repo}/issues`,
        {
          method: 'POST',
          headers: new Headers({
            ...Object.fromEntries(githubHeaders(token)),
            'Content-Type': 'application/json',
          }),
          body: JSON.stringify({
            title: '[TEST] Awtarchy anonymous crash reporting',
            body,
          }),
        },
      );
      const issue = await responseJson<{ number?: unknown; html_url?: unknown }>(
        response,
        'github_issue_creation_failed',
      );
      if (typeof issue.number !== 'number' || typeof issue.html_url !== 'string') {
        throw new Error('github_issue_creation_failed');
      }
      return { number: issue.number, url: issue.html_url };
    },

    async createFailureIssue(data: FailureIssueData): Promise<GitHubIssueRef> {
      assertFingerprint(data.fingerprint);
      const token = await installationToken();
      const marker = `<!-- awtarchy-report-fingerprint:${data.fingerprint} -->`;
      const bodyLines = [
        'This issue was created from a user-approved, sanitized Awtarchy failure report.',
        '',
        `Component: \`${data.component}\``,
        `Stage: \`${data.failureStage}\``,
        `Error code: \`${data.errorCode}\``,
        '',
        `Awtarchy config: \`${data.awtarchyConfigVersion}\``,
        `Awtarchy command revision: \`${data.awtarchyCommandRevision}\``,
        `Hyprland: \`${data.hyprlandVersion}\``,
        `Quickshell: \`${data.quickshellVersion}\``,
        `Kernel: \`${data.kernelVersion}\``,
        `GPU family: \`${data.gpuFamily}\``,
      ];
      if (data.context) {
        if (data.context.recovery_attempted !== undefined) {
          bodyLines.push(`Recovery attempted: \`${data.context.recovery_attempted}\``);
        }
        if (data.context.recovery_succeeded !== undefined) {
          bodyLines.push(`Recovery succeeded: \`${data.context.recovery_succeeded}\``);
        }
      }
      bodyLines.push(
        '',
        'The report payload contains no username, hostname, home-directory path, raw log, or persistent installation identifier.',
        '',
        `Report fingerprint: \`${data.fingerprint}\``,
        '',
        marker,
      );
      const response = await fetchImpl(
        `${GITHUB_API}/repos/${owner}/${repo}/issues`,
        {
          method: 'POST',
          headers: new Headers({
            ...Object.fromEntries(githubHeaders(token)),
            'Content-Type': 'application/json',
          }),
          body: JSON.stringify({
            title: `Automatic failure report: ${data.description}`,
            body: bodyLines.join('\n'),
          }),
        },
      );
      const issue = await responseJson<{ number?: unknown; html_url?: unknown }>(
        response,
        'github_issue_creation_failed',
      );
      if (typeof issue.number !== 'number' || typeof issue.html_url !== 'string') {
        throw new Error('github_issue_creation_failed');
      }
      return { number: issue.number, url: issue.html_url };
    },
  };
}
