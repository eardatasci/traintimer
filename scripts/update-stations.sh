#!/bin/sh
# Refreshes the bundled station list from the MTA's "Subway Stations" dataset on data.ny.gov.
set -eu
cd "$(dirname "$0")/.."

curl -fsSL "https://data.ny.gov/api/views/39hk-dx4f/rows.csv?accessType=DOWNLOAD" -o App/Resources/stations.csv
echo "Updated App/Resources/stations.csv ($(($(wc -l < App/Resources/stations.csv) - 1)) stops)"
