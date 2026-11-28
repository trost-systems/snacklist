import { useId, useLayoutEffect, useRef, useState } from 'react';
import type { CSSProperties, KeyboardEvent, ReactNode } from 'react';
import { shapePath } from './shape';
import type { Box, Look, ShapeKind } from './shape';
import { OPTIONS } from './options';
import type { ControlKind, FocusLook, Layer, OptionId, Token } from './options';

const EDGE = 4;
const CONTOUR = 2;

const v = (t: Token) => `var(--hl-color-${t})`;

export interface PaintCtx {
  option: OptionId;
  look: Look;
}

interface PaintedProps {
  ctx: PaintCtx;
  kind: ControlKind;
  forcedFocus: boolean;
  honey?: boolean;
  face?: Token | null;
  contour?: Token | null;
  contourWidth?: number;
  edge?: Token | null;
  testId: string;
  className?: string;
  style?: CSSProperties;
  role?: string;
  ariaLabel?: string;
  ariaPressed?: boolean;
  onActivate?: () => void;
  children: ReactNode;
}

const PAD: Record<ControlKind, { t: number; b: number; x: number }> = {
  chip: { t: 0, b: 0, x: 21 },
  textButton: { t: 0, b: 0, x: 18 },
  button: { t: 8, b: 8, x: 18 },
  field: { t: 0, b: 0, x: 18 },
  row: { t: 6, b: 7, x: 16 },
};

function shapeKind(kind: ControlKind): ShapeKind {
  return kind === 'row' ? 'rect' : 'hex';
}

function thinnestBarMeetingWcagArea(kind: ShapeKind, look: Look, face: Box, inset: number): number {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  path.setAttribute('d', shapePath(kind, look, face));
  svg.appendChild(path);
  svg.style.position = 'absolute';
  svg.style.visibility = 'hidden';
  document.body.appendChild(svg);
  const perimeter = path.getTotalLength();
  svg.remove();
  const need = 2 * perimeter;
  const canvas = document.createElement('canvas');
  canvas.width = Math.ceil(face.w) + 2;
  canvas.height = Math.ceil(face.h) + 2;
  const g = canvas.getContext('2d', { willReadFrequently: true });
  if (!g) return 8;
  const inner = new Path2D(shapePath(kind, look, { x: 0, y: 0, w: face.w, h: face.h }, -inset));
  for (let t = 4; t <= 8; t++) {
    g.clearRect(0, 0, canvas.width, canvas.height);
    g.save();
    g.clip(inner);
    g.fillStyle = '#000';
    g.fillRect(0, face.h - inset - t, face.w, t);
    g.restore();
    const data = g.getImageData(0, 0, canvas.width, canvas.height).data;
    let area = 0;
    for (let i = 3; i < data.length; i += 4) area += (data[i] ?? 0) / 255;
    // 10 % over the rule: antialiased edges lose a little of the drawn area.
    if (area >= need * 1.1) return t;
  }
  return 8;
}

function LayerPath({ layer, kind, look, face, whole, id }: { layer: Layer; kind: ShapeKind; look: Look; face: Box; whole: Box; id: string }) {
  switch (layer.t) {
    case 'stroke':
      return (
        <path
          data-layer="focus"
          d={shapePath(kind, look, layer.includeEdge ? whole : face, layer.outset)}
          fill="none"
          stroke={v(layer.color)}
          strokeWidth={layer.width}
        />
      );
    case 'glow':
      return (
        <g data-layer="focus" clipPath={layer.outset < 0 ? `url(#${id}-inside)` : undefined}>
          <g filter={`url(#${id}-blur)`} opacity={layer.opacity}>
            <path d={shapePath(kind, look, layer.includeEdge ? whole : face, layer.outset)} fill="none" stroke={v(layer.color)} strokeWidth={layer.width} />
          </g>
        </g>
      );
    case 'overlay':
      return (
        <path
          data-layer="focus"
          d={shapePath(kind, look, face)}
          fill={layer.color === 'ink' ? 'var(--fh-ink)' : v(layer.color)}
          opacity={layer.opacity}
        />
      );
    case 'bar': {
      const t = layer.thickness || thinnestBarMeetingWcagArea(kind, look, face, layer.inset);
      return (
        <g data-layer="focus" data-bar={t} clipPath={`url(#${id}-clip)`}>
          <rect x={face.x} y={face.y + face.h - layer.inset - t} width={face.w} height={t} fill={v(layer.color)} />
        </g>
      );
    }
  }
}

export function Painted({
  ctx,
  kind,
  forcedFocus,
  honey = false,
  face = 'surface-raised',
  contour = 'border',
  contourWidth = CONTOUR,
  edge = null,
  testId,
  className,
  style,
  role,
  ariaLabel,
  ariaPressed,
  onActivate,
  children,
}: PaintedProps) {
  const ref = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState<{ w: number; h: number } | null>(null);
  const [keyFocus, setKeyFocus] = useState(false);
  const id = useId().replace(/[^a-zA-Z0-9-]/g, '');

  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const measure = () => setSize({ w: el.offsetWidth, h: el.offsetHeight });
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const on = forcedFocus || keyFocus;
  const sk = shapeKind(kind);
  const faced = face !== null && kind !== 'row';
  const look: FocusLook = on ? OPTIONS[ctx.option].focus({ kind, honey, faced, contour: contourWidth }) : { layers: [] };
  const depth = edge ? EDGE : 0;
  const faceBox: Box | null = size ? { x: 0, y: 0, w: size.w, h: size.h - depth } : null;
  const faceColor = look.face ?? face;
  const room = OPTIONS[ctx.option].room[kind];
  // Material's focus overlay is ink under the label; every other indicator paints on top, as a foreground painter.
  const under = look.layers.filter((l) => l.t === 'overlay');
  const over = look.layers.filter((l) => l.t !== 'overlay');

  const onKey = (e: KeyboardEvent<HTMLDivElement>) => {
    if (kind === 'field') return;
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      onActivate?.();
    }
  };

  return (
    <div
      ref={ref}
      className={`fh-ctl fh-ctl--${kind}${className ? ` ${className}` : ''}`}
      data-testid={testId}
      data-focused={on ? 'true' : 'false'}
      data-option={ctx.option}
      style={{ ...style, color: v(look.text ?? (honey ? 'on-honey' : kind === 'textButton' ? 'brand' : 'text')) }}
      tabIndex={kind === 'field' ? undefined : 0}
      role={role ?? (kind === 'field' ? undefined : 'button')}
      aria-label={ariaLabel}
      aria-pressed={ariaPressed}
      onClick={onActivate}
      onKeyDown={onKey}
      onFocus={(e) => setKeyFocus((e.target as HTMLElement).matches(':focus-visible') || kind === 'field')}
      onBlur={() => setKeyFocus(false)}
    >
      {faceBox && (
        <svg className="fh-paint" width={faceBox.w} height={faceBox.h + depth} aria-hidden="true">
          {edge && (
            <path
              d={shapePath(sk, ctx.look, { ...faceBox, y: depth }, -CONTOUR / 2)}
              fill={v(edge)}
              stroke={v(contour ?? edge)}
              strokeWidth={CONTOUR}
            />
          )}
          {faceColor && <path data-layer="face" d={shapePath(sk, ctx.look, faceBox)} fill={v(faceColor)} />}
          {contour && kind !== 'row' && (
            <path
              d={shapePath(sk, ctx.look, faceBox, -contourWidth / 2)}
              fill="none"
              stroke={v(look.contour ?? contour)}
              strokeWidth={contourWidth}
            />
          )}
          {under.map((layer, i) => (
            <LayerPath key={i} layer={layer} kind={sk} look={ctx.look} face={faceBox} whole={faceBox} id={id} />
          ))}
          <path data-layer="outline" d={shapePath(sk, ctx.look, faceBox)} fill="none" />
        </svg>
      )}
      <div
        className="fh-ctl-body"
        style={{
          paddingTop: PAD[kind].t + room.t,
          paddingBottom: PAD[kind].b + room.b + depth,
          paddingLeft: PAD[kind].x + room.x,
          paddingRight: PAD[kind].x + room.x,
        }}
      >
        {children}
      </div>
      {faceBox && over.length > 0 && (
        <svg className="fh-paint" width={faceBox.w} height={faceBox.h + depth} aria-hidden="true">
          <defs>
            <filter id={`${id}-blur`} x="-50%" y="-50%" width="200%" height="200%">
              <feGaussianBlur stdDeviation={3} />
            </filter>
            <clipPath id={`${id}-clip`}>
              <path d={shapePath(sk, ctx.look, faceBox, -(over.find((l) => l.t === 'bar')?.inset ?? 0))} />
            </clipPath>
            <clipPath id={`${id}-inside`}>
              <path d={shapePath(sk, ctx.look, faceBox)} />
            </clipPath>
          </defs>
          {over.map((layer, i) => (
            <LayerPath key={i} layer={layer} kind={sk} look={ctx.look} face={faceBox} whole={{ ...faceBox, h: faceBox.h + depth }} id={id} />
          ))}
        </svg>
      )}
    </div>
  );
}
