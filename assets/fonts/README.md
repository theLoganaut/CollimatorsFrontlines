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
