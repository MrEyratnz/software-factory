#!/usr/bin/env node
// otel-emit — push ONE OTLP/HTTP-JSON metric datapoint to an OTEL collector.
// Zero-dependency by design (see hooks/lib/common.sh's otel_emit): hand-built
// OTLP JSON (resourceMetrics[].scopeMetrics[].metrics[], sum|gauge datapoints
// only — no traces, no spans) posted with node's built-in http/https, never
// @opentelemetry/*.
//
// This is best-effort telemetry, not part of the enforcement path. Its caller
// backgrounds and disowns this process specifically so it can never block or
// change a hook's decision — so every failure mode here (bad args, missing
// endpoint, DNS failure, connection refused, timeout, non-2xx response) is
// swallowed, and the process ALWAYS exits 0. A dead or missing collector must
// be invisible to the commit/release path.
//
// argv: [name, type("sum"|"gauge"), value, attrsJson]
// env:  OTEL_ENDPOINT — collector base URL (e.g. http://localhost:4318)
import http from 'node:http';
import https from 'node:https';

const HARD_TIMEOUT_MS = 250;

let done = false;
function finish() {
  if (done) return;
  done = true;
  process.exit(0);
}
process.on('uncaughtException', finish);
process.on('unhandledRejection', finish);

const [, , name, type, rawValue, rawAttrs] = process.argv;
const endpoint = process.env.OTEL_ENDPOINT || '';
const value = Number(rawValue);

if (!name || (type !== 'sum' && type !== 'gauge') || !Number.isFinite(value) || !endpoint) {
  finish();
} else {
  let attrs = {};
  try {
    const parsed = JSON.parse(rawAttrs || '{}');
    if (parsed && typeof parsed === 'object') attrs = parsed;
  } catch {
    attrs = {};
  }

  const attributes = Object.entries(attrs)
    .filter(([, v]) => v !== undefined && v !== null)
    .map(([key, v]) => ({ key, value: { stringValue: String(v) } }));

  const dataPoint = {
    attributes,
    timeUnixNano: String(Date.now() * 1e6),
    asDouble: value,
  };

  const metric = {
    name,
    unit: '1',
    ...(type === 'sum'
      ? { sum: { dataPoints: [dataPoint], aggregationTemporality: 2, isMonotonic: true } }
      : { gauge: { dataPoints: [dataPoint] } }),
  };

  const payload = JSON.stringify({
    resourceMetrics: [
      {
        resource: {
          attributes: [{ key: 'service.name', value: { stringValue: 'dark-software-factory' } }],
        },
        scopeMetrics: [
          { scope: { name: 'dark-software-factory-hooks' }, metrics: [metric] },
        ],
      },
    ],
  });

  let url;
  try {
    url = new URL('/v1/metrics', endpoint);
  } catch {
    url = null;
  }

  if (!url || (url.protocol !== 'http:' && url.protocol !== 'https:')) {
    finish();
  } else {
    // Hard backstop: whatever happens to the request/socket, never outlive
    // this — guarantees "always exits" even if some error path above forgets
    // to call finish().
    const backstop = setTimeout(finish, HARD_TIMEOUT_MS + 100);
    backstop.unref?.();

    try {
      const transport = url.protocol === 'https:' ? https : http;
      const req = transport.request(
        url,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(payload),
          },
          timeout: HARD_TIMEOUT_MS,
        },
        (res) => {
          res.on('data', () => {});
          res.on('end', finish);
          res.on('error', finish);
        },
      );
      req.on('timeout', () => {
        req.destroy();
        finish();
      });
      req.on('error', finish);
      req.end(payload);
    } catch {
      finish();
    }
  }
}
