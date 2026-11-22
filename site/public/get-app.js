// The launch stage's store cards (landing.mjs): a phone sees only its own store's badge, a
// desktop both badges with their QR codes (rules in landing.css key on data-os).
// Without this file both badges show and no QR code.
const ua = navigator.userAgent;
const ipadAsMac = /Macintosh/.test(ua) && navigator.maxTouchPoints > 1;
document.documentElement.dataset.os = /iPhone|iPad|iPod/.test(ua) || ipadAsMac ? 'ios' : /Android/.test(ua) ? 'android' : 'desktop';
