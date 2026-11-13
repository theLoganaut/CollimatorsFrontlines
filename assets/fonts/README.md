# Fonts

`VT323-Scaled.ttf` is the game's font (project setting `gui/theme/custom_font`):
VT323 (Peter Hull, SIL Open Font License 1.1, `VT323-OFL.txt`) from
github.com/google/fonts `ofl/vt323`, drawn 20% bigger at every size so the
game's font sizes read as they did with Godot's default font (Logan,
2026-10-16). Made by setting its unitsPerEm from 1000 to 833 with fontTools
(its DSIG signature removed, since it no longer matches):

    head.unitsPerEm = round(1000 / 1.2)

It imports as MSDF (pixel range 16) like the default font did, so it stays
sharp at the stretched window sizes and outlined text stays clean.

`VT323-Scaled-Large.ttf` and `VT323-Scaled-Larger.ttf` are the same font
1.2× and 1.4× bigger again, for Settings → Text size (`GameSettings.text_size`
swaps the theme's default font; Large is the default on a Steam Deck). Made
the same way from `VT323-Scaled.ttf` (unitsPerEm 833):

    head.unitsPerEm = round(833 / 1.2)   # Large: 694
    head.unitsPerEm = round(833 / 1.4)   # Larger: 595

Their `.import` files match `VT323-Scaled.ttf.import` (MSDF).
