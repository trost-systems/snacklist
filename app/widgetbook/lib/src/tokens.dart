import 'package:family_groceries/core/theme.dart';
import 'package:family_groceries/design/hex_border.dart';
import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/tactile.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:material_ui/material_ui.dart';
import 'package:snacklist_widgetbook/src/story.dart';

const _path = 'Tokens';

typedef ColorToken = ({String name, Color Function(SnacklistColors) of});

/// Every colour token by its name in `design/tokens/snacklist.tokens.json`
/// (the catalogue's test holds the two in step).
const List<ColorToken> colorTokens = [
  (name: 'brand', of: _brand),
  (name: 'on-brand', of: _onBrand),
  (name: 'honey', of: _honey),
  (name: 'on-honey', of: _onHoney),
  (name: 'honey-soft', of: _honeySoft),
  (name: 'accent', of: _accent),
  (name: 'on-accent', of: _onAccent),
  (name: 'accent-soft', of: _accentSoft),
  (name: 'surface', of: _surface),
  (name: 'surface-raised', of: _surfaceRaised),
  (name: 'surface-sunken', of: _surfaceSunken),
  (name: 'text', of: _text),
  (name: 'text-muted', of: _textMuted),
  (name: 'border', of: _border),
  (name: 'divider', of: _divider),
  (name: 'ink', of: _ink),
  (name: 'success', of: _success),
  (name: 'on-success', of: _onSuccess),
  (name: 'success-soft', of: _successSoft),
  (name: 'warning', of: _warning),
  (name: 'on-warning', of: _onWarning),
  (name: 'error', of: _error),
  (name: 'on-error', of: _onError),
  (name: 'edge', of: _edge),
  (name: 'honey-edge', of: _honeyEdge),
  (name: 'surface-edge', of: _surfaceEdge),
  (name: 'mint', of: _mint),
  (name: 'on-mint', of: _onMint),
  (name: 'mint-soft', of: _mintSoft),
  (name: 'mint-edge', of: _mintEdge),
  (name: 'cobalt', of: _cobalt),
  (name: 'on-cobalt', of: _onCobalt),
  (name: 'on-accent-soft', of: _onAccentSoft),
  (name: 'tomato', of: _tomato),
  (name: 'on-tomato', of: _onTomato),
  (name: 'tomato-edge', of: _tomatoEdge),
  (name: 'inverse', of: _inverse),
  (name: 'on-inverse', of: _onInverse),
];

Color _brand(SnacklistColors t) => t.brand;
Color _onBrand(SnacklistColors t) => t.onBrand;
Color _honey(SnacklistColors t) => t.honey;
Color _onHoney(SnacklistColors t) => t.onHoney;
Color _honeySoft(SnacklistColors t) => t.honeySoft;
Color _accent(SnacklistColors t) => t.accent;
Color _onAccent(SnacklistColors t) => t.onAccent;
Color _accentSoft(SnacklistColors t) => t.accentSoft;
Color _surface(SnacklistColors t) => t.surface;
Color _surfaceRaised(SnacklistColors t) => t.surfaceRaised;
Color _surfaceSunken(SnacklistColors t) => t.surfaceSunken;
Color _text(SnacklistColors t) => t.text;
Color _textMuted(SnacklistColors t) => t.textMuted;
Color _border(SnacklistColors t) => t.border;
Color _divider(SnacklistColors t) => t.divider;
Color _ink(SnacklistColors t) => t.ink;
Color _success(SnacklistColors t) => t.success;
Color _onSuccess(SnacklistColors t) => t.onSuccess;
Color _successSoft(SnacklistColors t) => t.successSoft;
Color _warning(SnacklistColors t) => t.warning;
Color _onWarning(SnacklistColors t) => t.onWarning;
Color _error(SnacklistColors t) => t.error;
Color _onError(SnacklistColors t) => t.onError;
Color _edge(SnacklistColors t) => t.edge;
Color _honeyEdge(SnacklistColors t) => t.honeyEdge;
Color _surfaceEdge(SnacklistColors t) => t.surfaceEdge;
Color _mint(SnacklistColors t) => t.mint;
Color _onMint(SnacklistColors t) => t.onMint;
Color _mintSoft(SnacklistColors t) => t.mintSoft;
Color _mintEdge(SnacklistColors t) => t.mintEdge;
Color _cobalt(SnacklistColors t) => t.cobalt;
Color _onCobalt(SnacklistColors t) => t.onCobalt;
Color _onAccentSoft(SnacklistColors t) => t.onAccentSoft;
Color _tomato(SnacklistColors t) => t.tomato;
Color _onTomato(SnacklistColors t) => t.onTomato;
Color _tomatoEdge(SnacklistColors t) => t.tomatoEdge;
Color _inverse(SnacklistColors t) => t.inverse;
Color _onInverse(SnacklistColors t) => t.onInverse;

/// A pair the design puts together, the contrast it needs, and the mode
/// it is used in (null: both).
typedef ContrastPair = ({String fg, String bg, double min, Brightness? only});

/// The token file's `contrastPairs` (the catalogue's test holds the two in
/// step).
const List<ContrastPair> contrastPairs = [
  (fg: 'on-honey', bg: 'honey', min: 4.5, only: null),
  (fg: 'text', bg: 'honey-soft', min: 4.5, only: null),
  (fg: 'text', bg: 'accent-soft', min: 4.5, only: null),
  (fg: 'text', bg: 'success-soft', min: 4.5, only: null),
  (fg: 'text', bg: 'surface-sunken', min: 4.5, only: null),
  (fg: 'text-muted', bg: 'surface-sunken', min: 4.5, only: null),
  (fg: 'brand', bg: 'surface-raised', min: 4.5, only: null),
  (fg: 'brand', bg: 'honey-soft', min: 4.5, only: null),
  (fg: 'accent', bg: 'surface', min: 4.5, only: null),
  (fg: 'accent', bg: 'surface-raised', min: 4.5, only: null),
  (fg: 'success', bg: 'surface-raised', min: 3, only: null),
  (fg: 'border', bg: 'surface', min: 3, only: null),
  (fg: 'border', bg: 'surface-raised', min: 3, only: null),
  (fg: 'on-mint', bg: 'mint', min: 4.5, only: null),
  (fg: 'text', bg: 'mint-soft', min: 4.5, only: null),
  (fg: 'on-cobalt', bg: 'cobalt', min: 4.5, only: null),
  (fg: 'on-tomato', bg: 'tomato', min: 4.5, only: null),
  (fg: 'on-accent-soft', bg: 'accent-soft', min: 4.5, only: null),
  (fg: 'on-inverse', bg: 'inverse', min: 4.5, only: null),
  (fg: 'text-muted', bg: 'accent-soft', min: 4.5, only: null),
  (fg: 'honey', bg: 'cobalt', min: 3, only: null),
  (fg: 'ink', bg: 'on-cobalt', min: 4.5, only: null),
  (fg: 'ink', bg: 'honey', min: 3, only: null),
  (fg: 'ink', bg: 'tomato', min: 3, only: null),
  (fg: 'ink', bg: 'mint', min: 3, only: null),
  (fg: 'accent', bg: 'accent-soft', min: 3, only: null),
  (fg: 'honey', bg: 'inverse', min: 3, only: null),
  (fg: 'text-muted', bg: 'honey', min: 4.5, only: Brightness.light),
  (fg: 'brand', bg: 'honey', min: 4.5, only: Brightness.light),
  (fg: 'honey', bg: 'surface', min: 3, only: Brightness.dark),
  (fg: 'honey', bg: 'surface-raised', min: 3, only: Brightness.dark),
  (fg: 'honey-edge', bg: 'surface', min: 3, only: Brightness.dark),
  (fg: 'edge', bg: 'honey', min: 3, only: null),
  (fg: 'on-honey', bg: 'honey-soft', min: 4.5, only: Brightness.light),
];

Color tokenColor(String name, Brightness brightness) => colorTokens
    .firstWhere((t) => t.name == name)
    .of(SnacklistColors.of(brightness));

String hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// The design tokens as pages: colours, type, radii, depth and motion.
final tokenComponents = [
  component(_path, 'Farben', [
    plain('Palette', (context) => const _Palette()),
    plain('Kontrastpaare', (context) => const _Pairs()),
  ]),
  component(_path, 'Schrift', [
    plain('Typo-Skala', (context) => const _TypeRamp()),
  ]),
  component(_path, 'Form', [
    plain('Radien', (context) => const _Radii()),
    plain('Tiefe', (context) => const _Depth()),
  ]),
  component(_path, 'Bewegung', [plain('Kurven', (context) => const _Curves())]),
];

TextStyle? _caption(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

/// Lays a token page out in a scrollable column a little narrower than a
/// laptop screen.
class const _Page({required final List<Widget> children})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 1400),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: HlSpace.s4,
        children: children,
      ),
    ),
  );
}

class const _Palette() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => _Page(
    children: [
      Wrap(
        spacing: HlSpace.s3,
        runSpacing: HlSpace.s3,
        children: [for (final token in colorTokens) _Swatch(token)],
      ),
    ],
  );
}

/// One token, light half over dark half, each with its hex.
class const _Swatch(final ColorToken token) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget half(Brightness brightness) {
      final color = token.of(SnacklistColors.of(brightness));
      final ink = color.computeLuminance() > 0.4
          ? SnacklistColors.light.ink
          : SnacklistColors.dark.text;
      return Container(
        height: 44,
        color: color,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: HlSpace.s3),
        child: Text(
          '${brightness == Brightness.light ? 'hell' : 'dunkel'} ${hex(color)}',
          style: TextStyle(
            fontFamily: HlFont.sans,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
      );
    }

    return Container(
      width: 200,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(HlRadius.s),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          half(Brightness.light),
          half(Brightness.dark),
          Padding(
            padding: const EdgeInsets.all(HlSpace.s2),
            child: Text(
              token.name,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class const _Pairs() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => _Page(
    children: [
      Text(
        'Vordergrund auf Grund, gemessen nach WCAG; das Minimum steht im '
        'Token-File.',
        style: _caption(context),
      ),
      Wrap(
        spacing: HlSpace.s3,
        runSpacing: HlSpace.s3,
        children: [
          for (final pair in contrastPairs)
            for (final brightness in const [Brightness.light, Brightness.dark])
              if (pair.only == null || pair.only == brightness)
                _PairCard(pair, brightness),
        ],
      ),
    ],
  );
}

class const _PairCard(final ContrastPair pair, final Brightness brightness)
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final fg = tokenColor(pair.fg, brightness);
    final bg = tokenColor(pair.bg, brightness);
    final ratio = contrastRatio(fg, bg);
    final ok = ratio >= pair.min;
    final mode = brightness == Brightness.light ? 'hell' : 'dunkel';
    return Container(
      width: 252,
      padding: const EdgeInsets.all(HlSpace.s3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(HlRadius.s),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: DefaultTextStyle(
        style: TextStyle(fontFamily: HlFont.sans, fontSize: 13, color: fg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: HlSpace.s1,
          children: [
            Text(
              'Aa ${ratio.toStringAsFixed(2)} : 1',
              style: const TextStyle(
                fontFamily: HlFont.display,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text('${pair.fg} auf ${pair.bg}'),
            Text(
              '$mode · ${hex(fg)} / ${hex(bg)} · '
              '${ok ? '≥' : 'VERFEHLT'} ${pair.min}',
            ),
          ],
        ),
      ),
    );
  }
}

class const _TypeRamp() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme.onSurface;
    final tokens = <(String, TextStyle)>[
      ('display', HlType.display),
      ('headline-l', HlType.headlineL),
      ('headline', HlType.headline),
      ('title', HlType.title),
      ('body-l', HlType.bodyL),
      ('body', HlType.body),
      ('label', HlType.label),
      ('caption', HlType.caption),
    ];
    final roles = <(String, TextStyle?)>[
      ('headlineMedium', text.headlineMedium),
      ('titleLarge', text.titleLarge),
      ('titleMedium', text.titleMedium),
      ('bodyLarge', text.bodyLarge),
      ('bodyMedium', text.bodyMedium),
      ('labelLarge', text.labelLarge),
      ('labelSmall', text.labelSmall),
    ];
    Widget row(String name, TextStyle? style, String sample) => Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(
          width: 220,
          child: Text(
            '$name · ${style?.fontFamily} ${style?.fontSize?.round()}',
            style: _caption(context),
          ),
        ),
        Expanded(
          child: Text(
            sample,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style?.copyWith(color: color),
          ),
        ),
      ],
    );
    return _Page(
      children: [
        Text('Tokens (HlType)', style: text.titleMedium),
        for (final (name, style) in tokens)
          row(
            name,
            style,
            name == 'caption' ? 'LIDL · 3 EINTRÄGE' : 'Snacklist',
          ),
        const SizedBox(height: HlSpace.s4),
        Text('Material-Rollen im App-Theme', style: text.titleMedium),
        for (final (name, style) in roles)
          row(name, style, 'Bananen, 6× für Lea'),
      ],
    );
  }
}

class const _Radii() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: HlSpace.s5,
      runSpacing: HlSpace.s5,
      children: [
        for (final (name, radius) in const [
          ('s', HlRadius.s),
          ('m', HlRadius.m),
          ('l', HlRadius.l),
          ('xl', HlRadius.xl),
        ])
          Column(
            spacing: HlSpace.s2,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: scheme.outline,
                    width: HlBorder.width,
                  ),
                ),
              ),
              Text('$name · ${radius.round()} px', style: _caption(context)),
            ],
          ),
      ],
    );
  }
}

/// The tactile face standing still in each state: the edge it rests on,
/// the lift on hover and the press that sinks it flush.
class const _Depth() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final colors = TactileColors(
      face: t.honey,
      contour: t.edge,
      edge: t.edge,
      focus: t.brand,
    );
    return Wrap(
      spacing: HlSpace.s6,
      runSpacing: HlSpace.s5,
      children: [
        for (final (name, states) in const [
          ('Ruhe · Kante ${HlDepth.edge} px', <WidgetState>{}),
          ('Hover · hebt ${HlDepth.lift} px', {WidgetState.hovered}),
          ('Gedrückt · sinkt ${HlDepth.press} px', {WidgetState.pressed}),
        ])
          Column(
            spacing: HlSpace.s3,
            children: [
              SizedBox(
                width: 160,
                height: HlSize.target + HlDepth.edge,
                child: TactileFace(
                  states: states,
                  colors: colors,
                  child: const SizedBox.expand(),
                ),
              ),
              Text(name, style: _caption(context)),
            ],
          ),
      ],
    );
  }
}

typedef _Easing = ({String name, Curve curve, Duration duration});

const List<_Easing> _easings = [
  (name: 'press', curve: HlEasing.press, duration: HlDuration.press),
  (name: 'bounce', curve: HlEasing.bounce, duration: HlDuration.release),
  (name: 'standard', curve: HlEasing.standard, duration: HlDuration.medium),
  (name: 'exit', curve: HlEasing.exit, duration: HlDuration.short),
];

/// Each easing token drawn as a curve, and a hex that runs it on
/// "Abspielen", at the token's duration (the Time Dilation addon slows it
/// down). With reduced motion it jumps, as the app's animations do.
class const _Curves() extends StatefulWidget {
  @override
  State<_Curves> createState() => _CurvesState();
}

class _CurvesState() extends State<_Curves> with TickerProviderStateMixin {
  late final _runs = [
    for (final _ in _easings) AnimationController(vsync: this),
  ];

  @override
  void dispose() {
    for (final run in _runs) {
      run.dispose();
    }
    super.dispose();
  }

  void _play() {
    for (final (i, easing) in _easings.indexed) {
      final run = _runs[i];
      final at = run.value < 0.5 ? 1.0 : 0.0;
      final duration = hlMotion(context, easing.duration);
      if (duration == Duration.zero) {
        run.value = at;
        continue;
      }
      run.animateTo(at, duration: duration, curve: easing.curve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: HlSpace.s4,
      children: [
        FilledButton.icon(
          onPressed: _play,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Abspielen'),
        ),
        for (final (i, easing) in _easings.indexed)
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: HlSpace.s4,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: CustomPaint(
                  painter: _CurvePainter(easing.curve, scheme.primary),
                ),
              ),
              SizedBox(
                width: 150,
                child: Text(
                  '${easing.name} · ${easing.duration.inMilliseconds} ms',
                  style: _caption(context),
                ),
              ),
              SizedBox(
                width: 300,
                height: 32,
                child: AnimatedBuilder(
                  animation: _runs[i],
                  builder: (context, child) => Align(
                    alignment: Alignment(_runs[i].value * 2 - 1, 0),
                    child: child,
                  ),
                  child: Container(
                    width: 40,
                    height: 28,
                    decoration: ShapeDecoration(
                      color: scheme.secondary,
                      shape: _hex(scheme.outline),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

ShapeBorder _hex(Color contour) => HexBorder(
  side: BorderSide(color: contour, width: HlBorder.width),
);

class _CurvePainter(final Curve curve, final Color color)
    extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // The bounce overshoots past 1: the box leaves room above and below.
    final path = Path();
    for (var i = 0; i <= 40; i++) {
      final t = i / 40;
      final point = Offset(
        t * size.width,
        size.height * (0.8 - 0.6 * curve.transform(t)),
      );
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter oldDelegate) =>
      oldDelegate.curve != curve || oldDelegate.color != color;
}
