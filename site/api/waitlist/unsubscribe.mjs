import { handle } from '../_waitlist.mjs';

const unsubscribe = (request) => handle('unsubscribe', request, { env: process.env, fetch: globalThis.fetch, now: new Date() });
export { unsubscribe as GET, unsubscribe as POST };
