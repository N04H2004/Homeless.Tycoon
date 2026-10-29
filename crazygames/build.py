#!/usr/bin/env python3
"""Fabrique le ZIP à déposer sur CrazyGames.

Le jeu est le même que sur Vercel : on ajoute seulement window.CG_BUILD=1 tout en haut de <head>,
ce qui active le mode CrazyGames (SDK, pubs CrazyGames, anglais par défaut, compte invité automatique).
Usage : python3 crazygames/build.py  ->  crazygames/homeless-tycoon-crazygames.zip
"""
import pathlib, zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / 'crazygames' / 'homeless-tycoon-crazygames.zip'
FILES = ['lang-en.js', 'favicon.png', 'logo/icon.png', 'logo/icon.svg']

html = (ROOT / 'index.html').read_text(encoding='utf-8')
assert '<head>' in html, 'balise <head> introuvable'
html = html.replace('<head>', '<head>\n<script>window.CG_BUILD=1</script>', 1)
# sur CrazyGames, pas d'appli à installer : le manifeste (absent du zip) est retiré
html = html.replace('<link rel="manifest" href="/manifest.webmanifest">', '', 1)

with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('index.html', html)
    for f in FILES:
        z.write(ROOT / f, f)
size = OUT.stat().st_size
print(f'{OUT.relative_to(ROOT)} : {len(FILES) + 1} fichiers, {size / 1024:.0f} Ko')
