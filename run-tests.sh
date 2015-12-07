mkdir coverage

echo Running unittests
dub run duck:duck --quiet --build=unittest-cov

echo Running external tests
dub build duck:duck --quiet --build=cov
time dub run duck:test-runner --quiet  -- --executable bin/duck $1 $2 $3 $4 $5 $6

echo Generating test report
dub run duck:coverage-report --quiet --build=release -- --template reports/template

rm coverage/*.lst
cp reports/template/static/* coverage

mkdir -p reports
rm -rf reports/coverage
mv coverage reports

# Restore release versions
echo Restore release versions
./build.sh
