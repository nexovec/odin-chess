@echo off
pushd %~dp0
mkdir .\\build
odin run src -vet -warnings-as-errors -no-bounds-check -debug -o:speed -show-timings -microarch:native -thread-count:6 -pdb-name:build/chesst.pdb -out:build/chesst.exe -strict-style-init-only
popd