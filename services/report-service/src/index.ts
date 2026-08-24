import {
  canonicalFailureId,
  FailureValidationError,
  runFailureReport,
  validateFailurePayload,
  type FailurePayload,
  type FailureReportOptions,
  type FailureReportResult,
} from './failure-report.ts';
import { runControlledTest, type ControlledTestResult, type ReportServiceEnv } from './test-report.ts';

type ReportRateLimiter = {
  limit(input: { key: string }): Promise<{ success: boolean }>;
};

export type WorkerEnv = ReportServiceEnv & {
  REPORT_RATE_LIMITER: ReportRateLimiter;
};
type RunTest = (env: WorkerEnv) => Promise<ControlledTestResult | Record<string, unknown>>;
type RunReport = (
  env: WorkerEnv,
  payload: FailurePayload,
  options?: FailureReportOptions,
) => Promise<FailureReportResult | Record<string, unknown>>;

const MAX_REPORT_BYTES = 32 * 1024;

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

function isJsonContentType(request: Request): boolean {
  const contentType = request.headers.get('Content-Type') ?? '';
  return contentType.split(';', 1)[0].trim().toLowerCase() === 'application/json';
}

async function readReportText(request: Request): Promise<string> {
  const contentLength = request.headers.get('Content-Length');
  if (contentLength && /^\d+$/.test(contentLength) && Number(contentLength) > MAX_REPORT_BYTES) {
    throw new FailureValidationError('payload_too_large');
  }

  if (!request.body) return '';

  const reader = request.body.getReader();
  const decoder = new TextDecoder();
  let byteLength = 0;
  let text = '';

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      byteLength += value.byteLength;
      if (byteLength > MAX_REPORT_BYTES) {
        await reader.cancel('payload_too_large').catch(() => undefined);
        throw new FailureValidationError('payload_too_large');
      }
      text += decoder.decode(value, { stream: true });
    }
    text += decoder.decode();
    return text;
  } finally {
    reader.releaseLock();
  }
}

async function parseReportRequest(request: Request): Promise<FailurePayload> {
  const text = await readReportText(request);

  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    throw new FailureValidationError('malformed_json');
  }
  return validateFailurePayload(raw);
}

async function allowProductionReport(env: WorkerEnv, payload: FailurePayload): Promise<boolean | null> {
  if (!env.REPORT_RATE_LIMITER) return null;
  try {
    const result = await env.REPORT_RATE_LIMITER.limit({ key: canonicalFailureId(payload) });
    return result.success === true;
  } catch {
    return null;
  }
}

export async function handleRequest(
  request: Request,
  env: WorkerEnv,
  runTest: RunTest = runControlledTest,
  runReport: RunReport = runFailureReport,
): Promise<Response> {
  const url = new URL(request.url);

  if (request.method === 'GET' && url.pathname === '/health') {
    return json({ ok: true, service: 'awtarchy-reports', version: 1 });
  }

  if (request.method === 'POST' && url.pathname === '/v1/report') {
    if (!isJsonContentType(request)) {
      return json({ ok: false, error: 'unsupported_media_type' }, 415);
    }

    let payload: FailurePayload;
    try {
      payload = await parseReportRequest(request);
    } catch (error) {
      if (error instanceof FailureValidationError) {
        const status = error.code === 'payload_too_large' ? 413 : 400;
        return json({ ok: false, error: 'invalid_report', reason: error.code }, status);
      }
      return json({ ok: false, error: 'invalid_report' }, 400);
    }

    const rateLimit = await allowProductionReport(env, payload);
    if (rateLimit === null) return json({ ok: false, error: 'service_unavailable' }, 503);

    try {
      const result = await runReport(env, payload, { rateLimitAllowed: rateLimit });
      if ('pending' in result && result.pending === true) return json(result, 202);
      if ('ok' in result && result.ok === false) {
        if ('error' in result && result.error === 'rate_limited') return json(result, 429);
        return json(result, 502);
      }
      if ('created' in result && result.created === true) return json(result, 201);
      return json(result, 200);
    } catch {
      return json({ ok: false, error: 'internal_error' }, 500);
    }
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
