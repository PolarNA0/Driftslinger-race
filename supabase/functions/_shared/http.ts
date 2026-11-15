// Shared plumbing for the two Edge Functions.

// The game is served from a different origin (Cloudflare) than the API
// (supabase.co), so every response needs CORS. The board is public data with no
// cookies and no credentials, so a permissive policy is safe here - it only lets
// a page on another host read public scores.
export const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers': 'authorization, content-type, apikey, x-client-info',
  'access-control-max-age': '86400',
};

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'content-type': 'application/json; charset=utf-8' },
  });

/** Answer a CORS preflight, or null when this is a real request. */
export const preflight = (req: Request) =>
  req.method === 'OPTIONS' ? new Response(null, { status: 204, headers: CORS }) : null;

/** The bearer token from the Authorization header, or null. */
export const bearer = (req: Request): string | null => {
  const raw = req.headers.get('authorization') ?? '';
  const m = raw.match(/^Bearer\s+(.+)$/i);
  return m ? m[1].trim() : null;
};
