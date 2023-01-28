# Chesst

A minimalist chess gui for managing databases with emphasis on performance.

## features

- [x] database view (partially done)
  - [ ] sorting columns
  - [x] metadata filtering
- [ ] fullscreen mode
- [ ] importing positions
  - [x] pgn (partially done)
    - [ ] old notation
    - [ ] localized notation
    - [ ] read annotations
    - [ ] read comments
  - [ ] fen
- [ ] advanced filtering
  - [ ] same position
  - [ ] opening tree
- [x] game preview
  - [ ] animations
  - [ ] custom annotations
  - [ ] variations support
  - [ ] exports
    - [ ] pgn
    - [ ] fen
- [x] legality checks (partially done)

## technology

It's written in odin, uses microui.

## developing

You need to have odin folder in your PATH, there's `debug.bat`, `release.bat` and `distribution.bat` build scripts that should build and launch chesst. There is `check.bat` that checks if the project compiles and `test.bat` that runs the tests.

`data/Small.pgn` contains 18 games

If you're planning to develop with vs code, install the ols extension, then clone odin, ols and chesst into the same folder, then open the .code-workspace file as a workspace in vs code, set ols path in vs code settings correctly and you should have go-to definition and static analysis working.
