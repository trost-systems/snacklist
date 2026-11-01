// Demo videos on the landing page (landing.mjs renders them): the poster shows until a video plays.
// A video starts by itself only while at least half of it is in view and the visitor has not asked
// for reduced motion; it pauses out of view. The hex button plays and pauses it; a pause by hand
// sticks until the next play by hand. Without this file the videos keep the browser's controls.
const motionOk = matchMedia('(prefers-reduced-motion: no-preference)');

for (const demo of document.querySelectorAll('[data-demo]')) {
  const video = demo.querySelector('video');
  const button = demo.querySelector('.demo-toggle');
  let pausedByHand = false;

  video.removeAttribute('controls');
  button.hidden = false;

  // The poster picture stays on top until real frames play: `playing`, not `play`, which fires
  // before anything has loaded.
  video.addEventListener('playing', () => demo.classList.add('is-playing'));
  const label = () => {
    demo.classList.toggle('is-on', !video.paused);
    button.setAttribute('aria-label', video.paused ? button.dataset.play : button.dataset.pause);
  };
  video.addEventListener('play', label);
  video.addEventListener('pause', () => {
    demo.classList.remove('is-playing');
    label();
  });
  motionOk.addEventListener('change', () => {
    if (!motionOk.matches) video.pause();
  });

  button.addEventListener('click', () => {
    pausedByHand = !video.paused;
    if (video.paused) video.play().catch(() => {});
    else video.pause();
  });

  new IntersectionObserver(
    ([entry]) => {
      if (!entry.isIntersecting) video.pause();
      else if (motionOk.matches && !pausedByHand) video.play().catch(() => {});
    },
    { threshold: 0.5 },
  ).observe(demo);
}
