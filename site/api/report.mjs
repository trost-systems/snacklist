import process from 'node:process';
import { createLimiter, handle } from './_report.mjs';

// One limiter per function instance: Vercel keeps an instance warm between requests.
const limiter = createLimiter();

export const POST = (request) => handle(request, { env: process.env, fetch: globalThis.fetch, now: new Date(), limiter });
