Press Start 2P, VT323, and Noto Sans CJK were copied from CausewaybayGolang/love2d/assets/fonts, including their SIL Open Font License files.

godot-latin-fallback.woff2 is the default Noto Sans font embedded in the installed Godot 4.7.2 engine, extracted from ThemeDB.fallback_font in an empty project. It supplies Latin Extended glyphs, including Czech Č and š, missing from the supplied CJK font. Noto Sans uses the SIL Open Font License (see NotoSansCJK-OFL.txt).

game-ui.tres uses Noto Sans for Latin text and the supplied CJK font for Korean, Japanese, Chinese, and Cantonese. retro-title.tres uses Press Start 2P for the game's English title with CJK fallback.

arcade-ui.tres uses VT323 for game menus and dialogue, with game-ui.tres providing missing multilingual glyphs.
