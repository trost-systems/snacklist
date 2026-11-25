// A TCP proxy in front of the local database that holds every chunk for half a round trip in each
// direction, in order: the network between a hosted function and its database, which the local
// stack does not have. Statements sent together (pipelined) share the wait; each statement that
// waits for the one before pays it again.

/** Listens on a free port; returns it and a stop function. */
export function latencyProxy(
  target: { hostname: string; port: number },
  rttMs: number,
): { port: number; stop(): void } {
  const listener = Deno.listen({ hostname: '127.0.0.1', port: 0 });
  const half = rttMs / 2;
  const open = new Set<Deno.Conn>();

  async function pipe(from: Deno.Conn, to: Deno.Conn) {
    let last = Promise.resolve();
    const buffer = new Uint8Array(64 * 1024);
    try {
      for (;;) {
        const n = await from.read(buffer);
        if (n === null) break;
        const chunk = buffer.slice(0, n);
        const due = performance.now() + half;
        last = last.then(async () => {
          const wait = due - performance.now();
          if (wait > 0) await new Promise((r) => setTimeout(r, wait));
          let written = 0;
          while (written < chunk.length) written += await to.write(chunk.subarray(written));
        });
      }
      await last;
    } catch {
      // The other side went away.
    } finally {
      try {
        to.closeWrite();
      } catch {
        // Already closed.
      }
    }
  }

  (async () => {
    for await (const client of listener) {
      const server = await Deno.connect(target);
      open.add(client);
      open.add(server);
      Promise.all([pipe(client, server), pipe(server, client)]).finally(() => {
        for (const c of [client, server]) {
          open.delete(c);
          try {
            c.close();
          } catch {
            // Already closed.
          }
        }
      });
    }
  })().catch(() => {});

  return {
    port: (listener.addr as Deno.NetAddr).port,
    stop() {
      listener.close();
      for (const c of open) {
        try {
          c.close();
        } catch {
          // Already closed.
        }
      }
    },
  };
}
