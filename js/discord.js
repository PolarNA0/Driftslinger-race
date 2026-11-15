/**
 * Posting to a Discord webhook.
 *
 * Discord's webhook endpoint answers a browser directly - it reflects the Origin
 * and allows POST with a JSON body - so a message can be sent without a server in
 * between. That keeps the whole feature offline-friendly and needs no deployment.
 *
 * The webhook URL is the credential: anyone holding it can post to the channel.
 * It is kept in the player's own settings and only ever sent to Discord itself.
 */

const TIMEOUT = 8000;

/** Post `content` to a webhook. Returns true only if Discord accepted it. */
export async function postWebhook(url, content) {
  if (!url) return false;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), TIMEOUT);
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      // Discord caps webhook content at 2000 characters.
      body: JSON.stringify({ content: String(content).slice(0, 1900) }),
      signal: ctl.signal,
    });
    return res.ok;
  } catch {
    return false;                 // offline, DNS, timeout, or a dead webhook
  } finally {
    clearTimeout(timer);
  }
}
