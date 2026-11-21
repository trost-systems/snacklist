// Input text the API and the MCP tools pass on to Postgres.
import { z } from 'zod';

/** Text as Postgres stores it: any character but U+0000, which it refuses with a server error. */
export const storedText = z.string().refine(
  (s) => !s.includes('\u0000'),
  'Must not contain U+0000',
);
