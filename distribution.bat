@echo off
pushd %~dp0
@mkdir .\\build
@REM odin run src -vet -warnings-as-errors -no-bounds-check -o:speed -show-timings -microarch:native -thread-count:6 -pdb-name:build/chesst.pdb -out:build/chesst.exe -strict-style-init-only
odin test src -vet -warnings-as-errors -debug -o:speed -show-timings -microarch:native -thread-count:6 -pdb-name:test.pdb -collection:libs=libs
odin run src -vet -warnings-as-errors -debug -o:speed -show-timings -microarch:native -thread-count:6 -pdb-name:build/chesst.pdb -out:build/chesst.exe -collection:libs=libs -strict-style-init-only
popd