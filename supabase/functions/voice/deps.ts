// The handler's dependencies in production: the database, the shared auth and telemetry. Kept out
// of index.ts so the database integration test runs the same wiring.
import { analyticsSubject } from '../alexa/store.ts';
import { type Auth, authenticate } from '../_shared/auth.ts';
import { asUser, isMember, serviceDb } from '../_shared/db.ts';
import { listItems } from '../_shared/list.ts';
import { requirePremiumWith } from '../_shared/premium.ts';
import type { Telemetry } from '../_shared/telemetry.ts';
import type { Deps } from './handler.ts';
import { addItems, splitItems } from './items.ts';

export function productionDeps(
  telemetry: Telemetry,
  resolve: Deps<Auth>['authenticate'] = (req) => authenticate(req, undefined, { siri: true }),
): Deps<Auth> {
  return {
    authenticate: resolve,
    requirePremium: requirePremiumWith(telemetry),
    isMember: (auth, household) => isMember(auth.userId, household),
    addItems: (auth, items, options) =>
      asUser(auth.userId, (tx) => addItems(tx, auth.householdId, items, options)),
    splitItems: (auth, items) =>
      asUser(auth.userId, (tx) => splitItems(tx, auth.householdId, items)),
    readItems: async (auth) =>
      (await asUser(auth.userId, (tx) => listItems(tx, auth.householdId, {}))).items,
    track: async (auth, { event, ...properties }) => {
      if (!telemetry.enabled) return;
      const subject = await analyticsSubject(serviceDb(), auth.userId);
      if (!subject) return;
      telemetry.event(event, subject, properties);
    },
    report: (e) => telemetry.exception(e),
  };
}
