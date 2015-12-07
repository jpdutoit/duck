dub --quiet build duck:duck --build=release
dub --quiet build duck:runtime  --build=release
dub --quiet build duck:runtime --config=port-audio --build=release
dub --quiet build duck:duck --config=interactive --build=release
