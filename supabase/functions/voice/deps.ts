// The handler's dependencies in production: the database, the shared auth and telemetry. Kept out
// of index.ts so the database integration test runs the same wiring.
import { analyticsSubject } from '../alexa/store.ts';
import { afterResponse } from '../_shared/after_response.ts';
import { type Auth, authenticate } from '../_shared/auth.ts';
import { asUser, isMember, serviceDb } from '../_shared/db.ts';
import { scrubMessage, type Telemetry } from '../_shared/telemetry.ts';
import type { Deps } from './handler.ts';
import { addItems, splitItems } from './items.ts';
import { householdLists, itemsToSay } from './read.ts';

export function productionDeps(
  telemetry: Telemetry,
  resolve: Deps<Auth>['authenticate'] = (req) => authenticate(req, undefined, { siri: true }),
): Deps<Auth> {
  return {
    authenticate: resolve,
    isMember: (auth, household) => isMember(auth.userId, household),
    lists: (auth) =>
      asUser(auth.userId, async (tx) => (await householdLists(tx, auth.householdId)).catalog),
    addItems: (auth, items, options) =>
      asUser(auth.userId, (tx) => addItems(tx, auth.householdId, items, options)),
    splitItems: (auth, items) =>
      asUser(auth.userId, (tx) => splitItems(tx, auth.householdId, items)),
    readItems: (auth) => asUser(auth.userId, (tx) => itemsToSay(tx, auth.householdId)),
    // The event is looked up and sent after the answer (_shared/after_response.ts). A failure is
    // logged as the handler logs one, never reported to error tracking.
    track: async (auth, { event, ...properties }) => {
      if (!telemetry.enabled) return;
      await afterResponse(async () => {
        try {
          const subject = await analyticsSubject(serviceDb(), auth.userId);
          if (subject) telemetry.event(event, subject, properties);
        } catch (e) {
          console.error('voice: event not recorded', `${(e as Error)?.name}: ${scrubMessage(e)}`);
        }
      }, telemetry);
    },
    report: (e) => telemetry.exception(e),
  };
}
