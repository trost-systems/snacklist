import { Img } from '@react-email/components';
import type { ReactElement } from 'react';
import { text, ui } from '../theme.ts';

/** Only images hosted on snacklist.app: every remote load in a mail reveals the reader's IP. */
export type SnacklistImage = `https://snacklist.app/${string}.png`;

/**
 * A phone screen in the RD1 navy frame, centred, fixed width. Demo data only (fixture households,
 * never real lists). `alt` is required and shown in the frame when images are blocked, so say
 * what the screen shows. `src` is a PNG at 2x of `width` x `height`.
 */
export function PhoneScreenshot({ src, alt, width = 240, height }: { src: SnacklistImage; alt: string; width?: number; height: number }): ReactElement {
  if (!alt.trim()) throw new Error('PhoneScreenshot needs alt text that says what the screen shows');
  const bezel = ui.space[2];
  return (
    <table role="presentation" align="center" cellPadding={0} cellSpacing={0} border={0} style={{ margin: `${ui.space[2]}px auto ${ui.space[5]}px auto` }}>
      <tbody>
        <tr>
          <td bgcolor={ui.light.ink} style={{ backgroundColor: ui.light.ink, padding: bezel, borderRadius: ui.radius.xl, boxShadow: `0 ${ui.depth.edge}px 0 ${ui.light.ink}` }}>
            <table role="presentation" cellPadding={0} cellSpacing={0} border={0}>
              <tbody>
                <tr>
                  <td width={width} height={height} align="center" valign="middle" bgcolor={ui.light.surface}
                    style={{ width, height, backgroundColor: ui.light.surface, borderRadius: ui.radius.xl - bezel, overflow: 'hidden' }}>
                    <Img src={src} alt={alt} width={width} height={height}
                      style={{ display: 'block', width, height, border: 0, borderRadius: ui.radius.xl - bezel, ...text.muted, margin: 0, textAlign: 'center' }} />
                  </td>
                </tr>
              </tbody>
            </table>
          </td>
        </tr>
      </tbody>
    </table>
  );
}
