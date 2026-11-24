import type { ReactElement, ReactNode } from 'react';
import { text, ui } from '../theme.ts';

/** A highlighted aside: honey left border on the honey tint. Optional bold title line. */
export function TipBox({ title, children }: { title?: string; children: ReactNode }): ReactElement {
  return (
    <table role="presentation" width="100%" cellPadding={0} cellSpacing={0} border={0} style={{ margin: `${ui.space[1]}px 0 ${ui.space[5]}px 0` }}>
      <tbody>
        <tr>
          <td className="hl-tip" bgcolor={ui.light['honey-soft']}
            style={{ backgroundColor: ui.light['honey-soft'], borderLeft: `${ui.depth.edge}px solid ${ui.light.honey}`, borderRadius: ui.radius.sm, padding: `${ui.space[4]}px ${ui.space[4]}px ${ui.space[1]}px ${ui.space[4]}px` }}>
            {title ? <p className="hl-text" style={text.stepTitle}>{title}</p> : null}
            {children}
          </td>
        </tr>
      </tbody>
    </table>
  );
}

/** A one-time code, large and spaced so it is easy to read and copy. */
export function CodeBox({ children }: { children: string }): ReactElement {
  return (
    <table role="presentation" cellPadding={0} cellSpacing={0} border={0} style={{ margin: `0 0 ${ui.space[5]}px 0` }}>
      <tbody>
        <tr>
          <td className="hl-sunken hl-text" bgcolor={ui.light['surface-sunken']}
            style={{
              backgroundColor: ui.light['surface-sunken'], border: `${ui.border.thin}px solid ${ui.light.divider}`, borderRadius: ui.radius.sm,
              padding: `${ui.space[3]}px ${ui.space[5]}px`, fontFamily: ui.font.display, fontSize: `${ui.typography.headline.size}px`,
              fontWeight: ui.weight.heavy, letterSpacing: '0.12em', color: ui.light.text,
            }}>
            {children}
          </td>
        </tr>
      </tbody>
    </table>
  );
}
