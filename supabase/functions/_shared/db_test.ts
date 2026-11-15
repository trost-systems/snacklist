import { assertEquals, assertRejects } from '@std/assert';
import { inTurn, OutOfTime } from './db.ts';

/** A piece of work that ends when the test says so, and notes when it began and ended. */
function held(log: string[], name: string) {
  let end = () => {};
  const ended = new Promise<void>((resolve) => {
    end = resolve;
  });
  const work = async () => {
    log.push(`${name} begins`);
    await ended;
    log.push(`${name} ends`);
    return name;
  };
  return { work, end };
}

/** Lets every promise that can settle now settle. */
const settled = () => new Promise<void>((resolve) => setTimeout(resolve, 0));

Deno.test("one caller's work runs one after another in the order it came, another caller's beside it", async () => {
  const log: string[] = [];
  const a1 = held(log, 'a1');
  const a2 = held(log, 'a2');
  const a3 = held(log, 'a3');
  const b1 = held(log, 'b1');
  const all = [
    inTurn('a', a1.work),
    inTurn('a', a2.work),
    inTurn('a', a3.work),
    inTurn('b', b1.work),
  ];
  await settled();
  assertEquals(log, ['a1 begins', 'b1 begins']);

  a2.end();
  a3.end();
  b1.end();
  await settled();
  assertEquals(log, ['a1 begins', 'b1 begins', 'b1 ends'], 'a2 and a3 wait for a1');

  a1.end();
  assertEquals(await Promise.all(all), ['a1', 'a2', 'a3', 'b1']);
  assertEquals(log.slice(3), ['a1 ends', 'a2 begins', 'a2 ends', 'a3 begins', 'a3 ends']);
});

Deno.test('work that waited its time gives up without running; what comes behind or after it still waits', async () => {
  const log: string[] = [];
  const first = held(log, 'first');
  const late = held(log, 'late');
  const behind = held(log, 'behind');
  const running = inTurn('a', first.work);
  const gaveUp = assertRejects(() => inTurn('a', late.work, 20), OutOfTime);
  const waiting = inTurn('a', behind.work);
  const lateAgain = assertRejects(() => inTurn('a', late.work, 20), OutOfTime);
  await gaveUp;
  await lateAgain;
  const after = held(log, 'after');
  const arrivedAfter = inTurn('a', after.work);
  await settled();
  assertEquals(log, ['first begins'], 'only the first ran');

  first.end();
  behind.end();
  after.end();
  assertEquals(await Promise.all([running, waiting, arrivedAfter]), ['first', 'behind', 'after']);
  assertEquals(log.slice(1), [
    'first ends',
    'behind begins',
    'behind ends',
    'after begins',
    'after ends',
  ]);
});

Deno.test('work that fails ends its turn; a caller with nothing running starts at once', async () => {
  const log: string[] = [];
  const failing = inTurn('a', () => Promise.reject(new Error('broke')));
  const after = held(log, 'after');
  const next = inTurn('a', after.work);
  await assertRejects(() => failing, Error, 'broke');
  after.end();
  assertEquals(await next, 'after');

  const again = held(log, 'again');
  const started = inTurn('a', again.work, 0);
  again.end();
  assertEquals(await started, 'again', 'no wait, so no time to run out of');
});
