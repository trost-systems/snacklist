#!/usr/bin/env python3
"""The A/B table of scripts/add-sheet-timing.sh: per APK (the label in <pass>-<label>.log) and
mode, the UI thread's time per key (the ranking plus the build of the key's frame) at p50, p95
and max, by typed length, and each pass's p50; then each label's [timing-cpu] lines."""
import collections
import re
import sys


def quantile(xs, q):
    xs = sorted(xs)
    return xs[round((len(xs) - 1) * q)] if xs else None


def stats(xs):
    xs = [x for x in xs if x is not None]
    return ' / '.join('-' if v is None else f'{v:.1f}'
                      for v in (quantile(xs, .5), quantile(xs, .95), max(xs) if xs else None))


def num(x):
    return None if x in ('null', '') else float(x)


rows = []
cpu = collections.defaultdict(list)
for path in sys.argv[1:]:
    m = re.search(r'(\d+)-([\w.-]+)\.log$', path)
    if not m:
        continue
    run, label = int(m[1]), m[2]
    for line in open(path, encoding='utf-8', errors='replace'):
        if '[timing-sample] ' in line:
            f = line.split('[timing-sample] ', 1)[1].strip().split(',')
            mode, gap, _line, length, log, rank, frame, build, raster, _skew = f[:10]
            answer = num(f[10]) if len(f) > 10 else None
            if answer is not None:
                rows.append(dict(label=label, run=run, mode=mode, len=-1, answer=answer))
            if num(build) is None:
                continue
            rows.append(dict(label=label, run=run, mode=mode, len=int(length),
                             rank=num(rank) or 0, build=num(build)))
        elif '[timing-cpu] ' in line:
            cpu[label].append(line.split('[timing-cpu] ', 1)[1].rstrip())

labels = sorted({r['label'] for r in rows}, key=lambda l: (l != 'base', l))
modes = ['off', 'stable', 'catalog']
runs = sorted({r['run'] for r in rows})
print('UI thread per key, ms (rank + build of its frame), each cell p50 / p95 / max')
print()
print("| apk | mode | keys | all | len 1 | len 2 | len 3+ | rank | build | pass p50s | the server's answer frame: build |")
print('|---|---|---|---|---|---|---|---|---|---|---|')
for label in labels:
    for mode in modes:
        answers = [r['answer'] for r in rows if r['label'] == label and r['mode'] == mode and r['len'] < 0]
        g = [r for r in rows if r['label'] == label and r['mode'] == mode and r['len'] >= 0]
        ui = lambda rs: [r['rank'] + r['build'] for r in rs]
        by_len = [ui([r for r in g if (r['len'] >= 3 if b == 3 else r['len'] == b)]) for b in (1, 2, 3)]
        passes = ', '.join(f"{quantile(ui([r for r in g if r['run'] == run]), .5):.1f}"
                           for run in runs if any(r['run'] == run for r in g))
        print(f"| {label} | {mode} | {len(g)} | {stats(ui(g))} | {' | '.join(stats(x) for x in by_len)} "
              f"| {stats(r['rank'] for r in g)} | {stats(r['build'] for r in g)} | {passes} "
              f"| {stats(answers)} ({len(answers)}) |")
for label in labels:
    print()
    print(f'CPU samples, {label}:')
    print('```')
    print('\n'.join(cpu[label]))
    print('```')
