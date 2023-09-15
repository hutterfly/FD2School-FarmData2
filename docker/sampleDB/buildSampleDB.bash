#!/bin/bash

# This script builds a sample database for development and
# testing of FarmData2.  The data is anonymized data from
# the Dickinson College farm.

# The build starts from an empty database and adds all of the
# uses, terms and data that make up the sample database.
# It can be reconstructed at any time by running this script.

HOST=$(docker inspect -f '{{.Name}}' $HOSTNAME 2> /dev/null)
if [ "$HOST" != "/fd2_dev" ];
then
  echo "Error: The buildSampleDB script must be run in the dev container."
  exit -1
fi

echo "Switching to empty db image..."
cd ..
echo "  Stopping FarmData2..."
docker stop fd2_farmdata2
echo "  Stopping Mariadb..."
docker stop fd2_mariadb
echo "  Deleting current db..."
cd db
sudo rm -rf *
echo "  Extracting empty db..."
sudo tar -xjf ../db.empty.tar.bz2
cd ..
echo "  Restarting Mariadb..."
docker start fd2_mariadb
echo "  Restarting FarmData2..."
docker start fd2_farmdata2
cd sampleDB
echo "Switched to empty db image."

sleep 5  # make sure drupal is fully up before starting.

echo "Setting farm info..."
docker exec -it fd2_farmdata2 drush vset site_name "Sample Farm"
docker exec -it fd2_farmdata2 drush vset site_slogan "Farm with sample data for development and testing."
echo "Farm info set."

echo "Enabling restws basic authentication..."
# Adds query parameter criteron for [gt], [lt], etc...
docker exec -it fd2_farmdata2 drush en restws_basic_auth -y
echo "restws basic authentication enabled."

echo "Enabling FarmData2 modules..."
docker exec -it fd2_farmdata2 drush en fd2_example -y
docker exec -it fd2_farmdata2 drush en fd2_barn_kit -y
docker exec -it fd2_farmdata2 drush en fd2_field_kit -y
docker exec -it fd2_farmdata2 drush en fd2_config -y
docker exec -it fd2_farmdata2 drush en fd2_school -y
echo "Enabled."

echo "Enabling the Field UI module..."
# Allows the editing of fields associated with vocabularies, logs and assests.
docker exec -it fd2_farmdata2 drush en field_ui -y
echo "Enabled."

# Create the 'people' (i.e. users) in the sample FarmData2 database.
source ./addPeople.bash

# Give logged in users permission to access the fd2_config module.
echo "Adding permissions for fd2_config API..."
docker exec -it fd2_farmdata2 drush role-add-perm "authenticated user" --module=restws "access resource fd2_config"
echo "Permissions added."

# Add custom FarmData2 fields to the Drupal entities.
echo "Adding FarmData2 custom fields..."
docker exec -it fd2_farmdata2 drush scr addDrupalFields.php --script-path=/sampleDB
echo "Fields added."

echo "Checking for FarmData2 host..."
echo -e "GET http://localhost HTTP/1.0\n\n" | nc localhost 80 > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "  Host is localhost."
  export FD2_HOST="localhost"  # Running build script on host.
else
  echo "  Host is fd2_farmdata2 container."
  export FD2_HOST="fd2_farmdata2"  # Running build script in container.
fi

# Create the vocabularies
  # Add the units used for quantities
  ./addUnits.py
  # Add the crop families and crops.
  ./addCrops.py
  # Add the farm areas (fields, greenhouses, beds)
  ./addAreas.py

# Add the data
  # Add plantings and seedings that create them.
  ./addDirectSeedings.py
  ./addTraySeedings.py
  # Add direct seedings and any necessary plantings
  ./addTransplantings.py
  # Add the harvests
  ./addHarvests.py

echo "Compressing the sample database..."
cd ..
rm -f db.sample.tar.bz2
docker exec -it fd2_farmdata2 drush cc all
cd db
sudo tar cjvf ../db.sample.tar.bz2 *
cd ../sampleDB
echo "Compressed the sample database."
