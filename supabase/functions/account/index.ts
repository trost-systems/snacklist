import { authenticateSession, secretKeyFromEnv, supabaseUrl } from '../_shared/auth.ts';
import { appleSubject, deleteAccount, serviceDb } from '../_shared/db.ts';
import {
  sqlSweepStore,
  storageRemover,
  sweepFeedbackScreenshots,
} from '../_shared/feedback_screenshots.ts';
import { telemetryFor, withTelemetry } from '../_shared/telemetry.ts';
import { appleConfig, revokeAppleGrant } from './apple.ts';
import { createHandler } from './handler.ts';

const telemetry = telemetryFor('account');

Deno.serve(withTelemetry(
  'account',
  createHandler({
    authenticate: (req) => authenticateSession(req),
    appleSubject,
    revokeApple: (grant) => revokeAppleGrant(grant, appleConfig()),
    deleteAccount,
    afterDeletion: () =>
      sweepFeedbackScreenshots(
        sqlSweepStore(serviceDb),
        storageRemover(supabaseUrl(), secretKeyFromEnv()),
      ),
    report: (e) => telemetry.exception(e),
  }),
  telemetry,
));
