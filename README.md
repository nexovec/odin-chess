# Chesst

A minimalist chess gui for managing databases with emphasis on performance.

## features

- [ ] sortable database view
  - [ ] metadata filtering
- [ ] fullscreen mode
- [ ] importing positions
  - [ ] pgn
  - [ ] fen
- [ ] advanced filtering
  - [ ] same position
  - [ ] opening tree
- [ ] game preview
  - [ ] animations
  - [ ] exports
    - [ ] pgn
    - [ ] fen
- [ ] legality checks

## technology

It's written in odin, uses microui.

## developing

You need to have odin folder in your PATH, there's `debug.bat` and `release.bat` build scripts that should build and launch chesst.

If you're planning to develop with vs code, install the ols extension, then clone odin, ols and chesst into the same folder, then open the .code-workspace file, set ols path in vs code settings correctly and you should have go-to definition and static analysis working.
