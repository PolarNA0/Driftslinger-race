// The leaderboard store.
//
// One JSON file, written atomically. At this scale (a few hundred runs per track)
// a file is the right answer: no database to run, no service to pay for, and the
// whole board can be backed up by copying one file.
import { readFile, writeFile, rename, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const DEFAULT_PATH = join(HERE, 'data', 'board.json');

// Only the fastest runs are kept; the tail is not worth storing.
const MAX_KEEP = 500;
// Steps are stored only for the head, because a watchable ghost is what the head
// is for and steps are the bulk of the file (a run is ~1.2 KB of button bits).
const STEPS_KEEP = 25;
const NAME_MAX = 16;

export const cleanName = (raw) => {
  const s = String(raw ?? '').replace(/[\u0000-\u001f\u007f]/g, '').trim();
  return (s.slice(0, NAME_MAX) || 'Player');
};

export class Store {
  constructor(path = DEFAULT_PATH) {
    this.path = path;
    this.tracks = {};        // track number -> array of entries, ascending by time
    this._write = Promise.resolve();
  }

  async load() {
    try {
      this.tracks = JSON.parse(await readFile(this.path, 'utf8'));
    } catch {
      this.tracks = {};      // no file yet, or unreadable: start empty
    }
    return this;
  }

  // Serialise writes so two concurrent requests cannot interleave.
  save() {
    this._write = this._write.then(async () => {
      await mkdir(dirname(this.path), { recursive: true });
      const tmp = `${this.path}.tmp`;
      await writeFile(tmp, JSON.stringify(this.tracks));
      await rename(tmp, this.path);
    });
    return this._write;
  }

  list(track) { return this.tracks[track] || []; }

  /**
   * Add a verified run. Returns { rank, entry, improved }.
   *
   * A client keeps only its best run per track, so one person cannot fill the
   * board, and an identical button sequence is stored once no matter who sends it.
   */
  add(track, { time, name, steps, clientId }) {
    const list = this.tracks[track] || (this.tracks[track] = []);
    const entry = { time, name: cleanName(name), steps, clientId, at: Date.now() };

    const dupe = list.findIndex((e) => e.steps === steps);
    if (dupe !== -1) {
      // Same run already known. Keep the faster claim only if it is the same time.
      return { rank: dupe + 1, entry: list[dupe], improved: false };
    }

    const mine = list.findIndex((e) => e.clientId && e.clientId === clientId);
    if (mine !== -1) {
      if (list[mine].time <= time) {
        // Their previous best on this track is better; nothing changes.
        return { rank: mine + 1, entry: list[mine], improved: false };
      }
      list.splice(mine, 1);   // replaced below by the better run
    }

    let lo = 0, hi = list.length;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (list[mid].time < time) lo = mid + 1; else hi = mid;
    }
    list.splice(lo, 0, entry);
    if (list.length > MAX_KEEP) list.length = MAX_KEEP;

    for (let i = STEPS_KEEP; i < list.length; i++) delete list[i].steps;
    if (lo < STEPS_KEEP) { /* entry keeps its steps */ }

    this.save();
    return { rank: lo + 1, entry, improved: true };
  }

  /** One page of the board, 1-based, plus the total. */
  page(track, pageNum, perPage) {
    const list = this.list(track);
    const pages = Math.max(1, Math.ceil(list.length / perPage));
    const p = Math.min(Math.max(1, Math.floor(pageNum) || 1), pages);
    const start = (p - 1) * perPage;
    const rows = list.slice(start, start + perPage).map((e, i) => ({
      rank: start + i + 1,
      name: e.name,
      time: e.time,
      watchable: typeof e.steps === 'string',
      steps: typeof e.steps === 'string' ? e.steps : null,
    }));
    return { rows, page: p, pages, total: list.length };
  }

  /** This player's best rank on a track, or null if they have not posted one. */
  rankOf(track, clientId) {
    if (!clientId) return null;
    const i = this.list(track).findIndex((e) => e.clientId === clientId);
    return i === -1 ? null : i + 1;
  }
}
