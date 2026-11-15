// The feedback screenshot upload and sweep: /functions/v1/feedback-screenshots/... (handler.ts).
// Not wrapped in withTelemetry: its errors could carry object names, which start with a user id.
import { authenticateSession, secretKeyFromEnv, supabaseUrl } from '../_shared/auth.ts';
import { serviceDb } from '../_shared/db.ts';
import {
  sqlSweepStore,
  storageRemover,
  sweepFeedbackScreenshots,
} from '../_shared/feedback_screenshots.ts';
import { createHandler } from './handler.ts';
import { sqlScreenshotStore, storagePutter } from './upload.ts';

Deno.serve(createHandler({
  sweep: () =>
    sweepFeedbackScreenshots(
      sqlSweepStore(serviceDb),
      storageRemover(supabaseUrl(), secretKeyFromEnv()),
    ),
  authenticate: (req) => authenticateSession(req),
  store: (userId, id, png) =>
    sqlScreenshotStore(serviceDb, storagePutter(supabaseUrl(), secretKeyFromEnv()))(
      userId,
      id,
      png,
    ),
}));
