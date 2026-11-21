/** Milliseconds since the epoch. */
export type Ms = number;

export const SECOND = 1000;
export const MINUTE = 60 * SECOND;
export const HOUR = 60 * MINUTE;
export const DAY = 24 * HOUR;

/** Where a tick came from: the app, Siri or Alexa, or an MCP or API client. */
export type Source = 'app' | 'voice' | 'agent';

/** What the person was really doing when they ticked (generator truth, never seen by detectors). */
export type Context =
  | 'walk' // ticking each item as it goes into the cart
  | 'checkout' // ticking everything at the checkout or in the car
  | 'home-after' // catching up at home after the shop
  | 'home-before' // "we still have that": ticking at home, nothing was bought
  | 'delivery' // unpacking a delivery at home
  | 'voice'
  | 'accident'; // a stray tick, undone a few seconds later

/** One `item_events` row with action bought or restored, plus what job 352 would add to it. */
export interface Tick {
  readonly id: number;
  readonly item: string;
  /** `items.canonical_key`: what order and store memory key on. */
  readonly key: string;
  readonly actor: string;
  readonly source: Source;
  readonly kind: 'bought' | 'restored';
  /** The device's clock at the tap (`SetStatus.at`): today never sent to the server. */
  readonly clientAt: Ms;
  /** The commit time (`item_events.created_at`, `items.bought_at` today). */
  readonly serverAt: Ms;
  /** The item's store at the tick (proposed `item_events.store_id`); null for "No store". */
  readonly store: string | null;
  /** Open items of [store] left on the list after this tick (what the server can count). */
  readonly storeOpenAfter: number;
  readonly truth: { readonly visit: string | null; readonly context: Context };
}

export interface Store {
  readonly id: string;
  readonly pharmacy: boolean;
  /** The store's real walk position (0..1) of every key it sells. */
  readonly layout: ReadonlyMap<string, number>;
  /** The default order before any trip: categories in route order (as `walkingOrder` today). */
  readonly prior: ReadonlyMap<string, number>;
}

/** A real store visit (generator truth): who shopped, where, when. */
export interface Visit {
  readonly id: string;
  readonly store: string;
  readonly actors: readonly string[];
  readonly start: Ms;
  readonly end: Ms;
}

export interface Household {
  readonly name: string;
  readonly stores: readonly Store[];
  readonly ticks: readonly Tick[];
  readonly visits: readonly Visit[];
  /** Keys bought at each store, for scoring order on what the household buys. */
  readonly bought: ReadonlyMap<string, ReadonlySet<string>>;
}

/** A run of the walk: keys ticked within the clump window are tied (same shelf, or a batch). */
export interface Segment {
  readonly store: string;
  readonly at: Ms;
  readonly clumps: readonly (readonly string[])[];
}

/** A trip as history would show it. */
export interface Trip {
  readonly store: string | null;
  readonly actors: readonly string[];
  readonly start: Ms;
  readonly end: Ms;
  readonly ticks: readonly Tick[];
  /** Whether it came from a walk (teaches order) or only from a burst of catch-up ticks. */
  readonly walked: boolean;
}

export interface StoreMemoryWrite {
  readonly key: string;
  readonly store: string;
  readonly tick: Tick;
}

export interface Detection {
  readonly trips: readonly Trip[];
  /** What order learning reads, in time order. */
  readonly segments: readonly Segment[];
  readonly storeMemory: readonly StoreMemoryWrite[];
}

export type Detector = (household: Household) => Detection;

/** A store's learned order: key to position, smaller first. */
export type Order = ReadonlyMap<string, number>;

export interface Learner {
  readonly name: string;
  learn(stores: readonly Store[], segments: readonly Segment[]): ReadonlyMap<string, Order>;
}
