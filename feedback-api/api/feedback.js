import { Resend } from 'resend';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

const MAX_MESSAGE = 4000;
const KINDS = new Set(['bug', 'idea', 'other', 'report']);
const MAX_REPORTED = 4000;
const TO = 'changkevin51@gmail.com';
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function applyCors(res) {
  for (const [key, value] of Object.entries(CORS)) {
    res.setHeader(key, value);
  }
}

function json(res, status, body) {
  applyCors(res);
  res.status(status).setHeader('Content-Type', 'application/json');
  res.send(JSON.stringify(body));
}

function parseBody(req) {
  if (req.body == null || req.body === '') return {};
  if (typeof req.body === 'object') return req.body;
  try {
    return JSON.parse(req.body);
  } catch (_) {
    return null;
  }
}

function sanitizeLine(value, max) {
  if (typeof value !== 'string') return '';
  return value.replace(/[\r\n\0]/g, ' ').trim().slice(0, max);
}

export default async function handler(req, res) {
  applyCors(res);

  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }

  if (req.method !== 'POST') {
    json(res, 405, { ok: false, error: 'POST only' });
    return;
  }

  const body = parseBody(req);
  if (body == null) {
    json(res, 400, { ok: false, error: 'Invalid JSON' });
    return;
  }

  // Bots filling a hidden field. Pretend success so they move on.
  if (typeof body.website === 'string' && body.website.trim() !== '') {
    json(res, 200, { ok: true });
    return;
  }

  const kindRaw = typeof body.kind === 'string' ? body.kind.trim().toLowerCase() : '';
  const kind = KINDS.has(kindRaw) ? kindRaw : 'idea';
  const message = typeof body.message === 'string' ? body.message.trim() : '';

  if (message.length < 8) {
    json(res, 400, { ok: false, error: 'Message too short' });
    return;
  }
  if (message.length > MAX_MESSAGE) {
    json(res, 400, { ok: false, error: 'Message too long' });
    return;
  }

  const emailRaw = typeof body.email === 'string' ? body.email.trim() : '';
  let replyTo;
  if (emailRaw) {
    if (emailRaw.length > 200 || !EMAIL_RE.test(emailRaw)) {
      json(res, 400, { ok: false, error: 'That email does not look right' });
      return;
    }
    replyTo = emailRaw;
  }

  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) {
    json(res, 500, { ok: false, error: 'Feedback is not configured yet' });
    return;
  }

  const version = sanitizeLine(body.version, 32) || 'unknown';
  const platform = sanitizeLine(body.platform, 64) || 'unknown';
  const kindLabel = kind.charAt(0).toUpperCase() + kind.slice(1);
  const reportedRaw =
    typeof body.reportedContent === 'string' ? body.reportedContent.trim() : '';
  const reported = reportedRaw.slice(0, MAX_REPORTED);

  const text = [
    `Kind: ${kindLabel}`,
    `Version: ${version}`,
    `Platform: ${platform}`,
    replyTo ? `Reply-to: ${replyTo}` : 'Reply-to: (none)',
    '',
    message,
    reported ? `\n--- Reported AI output ---\n${reported}` : '',
  ].filter(Boolean).join('\n');

  try {
    const resend = new Resend(apiKey);
    const { error } = await resend.emails.send({
      from: 'Scrapyard Feedback <onboarding@resend.dev>',
      to: TO,
      replyTo,
      subject: `[Scrapyard] ${kindLabel}`,
      text,
    });

    if (error) {
      json(res, 502, { ok: false, error: 'Could not send just now' });
      return;
    }

    json(res, 200, { ok: true });
  } catch (_) {
    json(res, 502, { ok: false, error: 'Could not send just now' });
  }
}
