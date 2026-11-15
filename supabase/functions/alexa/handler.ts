// POST /functions/v1/alexa: the endpoint of the custom Alexa skills "Snacklist" and, until S5,
// "Hummlist" (de-DE, en-*; the request's locale picks the language, voices.ts).
// Every request is verified first (verify.ts); a refused one answers 400 and touches nothing.
// The linked account is the Supabase OAuth access token Alexa got through account linking; its
// user's default household (household_members.is_default, read per request) is the one written
// to, never anything from the request. Adds go through the Siri path (voice/parse.ts,
// voice/items.ts), so items are split, categorized and deduplicated exactly as in the app.
// Job 207: AddToListIntent's `list` slot, or a list phrase the items slot ends with ("luftballons
// zur geburtstag liste"), names a list of that household (_shared/spoken_list.ts); without one
// the add goes to the user's default list there.
import { AuthError } from '../_shared/auth.ts';
import { json } from '../_shared/http.ts';
import type { ListCatalog } from '../_shared/list.ts';
import { type ListWish, takeListPhrase, targetOf } from '../_shared/spoken_list.ts';
import type { Added } from '../voice/handler.ts';
import { maxTextLength } from '../voice/handler.ts';
import { maxItems, type ParsedItem } from '../voice/parse.ts';
import { clip, speech, type Spoken } from './speech.ts';
import { speechFor } from './voices.ts';
import { type Envelope, VerificationError } from './verify.ts';

/** The account behind a linked Alexa user. */
export interface Linked {
  userId: string;
  householdId: string;
  /** The Supabase session behind the access token (revoked when the skill is disabled). */
  sessionId: string;
}

export interface Deps {
  /** verify.ts's verifyRequest with the production (or test) trust. */
  verify(headers: Headers, body: Uint8Array<ArrayBuffer>): Promise<Envelope>;
  /** Resolves an OAuth access token; throws an AuthError when it is not a live link. */
  authenticate(accessToken: string): Promise<Linked>;
  /** Takes [count] from the user's allowance (30 items a minute); false when it is used up. */
  takeAdds(linked: Linked, count: number): Promise<boolean>;
  /** The household's lists and the user's default one (job 207). */
  lists(linked: Linked): Promise<ListCatalog>;
  /**
   * Adds to the list [options.list] (an id from `lists`); `addVariants`: the yes to the Q79
   * question, held items are added (voice/items.ts).
   */
  addItems(
    linked: Linked,
    items: ParsedItem[],
    options: { addVariants?: boolean; list: string },
  ): Promise<Added[]>;
  /** The household's open items in aisle order. */
  listItems(linked: Linked): Promise<Spoken[]>;
  /** Remembers which session this Alexa user holds; [relinked] revokes the ones before it. */
  remember(alexaUserId: string, linked: Linked, relinked: boolean): Promise<void>;
  /** Revokes every session this Alexa user holds (the skill was disabled). */
  revoke(alexaUserId: string): Promise<void>;
  /** Analytics for an add, if the user said yes in the app (never names). */
  counted(linked: Linked, added: Added[]): Promise<void>;
  /** Error tracking (telemetry.ts); scrubbed there. */
  report(error: unknown): void;
  /** Writes the one request line (requestLine) to the function log. */
  log(line: string): void;
}

/**
 * What a request was answered with, for the request line. The job 74 brief named link, launch,
 * added, read, help, empty and error; the others are answers those would mislabel.
 */
export const replyKinds = [
  'link',
  'no-household',
  'launch',
  'added',
  'ask',
  'read',
  'help',
  'goodbye',
  'reprompt',
  'not-understood',
  'too-long',
  'rate-limited',
  'empty',
  'error',
  'refused',
] as const;
export type ReplyKind = typeof replyKinds[number];

interface Reply {
  speech?: string;
  reprompt?: string;
  end: boolean;
  kind: ReplyKind;
  card?: 'link' | string;
  /** Ask for the items again, on [intent]. */
  elicit?: boolean;
  /** Q79: ask yes or no about these items (the slot's new value), on [intent]. */
  confirm?: string;
  /** The add intent a dialog directive continues, with its list slot; AddItemIntent by default. */
  intent?: AddIntent;
  attributes?: Record<string, unknown>;
  /** Why a linked token is no link (linkReason), for the request line. */
  reason?: string;
}

/** The intents that add: AddToListIntent carries the list's name in its own slot (job 207). */
interface AddIntent {
  name: 'AddItemIntent' | 'AddToListIntent';
  /** AddToListIntent's list slot as heard, kept through the dialog. */
  list?: string;
}

const addIntentOf = (envelope: Envelope): AddIntent => {
  const intent = envelope.request.intent;
  if (intent?.name !== 'AddToListIntent') return { name: 'AddItemIntent' };
  const list = intent.slots?.list?.value;
  return list ? { name: intent.name, list } : { name: intent.name };
};

/** Amazon forbids one slot name with two types, so AddToListIntent's phrase is `itemphrase`. */
const itemsSlotName = (intentName: string | undefined) =>
  intentName === 'AddToListIntent' ? 'itemphrase' : 'items';

const itemsSlotOf = (
  intent: { name?: string; slots?: Record<string, { value?: string } | undefined> } | undefined,
) => intent?.slots?.[itemsSlotName(intent?.name)];

/** The intent a dialog directive updates: the items slot as given, the list slot kept. */
const updatedIntent = ({ name, list }: AddIntent, items: string | undefined) => {
  const slotName = itemsSlotName(name);
  return {
    name,
    confirmationStatus: 'NONE',
    slots: {
      [slotName]: {
        name: slotName,
        ...(items !== undefined && { value: items }),
        confirmationStatus: 'NONE',
      },
      ...(name === 'AddToListIntent' && {
        list: { name: 'list', ...(list && { value: list }), confirmationStatus: 'NONE' },
      }),
    },
  };
};

/** `invalid_token:expired`, `user_deleted`: closed words, never the token or the message. */
const linkReason = (e: AuthError) => e.detail ? `${e.reason}:${e.detail}` : e.reason;

function alexaResponse(reply: Reply): Response {
  const response: Record<string, unknown> = {};
  if (reply.speech) response.outputSpeech = { type: 'PlainText', text: clip(reply.speech) };
  if (reply.reprompt) {
    response.reprompt = { outputSpeech: { type: 'PlainText', text: reply.reprompt } };
  }
  if (reply.card === 'link') response.card = { type: 'LinkAccount' };
  else if (reply.card) {
    response.card = { type: 'Simple', title: speech.cardTitle, content: clip(reply.card) };
  }
  const intent = reply.intent ?? { name: 'AddItemIntent' };
  if (reply.elicit) {
    response.directives = [{
      type: 'Dialog.ElicitSlot',
      slotToElicit: itemsSlotName(intent.name),
      updatedIntent: updatedIntent(intent, undefined),
    }];
  }
  if (reply.confirm) {
    response.directives = [{
      type: 'Dialog.ConfirmIntent',
      updatedIntent: updatedIntent(intent, reply.confirm),
    }];
  }
  response.shouldEndSession = reply.end;
  return json({ version: '1.0', sessionAttributes: reply.attributes ?? {}, response });
}

/** The answer to requests Alexa wants no speech for (SessionEnded, skill events). */
const empty = () => json({ version: '1.0', response: {} });

const accessTokenOf = (envelope: Envelope) =>
  envelope.context?.System?.user?.accessToken ?? envelope.session?.user?.accessToken;

const alexaUserOf = (envelope: Envelope) =>
  envelope.context?.System?.user?.userId ?? envelope.session?.user?.userId;

/** One token of the line: never spaces or free text, whatever Alexa sent. */
const word = (value: string | undefined) =>
  value ? value.replace(/[^\w.:-]/g, '_').slice(0, 64) : '-';

/** Facts about how the request went that Alexa's own logs don't show (job 170). */
export interface RequestFacts {
  ms?: number;
  /** Why the verifier refused it (VerificationError.reason), or a linked token is no link. */
  reason?: string;
}

/**
 * `alexa: <type> <intent|-> <locale|-> linked=<bool> -> <kind> [reason] rid=… slot=… confirm=… ended=…
 * error=… ms=…`, the only line a request logs (docs/ALEXA.md, "Request log"). `rid` is the end of
 * Alexa's request id, to find the request in the console's device log; `slot` counts the words
 * heard for the items, never the words. Tokens, user ids, slot values and addresses never go in.
 */
export function requestLine(
  envelope: Envelope | undefined,
  kind: ReplyKind,
  facts: RequestFacts = {},
): string {
  const request = envelope?.request;
  const linked = Boolean(envelope && (accessTokenOf(envelope) ?? request?.body?.accessToken));
  const slot = itemsSlotOf(request?.intent);
  const words = slot?.value?.trim() ? slot.value.trim().split(/\s+/).length : 0;
  const details = [
    `rid=${word(request?.requestId?.split('.').at(-1)?.slice(-12))}`,
    `slot=${slot ? words : '-'}`,
    `confirm=${word(request?.intent?.confirmationStatus)}`,
    `ended=${word(request?.reason)}`,
    `error=${word(request?.error?.type)}`,
    `ms=${facts.ms ?? '-'}`,
  ];
  return `alexa: ${word(request?.type)} ${word(request?.intent?.name)} ${
    word(request?.locale)
  } linked=${linked} -> ${kind}${facts.reason ? ` ${word(facts.reason)}` : ''} ${
    details.join(' ')
  }`;
}

export function createHandler(deps: Deps) {
  /** The linked account, or the reply to give instead (link card, no household, error). */
  async function linkedOrReply(envelope: Envelope): Promise<Linked | Reply> {
    const { speech } = speechFor(envelope.request.locale);
    const token = accessTokenOf(envelope);
    if (!token) return { speech: speech.linkAccount, card: 'link', end: true, kind: 'link' };
    let linked: Linked;
    try {
      linked = await deps.authenticate(token);
    } catch (e) {
      if (e instanceof AuthError) {
        if (e.reason === 'no_household') {
          return { speech: speech.noHousehold, end: true, kind: 'no-household' };
        }
        // Revoked in the app, the account deleted, signed out everywhere, or expired: unlinked.
        return {
          speech: speech.linkAccount,
          card: 'link',
          end: true,
          kind: 'link',
          reason: linkReason(e),
        };
      }
      deps.report(e);
      return { speech: speech.failed, end: true, kind: 'error' };
    }
    const alexaUser = alexaUserOf(envelope);
    if (alexaUser) {
      await deps.remember(alexaUser, linked, false).catch((e) => deps.report(e));
    }
    return linked;
  }

  const isReply = (x: Linked | Reply): x is Reply => 'end' in x;

  /** One more try at most, then "nicht verstanden"; never a guess (AC4). */
  function notUnderstood(envelope: Envelope): Reply {
    const { speech } = speechFor(envelope.request.locale);
    return envelope.session?.attributes?.retry
      ? { speech: speech.notUnderstood, end: true, kind: 'not-understood' }
      : {
        speech: speech.notUnderstoodOnce,
        reprompt: speech.notUnderstoodReprompt,
        elicit: true,
        intent: addIntentOf(envelope),
        end: false,
        kind: 'reprompt',
        attributes: { retry: 1 },
      };
  }

  async function addItems(envelope: Envelope): Promise<Reply> {
    const voice = speechFor(envelope.request.locale);
    const { speech } = voice;
    const text = itemsSlotOf(envelope.request.intent)?.value?.trim() ?? '';
    if (text.length > maxTextLength) return { speech: speech.tooLong, end: true, kind: 'too-long' };
    const heard = text ? voice.parse(text, maxItems + 1) : [];
    if (heard.length === 0) {
      // Not even linked: ask to link instead of asking again.
      if (!accessTokenOf(envelope)) {
        return { speech: speech.linkAccount, card: 'link', end: true, kind: 'link' };
      }
      return notUnderstood(envelope);
    }
    const linked = await linkedOrReply(envelope);
    if (isReply(linked)) return linked;
    const intent = addIntentOf(envelope);
    // Q79: the yes or no to a question about held items; NONE on a first add.
    const answer = envelope.request.intent?.confirmationStatus;
    let catalog: ListCatalog;
    try {
      catalog = await deps.lists(linked);
    } catch (e) {
      deps.report(e);
      return { speech: speech.failed, end: true, kind: 'error' };
    }
    // Alexa may hear the list inside the items ("luftballons zur geburtstag liste"); the list slot
    // wins, and the yes or no to Q79 stays on the list the question was about.
    const phrase = takeListPhrase(text, voice.lang, catalog.lists);
    const asked = envelope.session?.attributes?.list;
    const wish: ListWish =
      typeof asked === 'string' && (answer === 'CONFIRMED' || answer === 'DENIED')
        ? { by: 'id', id: asked }
        : intent.list?.trim()
        ? { by: 'name', said: intent.list }
        : phrase.said
        ? { by: 'name', said: phrase.said }
        : { by: 'none' };
    const target = targetOf(catalog, wish);
    const rest = voice.parse(phrase.text, maxItems + 1);
    if (rest.length === 0) return notUnderstood(envelope);
    const items = rest.slice(0, maxItems).map((item) => ({
      ...item,
      name: voice.name(item.name, phrase.text),
    }));
    const cut = rest.length > maxItems ? ` ${speech.tooMany}` : '';
    let added: Added[];
    try {
      if (!await deps.takeAdds(linked, items.length)) {
        return { speech: speech.rateLimited, end: true, kind: 'rate-limited' };
      }
      added = await deps.addItems(linked, items, {
        addVariants: answer === 'CONFIRMED',
        list: target.list.id,
      });
    } catch (e) {
      deps.report(e);
      return { speech: speech.failed, end: true, kind: 'error' };
    }
    await deps.counted(linked, added).catch((e) => deps.report(e));
    // The server's parser can still find no item in a piece ("1 Packung"): nothing to read back.
    if (added.length === 0) {
      return { speech: speech.notUnderstood, end: true, kind: 'not-understood' };
    }
    const ask = answer === 'NONE' || !answer ? voice.question(added, target) : null;
    if (ask) {
      const question = ask.question + cut;
      return {
        speech: question,
        reprompt: question,
        confirm: ask.again,
        intent,
        attributes: { list: target.list.id },
        end: false,
        kind: 'ask',
      };
    }
    const said = voice.confirmation(added, target) + cut;
    return { speech: said, card: said, end: true, kind: 'added' };
  }

  async function readList(envelope: Envelope): Promise<Reply> {
    const voice = speechFor(envelope.request.locale);
    const { speech } = voice;
    const linked = await linkedOrReply(envelope);
    if (isReply(linked)) return linked;
    try {
      const said = voice.listing(await deps.listItems(linked));
      return { speech: said, card: said, end: true, kind: 'read' };
    } catch (e) {
      deps.report(e);
      return { speech: speech.listFailed, end: true, kind: 'error' };
    }
  }

  async function launch(envelope: Envelope): Promise<Reply> {
    const { speech } = speechFor(envelope.request.locale);
    const linked = await linkedOrReply(envelope);
    if (isReply(linked)) return linked;
    return {
      speech: speech.launch,
      reprompt: speech.launchReprompt,
      elicit: true,
      end: false,
      kind: 'launch',
    };
  }

  async function intent(envelope: Envelope): Promise<Reply> {
    const { speech } = speechFor(envelope.request.locale);
    switch (envelope.request.intent?.name) {
      case 'AddItemIntent':
      case 'AddToListIntent':
        return await addItems(envelope);
      case 'ReadListIntent':
        return await readList(envelope);
      case 'AMAZON.HelpIntent':
        return { speech: speech.help, reprompt: speech.helpReprompt, end: false, kind: 'help' };
      case 'AMAZON.StopIntent':
      case 'AMAZON.CancelIntent':
      case 'AMAZON.NavigateHomeIntent':
        return { speech: speech.goodbye, end: true, kind: 'goodbye' };
      default:
        // AMAZON.FallbackIntent and anything this model does not know.
        return notUnderstood(envelope);
    }
  }

  /** Handles an Alexa skill event; returns why the token from a new link is no link. */
  async function skillEvent(envelope: Envelope): Promise<string | undefined> {
    const alexaUser = alexaUserOf(envelope);
    if (!alexaUser) return;
    if (envelope.request.type === 'AlexaSkillEvent.SkillDisabled') {
      await deps.revoke(alexaUser);
      return;
    }
    if (envelope.request.type === 'AlexaSkillEvent.SkillAccountLinked') {
      const token = envelope.request.body?.accessToken;
      if (typeof token !== 'string') return;
      try {
        await deps.remember(alexaUser, await deps.authenticate(token), true);
      } catch (e) {
        if (!(e instanceof AuthError)) throw e;
        return linkReason(e);
      }
    }
  }

  /** The answer to a verified request, its kind and the reason for the request line. */
  async function respond(envelope: Envelope): Promise<[Response, ReplyKind, string?]> {
    const type = envelope.request.type;
    if (type.startsWith('AlexaSkillEvent.')) {
      let reason: string | undefined;
      try {
        reason = await skillEvent(envelope);
      } catch (e) {
        deps.report(e);
        return [json({ error: 'server' }, { status: 500 }), 'error'];
      }
      return [empty(), 'empty', reason];
    }
    let reply: Reply;
    switch (type) {
      case 'LaunchRequest':
        reply = await launch(envelope);
        break;
      case 'IntentRequest':
        reply = await intent(envelope);
        break;
      default:
        // SessionEndedRequest, System.ExceptionEncountered and the rest want no speech.
        return [empty(), 'empty'];
    }
    return [alexaResponse(reply), reply.kind, reply.reason];
  }

  return async (req: Request): Promise<Response> => {
    const started = performance.now();
    const ms = () => Math.round(performance.now() - started);
    if (req.method !== 'POST') {
      deps.log(requestLine(undefined, 'refused', { ms: ms() }));
      return json({ error: 'method' }, { status: 405 });
    }
    const body = new Uint8Array(await req.arrayBuffer());
    let envelope: Envelope;
    try {
      envelope = await deps.verify(req.headers, body);
    } catch (e) {
      if (!(e instanceof VerificationError)) {
        deps.log(requestLine(undefined, 'error', { ms: ms() }));
        throw e;
      }
      deps.log(requestLine(undefined, 'refused', { ms: ms(), reason: e.reason }));
      return json({ error: e.reason }, { status: 400 });
    }
    let kind: ReplyKind = 'error';
    let reason: string | undefined;
    try {
      const [response, answered, why] = await respond(envelope);
      kind = answered;
      reason = why;
      return response;
    } finally {
      deps.log(requestLine(envelope, kind, reason ? { ms: ms(), reason } : { ms: ms() }));
    }
  };
}
