# Verification roadmap: the testing spectrum

Saved Nov 15 2026 at Peter's request, to revisit when improving Snacklist's
verification pipeline, even if a local machine is wiped.

Source: <https://www.youtube.com/watch?v=O_zcc6Xl12g> (a talk's testing-spectrum
slide, typed out here as text; the video frame is third-party and is not in the repo).

The spectrum runs left to right: Pre-production, Deploy, Release, Post release.

## Revisit at the end of December 2026

1. Map each item below to what Snacklist already does (CI, `ci-ok`, goldens,
   PostHog flags, pgTAP, e2e, and so on) and fill in "Today at Snacklist".
2. Mark the gaps.
3. Pick the top 3 gaps by risk to beta and launch.

This is not scheduled work yet, and the "Today at Snacklist" column is
deliberately empty: no current-state audit has been done.

## Pre-production

| Item | Today at Snacklist |
| --- | --- |
| unit | TODO |
| functional | TODO |
| component | TODO |
| fuzz | TODO |
| property-based | TODO |
| formal verification | TODO |
| static analysis | TODO |
| mutation | TODO |
| coverage | TODO |
| benchmark | TODO |
| contract | TODO |
| lint | TODO |
| acceptance | TODO |
| regression | TODO |
| smoke | TODO |
| usability | TODO |
| UI/UX | TODO |
| penetration | TODO |
| threat modeling | TODO |
| performance | TODO |

## Deploy

| Item | Today at Snacklist |
| --- | --- |
| integration | TODO |
| tap compare | TODO |
| load | TODO |
| shadowing | TODO |
| config | TODO |
| soak | TODO |

## Release

| Item | Today at Snacklist |
| --- | --- |
| canarying | TODO |
| monitoring | TODO |
| traffic shaping | TODO |
| feature flagging | TODO |
| exception tracking | TODO |

## Post release

| Item | Today at Snacklist |
| --- | --- |
| teeing | TODO |
| profiling | TODO |
| logs/events | TODO |
| chaos testing | TODO |
| monitoring | TODO |
| A/B tests | TODO |
| tracing | TODO |
| dynamic exploration | TODO |
| real user monitoring | TODO |
| auditing | TODO |
| on-call experience | TODO |
