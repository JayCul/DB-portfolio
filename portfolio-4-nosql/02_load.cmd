@echo off
rem Deeva's Designs: load the exported JSON files into MongoDB.
rem
rem Run from this folder, after 01_export_from_postgres.sql and with the
rem container started (docker compose up -d). Each collection is dropped
rem and loaded again, so running this also resets the database.

for %%c in (wearers orders styles) do (
    echo Loading %%c
    docker compose exec -T mongo mongoimport --quiet --db deevas --collection %%c --drop --file /work/data/%%c.json || exit /b 1
)

echo.
echo Documents loaded:
docker compose exec -T mongo mongosh --quiet deevas --eval "['wearers','orders','styles'].forEach(c => print('  ' + c.padEnd(8), db[c].countDocuments()))"
