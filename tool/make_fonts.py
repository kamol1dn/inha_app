"""Cuts the app's static fonts from the upstream variable fonts.

Usage: python tool/make_fonts.py <dir with the google/fonts files> assets/fonts

The input directory holds, from https://github.com/google/fonts:
  ofl/fraunces/Fraunces[SOFT,WONK,opsz,wght].ttf          as Fraunces.ttf
  ofl/fraunces/Fraunces-Italic[SOFT,WONK,opsz,wght].ttf   as Fraunces-Italic.ttf
  ofl/publicsans/PublicSans[wght].ttf                     as PublicSans.ttf
and each family's OFL.txt as Fraunces-OFL.txt and PublicSans-OFL.txt.

Fraunces has proportional digits and no `tnum` feature, so this adds one:
tabular copies of 0-9 (composites of the originals, centred on the widest
digit's advance) behind a `tnum` lookup. DESIGN.md section 4 says which
style uses which file.
"""
import os
import shutil
import sys

from fontTools.ttLib import TTFont
from fontTools.ttLib.tables import otTables as ot
from fontTools.ttLib.tables._g_l_y_f import Glyph, GlyphComponent
from fontTools.varLib import instancer

SRC, OUT = sys.argv[1], sys.argv[2]

# (output file, source, axis location, family, style, weight, italic)
FONTS = [
    ('Fraunces-Regular.ttf', 'Fraunces.ttf', dict(opsz=20, wght=400, SOFT=0, WONK=1), 'Fraunces', 'Regular', 400, False),
    ('Fraunces-SemiBold.ttf', 'Fraunces.ttf', dict(opsz=20, wght=600, SOFT=0, WONK=1), 'Fraunces', 'SemiBold', 600, False),
    ('Fraunces-Italic.ttf', 'Fraunces-Italic.ttf', dict(opsz=20, wght=400, SOFT=0, WONK=1), 'Fraunces', 'Italic', 400, True),
    ('FrauncesDisplay-SemiBold.ttf', 'Fraunces.ttf', dict(opsz=72, wght=600, SOFT=0, WONK=1), 'Fraunces Display',
     'SemiBold', 600, False),
    ('PublicSans-Regular.ttf', 'PublicSans.ttf', dict(wght=400), 'Public Sans', 'Regular', 400, False),
    ('PublicSans-Medium.ttf', 'PublicSans.ttf', dict(wght=500), 'Public Sans', 'Medium', 500, False),
    ('PublicSans-SemiBold.ttf', 'PublicSans.ttf', dict(wght=600), 'Public Sans', 'SemiBold', 600, False),
]


def add_tnum(font):
    """Adds `<digit>.tnum` glyphs, all as wide as the widest digit, and a
    `tnum` feature that swaps them in."""
    cmap = font.getBestCmap()
    digits = [cmap[0x30 + i] for i in range(10)]
    glyf, hmtx = font['glyf'], font['hmtx']
    width = max(hmtx[g][0] for g in digits)
    for g in digits:
        comp = GlyphComponent()
        comp.glyphName = g
        comp.x, comp.y = round((width - hmtx[g][0]) / 2), 0
        comp.flags = 0x0004  # ROUND_XY_TO_GRID
        glyph = Glyph()
        glyph.numberOfContours = -1
        glyph.components = [comp]
        glyf[g + '.tnum'] = glyph  # also appends to the glyph order
        glyph.recalcBounds(glyf)
        hmtx[g + '.tnum'] = (width, glyph.xMin)
    order = font.getGlyphOrder()
    font.setGlyphOrder(order + [g + '.tnum' for g in digits if g + '.tnum' not in order])
    font.getReverseGlyphMap(rebuild=True)
    if 'GDEF' in font and font['GDEF'].table.GlyphClassDef:
        classes = font['GDEF'].table.GlyphClassDef.classDefs
        for g in digits:
            classes[g + '.tnum'] = 1  # base glyph

    gsub = font['GSUB'].table
    subst = ot.SingleSubst()
    subst.mapping = {g: g + '.tnum' for g in digits}
    lookup = ot.Lookup()
    lookup.LookupType, lookup.LookupFlag = 1, 0
    lookup.SubTable = [subst]
    lookup.SubTableCount = 1
    gsub.LookupList.Lookup.append(lookup)
    gsub.LookupList.LookupCount = len(gsub.LookupList.Lookup)

    record = ot.FeatureRecord()
    record.FeatureTag = 'tnum'
    record.Feature = ot.Feature()
    record.Feature.FeatureParams = None
    record.Feature.LookupListIndex = [len(gsub.LookupList.Lookup) - 1]
    record.Feature.LookupCount = 1
    # Feature records are kept sorted by tag; renumber the language systems' indices to match.
    records = gsub.FeatureList.FeatureRecord + [record]
    order = sorted(range(len(records)), key=lambda i: records[i].FeatureTag)
    new_index = {old: new for new, old in enumerate(order)}
    gsub.FeatureList.FeatureRecord = [records[i] for i in order]
    gsub.FeatureList.FeatureCount = len(records)
    tnum_index = new_index[len(records) - 1]
    for script in gsub.ScriptList.ScriptRecord:
        systems = [script.Script.DefaultLangSys] + [r.LangSys for r in script.Script.LangSysRecord]
        for ls in systems:
            if ls is None:
                continue
            ls.FeatureIndex = sorted([new_index[i] for i in ls.FeatureIndex] + [tnum_index])
            ls.FeatureCount = len(ls.FeatureIndex)
            if ls.ReqFeatureIndex != 0xFFFF:
                ls.ReqFeatureIndex = new_index[ls.ReqFeatureIndex]


def set_names(font, family, style, weight, italic):
    ribbi = style in ('Regular', 'Italic')
    name = font['name']
    for nid in (1, 2, 3, 4, 6, 16, 17, 25):
        name.removeNames(nameID=nid)
    full = f'{family} {style}'
    ps = f'{family.replace(" ", "")}-{style}'
    name.setName(family if ribbi else f'{family} {style}', 1, 3, 1, 0x409)
    name.setName(style if ribbi else 'Regular', 2, 3, 1, 0x409)
    name.setName(f'{ps};IUT app static instance', 3, 3, 1, 0x409)
    name.setName(full, 4, 3, 1, 0x409)
    name.setName(ps, 6, 3, 1, 0x409)
    if not ribbi:
        name.setName(family, 16, 3, 1, 0x409)
        name.setName(style, 17, 3, 1, 0x409)
    os2 = font['OS/2']
    os2.usWeightClass = weight
    # fsSelection: bit 0 italic, bit 5 bold, bit 6 regular.
    os2.fsSelection = (os2.fsSelection & ~0b1100001) | (1 if italic else 0) | (0 if italic else 0b1000000)
    font['head'].macStyle = 0b10 if italic else 0


os.makedirs(OUT, exist_ok=True)
for out, src, location, family, style, weight, italic in FONTS:
    font = instancer.instantiateVariableFont(TTFont(os.path.join(SRC, src)), location)
    for table in ('STAT', 'hdmx', 'LTSH', 'VDMX'):
        if table in font:
            del font[table]
    if family.startswith('Fraunces'):
        add_tnum(font)
    set_names(font, family, style, weight, italic)
    font.save(os.path.join(OUT, out))
    print(out, os.path.getsize(os.path.join(OUT, out)))

shutil.copy(os.path.join(SRC, 'Fraunces-OFL.txt'), os.path.join(OUT, 'OFL-Fraunces.txt'))
shutil.copy(os.path.join(SRC, 'PublicSans-OFL.txt'), os.path.join(OUT, 'OFL-PublicSans.txt'))
