import { runControlledTest, type ControlledTestResult, type ReportServiceEnv } from './test-report.ts';

export type WorkerEnv = ReportServiceEnv;
type RunTest = (env: WorkerEnv) => Promise<ControlledTestResult | Record<string, unknown>>;

function json(value: unknown, status = 200): Response {
  return Response.json(value, {
    status,
    headers: {
      'Cache-Control': 'no-store',
    },
  });
}

function constantTimeEqual(left: string, right: string): boolean {
  const encoder = new TextEncoder();
  const a = encoder.encode(left);
  const b = encoder.encode(right);
  const length = Math.max(a.length, b.length);
  let mismatch = a.length ^ b.length;
  for (let i = 0; i < length; i += 1) {
    mismatch |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return mismatch === 0;
}

function bearerToken(request: Request): string | null {
  const authorization = request.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) return null;
  const token = authorization.slice('Bearer '.length);
  return token.length > 0 ? token : null;
}

export async function handleRequest(
  request: Request,
  env: WorkerEnv,
  runTest: RunTest = runControlledTest,
): Promise<Response> {
  const url = new URL(request.url);

  if (request.method === 'GET' && url.pathname === '/health') {
    return json({ ok: true, service: 'awtarchy-reports', version: 1 });
  }

  if (request.method === 'POST' && url.pathname === '/v1/test') {
    if (!env.TEST_AUTH_TOKEN) return json({ ok: false, error: 'not_found' }, 404);
    const supplied = bearerToken(request);
    if (!supplied || !constantTimeEqual(supplied, env.TEST_AUTH_TOKEN)) {
      return json({ ok: false, error: 'unauthorized' }, 401);
    }

    try {
      const result = await runTest(env);
      if ('pending' in result && result.pending === true) return json(result, 202);
      if ('ok' in result && result.ok === false) return json(result, 502);
      return json(result, 200);
    } catch {
      return json({ ok: false, error: 'internal_error' }, 500);
    }
  }

  return json({ ok: false, error: 'not_found' }, 404);
}

export default {
  fetch(request: Request, env: WorkerEnv): Promise<Response> {
    return handleRequest(request, env);
  },
};
