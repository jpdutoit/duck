echo Build duck executable
dub --quiet build duck:duck --build=release
echo Build duck executable \(interactive version\)
dub --quiet build duck:duck --config=interactive --build=release
echo Build duck runtime
dub --quiet build duck:runtime  --build=release
echo Build duck runtime \(port-audio\)
dub --quiet build duck:runtime --config=port-audio --build=release
