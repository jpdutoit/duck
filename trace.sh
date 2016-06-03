dub build duck:duck --quiet --build=cov
lldb -o "settings set frame-format \" at \${line.file.fullpath}:\${line.number}\n\"" -o run -o "thread backtrace" -o exit bin/duck -- run --no-stdlib $1 2>&1 | ddemangle
