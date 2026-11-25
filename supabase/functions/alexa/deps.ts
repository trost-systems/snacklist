// The handler's dependencies in production: the database, the shared auth and telemetry. Kept out
// of index.ts so the database integration test runs the same wiring.
import { afterResponse } from '../_shared/after_response.ts';
import { authenticate, AuthError } from '../_shared/auth.ts';
import { asUser, serviceDb } from '../_shared/db.ts';
import type { Telemetry } from '../_shared/telemetry.ts';
import { addItems } from '../voice/items.ts';
import { householdLists, itemsToSay } from '../voice/read.ts';
import { countAdds } from './analytics.ts';
import type { Deps, Linked } from './handler.ts';
import { analyticsSubject, remember, revoke, takeAdds } from './store.ts';

/** An OAuth access token from account linking; a PAT or an app session is no link. */
export async function linkedBy(accessToken: string): Promise<Linked> {
  const auth = await authenticate(
    new Request('http://alexa.local/', { headers: { authorization: `Bearer ${accessToken}` } }),
  );
  if (auth.via !== 'oauth') throw new AuthError('invalid_token', 'Kein Alexa-Zugang.', 'not_oauth');
  return { userId: auth.userId, householdId: auth.householdId, sessionId: auth.sessionId };
}

export function productionDeps(
  telemetry: Telemetry,
  verify: Deps['verify'],
  resolve: Deps['authenticate'] = linkedBy,
): Deps {
  return {
    verify,
    authenticate: resolve,
    takeAdds: (linked, count) => takeAdds(serviceDb(), linked.userId, count),
    lists: (linked) =>
      asUser(linked.userId, async (tx) => (await householdLists(tx, linked.householdId)).catalog),
    addItems: (linked, items, options) =>
      asUser(linked.userId, (tx) => addItems(tx, linked.householdId, items, options)),
    listItems: (linked) => asUser(linked.userId, (tx) => itemsToSay(tx, linked.householdId)),
    // A request's own link is noted after the answer; a new link (a skill event) before it, so a
    // failure there is answered with 500 and Alexa sends the event again.
    remember: async (alexaUser, linked, relinked) => {
      const note = async () => {
        await remember(serviceDb(), alexaUser, linked, relinked);
      };
      await (relinked ? note() : afterResponse(note, telemetry));
    },
    revoke: async (alexaUser) => {
      await revoke(serviceDb(), alexaUser);
    },
    counted: async (linked, added) => {
      if (!telemetry.enabled || added.every((a) => a.alreadyOnList)) return;
      await afterResponse(async () => {
        countAdds(telemetry, await analyticsSubject(serviceDb(), linked.userId), added);
      }, telemetry);
    },
    report: (e) => telemetry.exception(e),
    log: (line) => console.log(line),
  };
}
