"""Generates the app's launcher and notification icons from one wordmark.

Usage: python tool/make_icons.py android/app/src/main/res [preview.png]

The "IUT" letters are drawn on a 108x108 grid (the adaptive-icon canvas),
inside the 66x66 safe zone, centred on (54, 54).
"""
import os
import sys

from PIL import Image, ImageDraw

RES = sys.argv[1]  # android/app/src/main/res
ACCENT = (0x1D, 0x4E, 0x89)

I_PATH = 'M25,39 h6 v30 h-6 z'
U_PATH = 'M37,39 h6 v19 a5,5 0 0 0 10,0 v-19 h6 v19 a11,11 0 0 1 -22,0 z'
T_PATH = 'M63,39 h20 v6 h-7 v24 h-6 v-24 h-7 z'
LETTERS = ' '.join([I_PATH, U_PATH, T_PATH])


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)


# Adaptive icon (Android 8+), with a monochrome layer for themed icons (13+).
write(f'{RES}/drawable/ic_launcher_foreground.xml', f'''<?xml version="1.0" encoding="utf-8"?>
<!-- The "IUT" wordmark, white, well inside the adaptive icon's 66dp safe zone. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <group android:pivotX="54" android:pivotY="54" android:scaleX="0.86" android:scaleY="0.86">
        <path android:fillColor="#FFFFFF" android:pathData="{LETTERS}" />
    </group>
</vector>
''')
write(f'{RES}/drawable/ic_launcher_monochrome.xml', f'''<?xml version="1.0" encoding="utf-8"?>
<!-- Themed-icon layer (Android 13+): the system tints it. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <group android:pivotX="54" android:pivotY="54" android:scaleX="0.86" android:scaleY="0.86">
        <path android:fillColor="#FFFFFF" android:pathData="{LETTERS}" />
    </group>
</vector>
''')
write(f'{RES}/values/ic_launcher_background.xml', '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- DESIGN.md 3: the accent, from the deep blue of the IUT emblem. -->
    <color name="ic_launcher_background">#1D4E89</color>
</resources>
''')
write(f'{RES}/mipmap-anydpi-v26/ic_launcher.xml', '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
''')

# Status bar icon: white on transparent, the letters filling the 24dp box.
# The viewport is the letters' box (x 25..83, y 39..69) plus 3 units around.
write(f'{RES}/drawable/ic_stat_notify.xml', f'''<?xml version="1.0" encoding="utf-8"?>
<!-- Notification small icon: white on transparent (Android tints it). -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="64"
    android:viewportHeight="64">
    <group android:translateX="-22" android:translateY="-22">
        <path android:fillColor="#FFFFFF" android:pathData="{LETTERS}" />
    </group>
</vector>
''')
write(f'{RES}/raw/keep.xml', '''<?xml version="1.0" encoding="utf-8"?>
<!-- R8 resource shrinking can't see icons named only from Dart (flutter_local_notifications). -->
<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@drawable/ic_stat_notify,@mipmap/ic_launcher" />
''')


# Legacy PNGs (Android 7.x): a rounded square in the accent with the letters.
def legacy(n):
    k = 4  # supersample
    size = n * k
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    margin = round(size * 0.04)
    d.rounded_rectangle([margin, margin, size - margin - 1, size - margin - 1], radius=round(size * 0.22),
                        fill=ACCENT + (255,))
    s = 0.62 * size / 58

    def p(x, y):
        return ((x - 54) * s + size / 2, (y - 54) * s + size / 2)

    def rect(x0, y0, x1, y1, fill=(255, 255, 255, 255)):
        d.rectangle([p(x0, y0), p(x1, y1)], fill=fill)

    rect(25, 39, 31, 69)  # I
    rect(37, 39, 43, 58)  # U left
    rect(53, 39, 59, 58)  # U right
    d.pieslice([p(37, 47), p(59, 69)], 0, 180, fill=(255, 255, 255, 255))  # U bowl
    d.ellipse([p(43, 53), p(53, 63)], fill=ACCENT + (255,))  # U counter, bottom
    d.rectangle([p(43, 39), p(53, 58)], fill=ACCENT + (255,))  # U counter, top
    rect(63, 39, 83, 45)  # T bar
    rect(70, 39, 76, 69)  # T stem
    return img.resize((n, n), Image.LANCZOS)


for folder, n in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    legacy(n).save(f'{RES}/mipmap-{folder}/ic_launcher.png')

if len(sys.argv) > 2:  # optional: a 512 px preview, e.g. for a store listing
    legacy(512).save(sys.argv[2])
print('ok')
