// The five transition options (T1–T5), the "Today" baseline, and the comparison data.
// The motion itself lives in styles.css (.ob-stage[data-t="…"]); the numbers here must match it.

import type { StepNumber } from './onboardingSteps';

export type OptionId = 't1' | 't2' | 't3' | 't4' | 't5';
export type ModeId = OptionId | 'today';
export type Direction = 'fwd' | 'back';

/** One navigation request. `seq` makes every request unique, so Replay to the same step still runs. */
export interface NavEvent {
  seq: number;
  /** Step shown as the outgoing layer for a fresh run (Replay / Auto-Tour); null means "enter from nothing". */
  from: StepNumber | null;
  to: StepNumber;
  dir: Direction;
  /** Fresh runs discard the current layers and rebuild `from → to` from scratch. */
  fresh: boolean;
  /** Move focus to the new step's heading (in-phone navigation only). */
  focus: boolean;
}

export const REDUCED_MOTION_MS = 120;
export const TOUR_STEP_MS = 1100;

export type MetricKey =
  | 'duration'
  | 'curve'
  | 'barJump'
  | 'direction'
  | 'keyboard'
  | 'reduced'
  | 'flutter'
  | 'smoothness';

export const METRICS: readonly { key: MetricKey; label: string }[] = [
  { key: 'duration', label: 'Duration' },
  { key: 'curve', label: 'Curve / physics' },
  { key: 'barJump', label: 'Progress bar jump' },
  { key: 'direction', label: 'Direction cue' },
  { key: 'keyboard', label: 'Keyboard / text-step safety' },
  { key: 'reduced', label: 'Reduced-motion behavior' },
  { key: 'flutter', label: 'Flutter implementation' },
  { key: 'smoothness', label: 'Perceived smoothness' },
];

export interface ModeInfo {
  id: ModeId;
  code: string;
  name: string;
  pill: string;
  /** One-line motion spec shown under the switcher. */
  spec: string;
  next: string;
  back: string;
  /** Time after which the outgoing layer is gone (longest exit or entrance). */
  settleMs: number;
  metrics: Record<MetricKey, string>;
}

export const OPTION_IDS: readonly OptionId[] = ['t1', 't2', 't3', 't4', 't5'];

export const MODES: Record<ModeId, ModeInfo> = {
  t1: {
    id: 't1',
    code: 'T1',
    name: 'Shared-Axis Slide',
    pill: 'Slide',
    spec: '300 ms · cubic-bezier(0.2, 0, 0, 1) · ±28 px on X with fade-through sub-intervals (90 ms out, 210 ms in)',
    next: 'Next: old step slides 28 px left and fades, new step enters from 28 px right.',
    back: 'Back: mirrored, old step leaves right, previous step returns from the left.',
    settleMs: 300,
    metrics: {
      duration: '300 ms (fade out 90 ms, fade in 210 ms)',
      curve: 'cubic-bezier(0.2, 0, 0, 1) on the move; fades accelerate out, decelerate in',
      barJump: '0 px',
      direction: 'Strong. Next moves left, Back mirrors right',
      keyboard:
        'Medium. 28 px is short, but a step with an open keyboard slides sideways under it. Dismiss the keyboard on Continue.',
      reduced: '120 ms opacity dissolve, no travel',
      flutter:
        'PageTransitionSwitcher(reverse: isBack) + SharedAxisTransition(horizontal) below a fixed AppBar and progress bar',
      smoothness: 'Reads as turning a page. Sub-interval fades avoid double exposure; feels fastest of the five.',
    },
  },
  t2: {
    id: 't2',
    code: 'T2',
    name: 'Fade-Through Stage',
    pill: 'Fade',
    spec: '300 ms · out 90 ms cubic-bezier(0.3, 0, 1, 1) · in 210 ms cubic-bezier(0.05, 0.7, 0.1, 1) with scale 0.96 → 1',
    next: 'Next: old step fades out fast, new step fades in and settles from 0.96.',
    back: 'Back: same dissolve, previous step settles from 1.04 instead (zoom-out cue, still 0 px travel).',
    settleMs: 300,
    metrics: {
      duration: '300 ms (90 ms out, then 210 ms in)',
      curve: 'Out cubic-bezier(0.3, 0, 1, 1); in cubic-bezier(0.05, 0.7, 0.1, 1), scale 0.96 → 1',
      barJump: '0 px',
      direction: 'Weak. Next settles from 0.96, Back from 1.04; no travel',
      keyboard: 'High. Nothing moves along X or Y, so the keyboard and focused field never fight the motion.',
      reduced: 'Drops the scale, keeps a 120 ms dissolve (almost identical)',
      flutter: 'PageTransitionSwitcher + FadeThroughTransition (animations package)',
      smoothness: 'Calmest. The short blank beat between steps can read as a reload on very fast taps.',
    },
  },
  t3: {
    id: 't3',
    code: 'T3',
    name: 'Morphing Card Container',
    pill: 'Morph',
    spec: '340 ms height · cubic-bezier(0.05, 0.7, 0.1, 1) · inner cross-fade 200 ms with 12 px drift',
    next: 'Next: the one card resizes to the new step while content cross-fades, drifting 12 px left.',
    back: 'Back: same resize, content drifts 12 px right.',
    settleMs: 340,
    metrics: {
      duration: '340 ms height, 200 ms content cross-fade',
      curve: 'Height cubic-bezier(0.05, 0.7, 0.1, 1); content fades with a 12 px mirrored drift',
      barJump: '0 px (the card’s bottom edge and CTA move with content height)',
      direction: 'Medium. Only the 12 px content drift carries direction; the card itself has none',
      keyboard:
        'Low. On Steps 3 and 5 the card height animates while the keyboard resizes the viewport; the two collide and the CTA moves.',
      reduced: 'Height snaps, content dissolves in 120 ms',
      flutter: 'AnimatedSize(340 ms, Easing.emphasizedDecelerate) around an AnimatedSwitcher; profile on Flutter Web',
      smoothness:
        'Most cohesive on chip steps (2, 4, 5): the card grows with the chips. Height is a layout animation, so watch low-end Android and Web.',
    },
  },
  t4: {
    id: 't4',
    code: 'T4',
    name: 'Vertical Stepper Stack',
    pill: 'Stack',
    spec: '280 ms · cubic-bezier(0.2, 0, 0, 1) · in +24 px on Y, out −16 px and dim',
    next: 'Next: new step rises 24 px from below, old step recedes 16 px up and dims.',
    back: 'Back: previous step drops in from 16 px above, current step sinks 24 px and dims.',
    settleMs: 280,
    metrics: {
      duration: '280 ms',
      curve: 'cubic-bezier(0.2, 0, 0, 1); in +24 px, out −16 px with opacity',
      barJump: '0 px',
      direction: 'Medium. Next rises, Back drops; less familiar than X for Back',
      keyboard: 'High. Motion runs along the keyboard’s own axis.',
      reduced: '120 ms dissolve, no vertical travel',
      flutter: 'PageTransitionSwitcher + SharedAxisTransition(vertical)',
      smoothness: 'Feels like “next question”. Tall chip steps can feel cramped mid-move.',
    },
  },
  t5: {
    id: 't5',
    code: 'T5',
    name: 'Tactile Spring Deck',
    pill: 'Spring',
    spec: '~360 ms · cubic-bezier(0.22, 1.18, 0.36, 1) light overshoot · old card 1 → 0.95, opacity 1 → 0.35',
    next: 'Next: new card springs up over the deck, old card shrinks to 0.95 and dims to 0.35.',
    back: 'Back: top card drops away, the previous card pops back from 0.95 / 0.35 to full.',
    settleMs: 360,
    metrics: {
      duration: '~360 ms in, 260 ms drop-away on Back',
      curve: 'cubic-bezier(0.22, 1.18, 0.36, 1), lightly damped overshoot; interruptible (retargets mid-flight)',
      barJump: '0 px',
      direction: 'Medium. Depth: Next stacks a card on top, Back lifts it off',
      keyboard: 'Medium-low. Overshoot next to a keyboard distracts; use 100% damping on text steps.',
      reduced: 'Removes scale and overshoot (z-axis motion is on Apple’s reduce list), 120 ms dissolve',
      flutter: 'AnimationController.animateWith(SpringSimulation), damping ≈ 0.9, response ≈ 0.38 s',
      smoothness: 'Most tactile. Bounce on the consent step (1) and account step (6) feels wrong.',
    },
  },
  today: {
    id: 'today',
    code: 'Today',
    name: 'Today (jumping bar)',
    pill: 'Today (Bug)',
    spec: 'No transition · progress bar + body inside a centered ListView(shrinkWrap: true) · full re-mount per step',
    next: 'Next: hard cut. Short steps re-center, so the progress bar jumps down.',
    back: 'Back: hard cut, the bar jumps again.',
    settleMs: 0,
    metrics: {
      duration: '0 ms (hard cut, whole screen re-mounts)',
      curve: 'None',
      barJump: '~140–210 px between steps on a full-height phone (live readout measures this frame)',
      direction: 'None',
      keyboard: 'Low. The column re-centers when the keyboard opens, so the field and bar move.',
      reduced: 'Same hard cut',
      flutter: 'Center(ListView(shrinkWrap: true, children: [progress, body])): the bug',
      smoothness: 'Nothing anchors the eye; the bar and title land somewhere new on every step.',
    },
  },
};
