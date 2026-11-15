// In-page probes for verify.mjs: run in the page as window.__probe = (probes.toString())().
// Is a box visible on the phone: inside every clipping ancestor, not under the scrim (unless in the dock or a sheet),
// and, for list rows, above whatever the dock puts over the list.
export const probes = () => {
  const coverTop = (phone) => Math.min(...[...phone.querySelector('.dock').children].filter((c) => c.getBoundingClientRect().height).map((c) => c.getBoundingClientRect().top));
  const clips = (a) => {
    const cs = getComputedStyle(a);
    return cs.overflowX !== 'visible' || cs.overflowY !== 'visible';
  };
  // The part of the screen where `el`'s content can show: inside every clipping ancestor from `from` up to the phone;
  // list content also above the dock's cover and nowhere under a scrim.
  const clipBox = (el, phone, from = el.parentElement) => {
    const pr = phone.getBoundingClientRect();
    let { top, bottom, left, right } = pr;
    for (let a = from; a && a !== phone; a = a.parentElement) {
      if (!clips(a)) continue;
      const ar = a.getBoundingClientRect();
      top = Math.max(top, ar.top);
      bottom = Math.min(bottom, ar.bottom);
      left = Math.max(left, ar.left);
      right = Math.min(right, ar.right);
    }
    if (el.closest('.list')) {
      if (phone.querySelector('.scrim')) return null;
      bottom = Math.min(bottom, coverTop(phone));
    }
    return { top, bottom, left, right };
  };
  // The box of an element's own text (not its padding): the union of its direct text nodes' line boxes.
  const textRect = (el) => {
    const rs = [...el.childNodes].filter((n) => n.nodeType === 3 && n.textContent.trim()).flatMap((n) => {
      const range = document.createRange();
      range.selectNodeContents(n);
      return [...range.getClientRects()];
    });
    if (!rs.length) return el.getBoundingClientRect();
    return { top: Math.min(...rs.map((r) => r.top)), bottom: Math.max(...rs.map((r) => r.bottom)), left: Math.min(...rs.map((r) => r.left)), right: Math.max(...rs.map((r) => r.right)), get height() { return this.bottom - this.top; } };
  };
  const visibleRect = (el, phone, own = false) => {
    const r = own ? textRect(el) : el.getBoundingClientRect();
    const box = clipBox(el, phone, own ? el : el.parentElement);
    if (!box) return null;
    const top = Math.max(r.top, box.top), bottom = Math.min(r.bottom, box.bottom), left = Math.max(r.left, box.left), right = Math.min(r.right, box.right);
    return bottom - top > 2 && right - left > 2 ? { top, bottom, left, right, full: bottom - top >= r.height - 1 } : null;
  };
  // An element cut off with an ellipsis: its text is wider than its box.
  const ellipsized = (el) => {
    const cs = getComputedStyle(el);
    return cs.textOverflow === 'ellipsis' && cs.overflowX !== 'visible' && el.scrollWidth > el.clientWidth + 1;
  };
  // What of a text node a reader sees: each character inside every clip, not hidden behind an ellipsis.
  const seen = new Map();
  const visibleChars = (n, phone) => {
    if (seen.has(n)) return seen.get(n);
    const el = n.parentElement;
    const box = clipBox(el, phone, el);
    let cut = Infinity;
    for (let a = el; a && a !== phone; a = a.parentElement)
      if (ellipsized(a)) cut = Math.min(cut, a.getBoundingClientRect().right - parseFloat(getComputedStyle(a).paddingRight) - parseFloat(getComputedStyle(a).fontSize));
    const range = document.createRange();
    let out = '';
    const t = n.textContent;
    for (let i = 0; i < t.length; i++) {
      if (/\s/.test(t[i])) {
        out += ' ';
        continue;
      }
      range.setStart(n, i);
      range.setEnd(n, i + 1);
      const r = range.getBoundingClientRect();
      const inside = box && r.width > 0 && r.left >= box.left - 1 && r.right <= Math.min(box.right, cut) + 1 && Math.min(r.bottom, box.bottom) - Math.max(r.top, box.top) >= r.height * 0.6;
      out += inside ? t[i] : '\u0000';
    }
    seen.set(n, out);
    return out;
  };
  const visibleText = (root, phone) => {
    const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let out = '';
    for (let n = w.nextNode(); n; n = w.nextNode()) out += visibleChars(n, phone);
    return out.replace(/\s+/g, ' ');
  };
  // A unit names the item, its store and its section, in text a reader sees, within about three suggestion rows'
  // height (at the text size) beyond the name's own lines.
  const identify = (phone, { name, store, cat }) => {
    seen.clear();
    const ts = Number(getComputedStyle(phone).getPropertyValue('--ts')) || 1;
    let best = 'no';
    for (const el of phone.querySelectorAll('*')) {
      const own = [...el.childNodes].filter((n) => n.nodeType === 3).map((n) => visibleChars(n, phone)).join('').replace(/\s+/g, ' ');
      if (!own.includes(name)) continue;
      if (best === 'no') best = 'name';
      const cap = textRect(el).height + 200 * ts;
      for (let a = el; a && a !== phone; a = a.parentElement) {
        if (a.getBoundingClientRect().height > cap) break;
        const t = visibleText(a, phone);
        const hasS = t.includes(store), hasC = t.includes(cat);
        if (hasS && hasC) return 'yes';
        if (hasS || hasC) best = 'partly';
      }
    }
    return best;
  };
  const rowsVisible = (phone) => {
    const list = phone.querySelector('.list');
    const lr = list.getBoundingClientRect();
    const cover = coverTop(phone);
    return [...list.querySelectorAll('.item')].filter((it) => {
      const r = it.getBoundingClientRect();
      return r.top >= lr.top - 1 && r.bottom <= Math.min(lr.bottom, cover) + 1;
    });
  };
  // List text half under a floating layer (a toast or a bar above the field) after the close.
  const halfUnder = (phone) => {
    const floats = [...phone.querySelectorAll('.dock > .toast, .dock > .addedbar')].map((f) => f.getBoundingClientRect());
    return [...phone.querySelectorAll('.list .div, .list .cat, .list .item')]
      .filter((e) => floats.some((f) => {
        const r = e.getBoundingClientRect();
        const across = (y) => r.top < y - 2 && r.bottom > y + 2;
        return (across(f.top) || across(f.bottom)) && r.right > f.left && r.left < f.right;
      }))
      .map((e) => e.textContent.trim().replace(/\s+/g, ' ').slice(0, 20));
  };
  // What belongs to the option's feedback; everything else is main's chrome, the same in every phone.
  const OWN = '[data-note], .tray, .addedbar, .confirm, .toast, .rowchip, .newmark, .learned, .fixbox';
  // What the option's own feedback (note, tray, bar, card, toast, row chip, Learned line) shows a reader, its open
  // picker left out: the visible text of each outermost feedback element, a space between text nodes (“Added to” and
  // “Rewe” are separate elements), joined by “ | ”.
  const feedbackText = (phone) => {
    seen.clear();
    return [...phone.querySelectorAll(OWN)]
      .filter((el) => !el.parentElement.closest(OWN))
      .map((el) => {
        const w = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
        let t = '';
        for (let n = w.nextNode(); n; n = w.nextNode()) if (!n.parentElement.closest('.fixbox')) t += `${visibleChars(n, phone)} `;
        return t.replace(/\u0000/g, '').replace(/\s+/g, ' ').trim();
      })
      .filter(Boolean)
      .join(' | ');
  };
  // Layout faults at a large text size: text sticking out of the phone, text spilling out of its box, text cut by a
  // clipping ancestor or an ellipsis, two texts on top of each other, text under the home indicator.
  const faults = (phone) => {
    const out = [];
    const add = (el, what, also) => out.push({ what, chrome: !el.closest(OWN) && !also?.closest(OWN) });
    const short = (el) => el.textContent.trim().replace(/\s+/g, ' ').slice(0, 30);
    const pr = phone.getBoundingClientRect();
    const texts = [...phone.querySelectorAll('*')].filter((el) => [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim()) && getComputedStyle(el).visibility !== 'hidden' && el.getClientRects().length);
    for (const el of phone.querySelectorAll('*')) {
      const b = el.getBoundingClientRect();
      if (!b.width || b.right <= pr.right + 1) continue;
      let clipped = false;
      for (let a = el.parentElement; a && a !== phone; a = a.parentElement) if (getComputedStyle(a).overflowX !== 'visible') clipped = true;
      if (!clipped) add(el, `sticks out: ${el.className || el.tagName}`);
    }
    for (const el of texts) {
      const cs = getComputedStyle(el);
      if (el.matches('.emoji')) continue;
      if (cs.overflowX === 'visible' && el.scrollWidth > el.clientWidth + 2 && cs.display !== 'inline') add(el, `spills sideways: “${short(el)}”`);
      if (cs.overflowY === 'visible' && el.scrollHeight > el.clientHeight + 2 && cs.display !== 'inline') add(el, `spills down: “${short(el)}”`);
      // Cut sideways: a character outside a clipping ancestor (nothing on the phone scrolls sideways).
      const box = clipBox(el, phone, el);
      const r = textRect(el);
      if (box && !ellipsized(el) && (r.right > box.right + 1 || r.left < box.left - 1)) add(el, `cut: “${short(el)}”`);
    }
    for (const el of phone.querySelectorAll('*')) if (ellipsized(el)) add(el, `ellipsis: “${short(el)}”`);
    const vis = texts.map((el) => ({ el, r: visibleRect(el, phone, true) })).filter((x) => x.r);
    const layer = (el) => (el.closest('.edit-sheet') ? 'edit' : el.closest('.dock') ? 'dock' : 'list');
    for (let i = 0; i < vis.length; i++)
      for (let j = i + 1; j < vis.length; j++) {
        const a = vis[i], b = vis[j];
        if (layer(a.el) !== layer(b.el) || a.el.contains(b.el) || b.el.contains(a.el)) continue;
        const w = Math.min(a.r.right, b.r.right) - Math.max(a.r.left, b.r.left), h = Math.min(a.r.bottom, b.r.bottom) - Math.max(a.r.top, b.r.top);
        if (w > 2 && h > 2) add(a.el, `overlap: “${short(a.el).slice(0, 20)}” / “${short(b.el).slice(0, 20)}”`, b.el);
      }
    const bar = phone.querySelector('.homeind i')?.getBoundingClientRect();
    if (bar?.width)
      for (const { el, r } of vis) if (r.top < bar.bottom && r.bottom > bar.top && r.left < bar.right && r.right > bar.left) add(el, `under the home indicator: “${short(el).slice(0, 20)}”`);
    return out;
  };
  const targets = (phone) =>
    [...phone.querySelectorAll('button, [data-act]:not(.scrim):not(.item), input')]
      .filter((el) => visibleRect(el, phone))
      .map((el) => ({ el, r: el.getBoundingClientRect() }))
      .filter(({ el, r }) => (r.height < 44 || r.width < 44) && !el.closest('.srow .badge-hex'))
      .map(({ el, r }) => `${el.dataset.act ?? el.tagName} “${(el.getAttribute('aria-label') || el.textContent).trim().slice(0, 20)}” ${Math.round(r.width)}×${Math.round(r.height)}`);
  // Counts the pixels that differ between two PNG screenshots of the same box (data URLs) and how strongly: each
  // changed pixel's contrast ratio between its two colours, from pixel row `top` down. Returns { strong: px at ≥ 3:1, weak: px below, median }.
  const diff = async (a, b, top = 0) => {
    const load = async (u) => createImageBitmap(await (await fetch(u)).blob());
    const [ia, ib] = await Promise.all([load(a), load(b)]);
    const px = (img) => {
      const c = new OffscreenCanvas(img.width, img.height);
      const g = c.getContext('2d');
      g.drawImage(img, 0, 0);
      return g.getImageData(0, 0, img.width, img.height).data;
    };
    const da = px(ia), db = px(ib);
    const lin = (v) => ((v /= 255) <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
    const lum = (d, i) => 0.2126 * lin(d[i]) + 0.7152 * lin(d[i + 1]) + 0.0722 * lin(d[i + 2]);
    const ratios = [];
    let weak = 0;
    for (let i = top * ia.width * 4; i < da.length; i += 4) {
      if (Math.abs(da[i] - db[i]) + Math.abs(da[i + 1] - db[i + 1]) + Math.abs(da[i + 2] - db[i + 2]) < 12) continue;
      const la = lum(da, i), lb = lum(db, i);
      const r = (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
      if (r >= 3) ratios.push(r);
      else weak++;
    }
    ratios.sort((x, y) => x - y);
    return { strong: ratios.length, weak, median: ratios.length ? Math.round(ratios[ratios.length >> 1] * 10) / 10 : null };
  };
  // Hex faces whose content sits off the face's vertical centre by more than 2 px (Peter: content in a hex stays centred).
  const offCentre = (phone) =>
    [...phone.querySelectorAll('.tact > span, .chip > span, .opt > span, .confirm-chip > span, .rowchip > span')]
      .filter((f) => f.getBoundingClientRect().height)
      .flatMap((f) => {
        const fr = f.getBoundingClientRect();
        const range = document.createRange();
        range.selectNodeContents(f);
        const rs = [...range.getClientRects()].filter((r) => r.height && r.width);
        if (!rs.length) return [];
        const top = Math.min(...rs.map((r) => r.top)), bottom = Math.max(...rs.map((r) => r.bottom));
        const off = (top + bottom) / 2 - (fr.top + fr.bottom) / 2;
        return Math.abs(off) > 2 ? [`${f.textContent.trim().slice(0, 24)} ${Math.round(off)} px`] : [];
      });
  // The option's chips whose label does not read as one run of text: walking its characters and icons in DOM order,
  // each sits on the same line right of the one before, or on a later line. A flex face whose label is several flex
  // items lays them out as side-by-side columns, so a later piece sits beside or above an earlier one (1ef304ef).
  const readingOrder = (phone) =>
    [...phone.querySelectorAll('.confirm-chip > span, .rowchip > span')]
      .filter((f) => f.getBoundingClientRect().height)
      .flatMap((f) => {
        const pieces = [];
        const w = document.createTreeWalker(f, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
        for (let n = w.nextNode(); n; n = w.nextNode()) {
          if (n.nodeType === 3) {
            const range = document.createRange();
            for (let i = 0; i < n.length; i++) {
              if (/\s/.test(n.data[i])) continue;
              range.setStart(n, i);
              range.setEnd(n, i + 1);
              const r = range.getBoundingClientRect();
              if (r.width && r.height) pieces.push({ r, c: n.data[i] });
            }
          } else if (n.localName === 'svg') pieces.push({ r: n.getBoundingClientRect(), c: '▾' });
        }
        for (let i = 1; i < pieces.length; i++) {
          const a = pieces[i - 1].r, b = pieces[i].r;
          const sameLine = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) >= Math.min(a.height, b.height) / 2;
          if (sameLine ? b.left >= a.right - 2 : b.top >= a.bottom - 3) continue;
          return [`“${f.textContent.trim().replace(/\s+/g, ' ').slice(0, 40)}”: “${pieces[i].c}” sits ${sameLine ? 'left of' : 'beside or above'} the “${pieces[i - 1].c}” before it`];
        }
        return [];
      });
  return { feedbackText, readingOrder, offCentre, visibleRect, visibleText, coverTop, identify, rowsVisible, halfUnder, faults, targets, diff };
};
