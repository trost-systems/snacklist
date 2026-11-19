import sys, json, re
sys.path.insert(0, sys.argv[1])
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
font = TTFont(sys.argv[2])
src = open(sys.argv[3]).read()
names = sys.argv[4].split(',')
cmap = font.getBestCmap(); gs = font.getGlyphSet(); upem = font['head'].unitsPerEm
asc = font['hhea'].ascent
out = {}
for n in names:
    m = re.search(r'static const IconData %s = IconData\(\s*(0x[0-9a-f]+)' % re.escape(n), src)
    cp = int(m.group(1), 16)
    pen = SVGPathPen(gs, ntos=lambda v: ('%.6f' % v).rstrip('0').rstrip('.') if '.' in '%.6f' % v else str(v))
    s = 24 / upem
    gs[cmap[cp]].draw(TransformPen(pen, (s, 0, 0, -s, 0, asc * s)))
    out[n] = pen.getCommands()
print(json.dumps(out, indent=1))
