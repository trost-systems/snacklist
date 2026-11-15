// The feedback screenshot sweep: /functions/v1/feedback-screenshots/sweep (handler.ts).
// Not wrapped in withTelemetry: its errors could carry object names, which start with a user id.
import { secretKeyFromEnv, supabaseUrl } from '../_shared/auth.ts';
import { serviceDb } from '../_shared/db.ts';
import {
  sqlSweepStore,
  storageRemover,
  sweepFeedbackScreenshots,
} from '../_shared/feedback_screenshots.ts';
import { createHandler } from './handler.ts';

Deno.serve(createHandler(() =>
  sweepFeedbackScreenshots(
    sqlSweepStore(serviceDb),
    storageRemover(supabaseUrl(), secretKeyFromEnv()),
  )
));
