import type { ReactElement } from 'react';
import { Raw, mso } from '../raw.tsx';
import { text, ui } from '../theme.ts';

const HEIGHT = ui.target;
const escape = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/**
 * The mail's one call to action: a yellow button with the navy contour, 48 px tall, and the raw
 * link printed under it for clients that break buttons. Outlook on Windows gets a VML button of
 * the same size. `fallbackLabel` leads the raw link ("Falls der Knopf nicht geht, öffne diesen
 * Link:"); without it the link stands alone. render.ts refuses a mail with two of these.
 */
export function PrimaryButton({ href, children, fallbackLabel }: { href: string; children: string; fallbackLabel?: string }): ReactElement {
  const border = ui.border.width;
  // VML needs a fixed width: wide enough for the label in Arial bold at the button's size.
  const width = Math.max(200, Math.ceil(children.length * ui.typography.body.size * 0.62) + 2 * ui.space[6]);
  const vml = mso(
    `<v:roundrect xmlns:v="urn:schemas-microsoft-com:vml" xmlns:w="urn:schemas-microsoft-com:office:word" href="${escape(href)}" style="height:${HEIGHT}px;v-text-anchor:middle;width:${width}px;" arcsize="25%" strokecolor="${ui.light.ink}" strokeweight="${border}px" fillcolor="${ui.light.honey}"><w:anchorlock/><center style="color:${ui.light['on-honey']};font-family:Arial,sans-serif;font-size:${ui.typography.body.size}px;font-weight:bold;">${escape(children)}</center></v:roundrect>`,
  );
  return (
    <div data-hl-cta="true" data-hl-label={children} data-hl-href={href} style={{ margin: `${ui.space[2]}px 0 ${ui.space[4]}px 0` }}>
      <Raw html={vml} />
      <Raw html="<!--[if !mso]><!-->" />
      <table role="presentation" className="hl-btn-table" cellPadding={0} cellSpacing={0} border={0} data-skip-in-text="true">
        <tbody>
          <tr>
            <td align="center" bgcolor={ui.light.honey} className="hl-honey"
              style={{
                backgroundColor: ui.light.honey, border: `${border}px solid ${ui.light.ink}`, borderRadius: ui.radius.md,
                boxShadow: `0 ${ui.depth.edge}px 0 ${ui.light.ink}`,
              }}>
              <a href={href} target="_blank" className="hl-honey"
                style={{
                  display: 'block', padding: `0 ${ui.space[6]}px`, lineHeight: `${HEIGHT - 2 * border}px`, minHeight: HEIGHT - 2 * border,
                  fontFamily: ui.font.body, fontSize: `${ui.typography.body.size}px`, fontWeight: ui.weight.bold,
                  color: ui.light['on-honey'], textDecoration: 'none', textAlign: 'center', borderRadius: ui.radius.md,
                }}>
                {children}
              </a>
            </td>
          </tr>
        </tbody>
      </table>
      <Raw html="<!--<![endif]-->" />
      <p className="hl-muted" style={{ ...text.muted, margin: `${ui.space[4]}px 0 0 0` }}>
        {fallbackLabel ? <span data-skip-in-text="true">{fallbackLabel} </span> : null}
        <a href={href} target="_blank" className="hl-link" style={{ color: ui.light.accent, textDecoration: 'underline', overflowWrap: 'anywhere', wordBreak: 'break-word' }}>{href}</a>
      </p>
    </div>
  );
}
