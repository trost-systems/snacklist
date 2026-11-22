// Server push through FCM: /functions/v1/push (docs/PUSH.md). Internal, behind x-push-secret.
// Not wrapped in withTelemetry: nothing about a send leaves the function but the messages.
import { serviceDb } from '../_shared/db.ts';
import { configFrom, createHandler } from './handler.ts';
import { sqlStore } from './store.ts';

Deno.serve(createHandler({
  ...configFrom(Deno.env),
  store: sqlStore(serviceDb),
  now: () => new Date(),
}));
