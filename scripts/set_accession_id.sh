# This script sets the accession ID for a list of files in a given file path list file
function generate_accession_id {
    part_one=$(LC_ALL=C tr -dc 'abcdefghjkmnpqrstuvwxyz23456789' </dev/urandom | head -c 6)
    part_two=$(LC_ALL=C tr -dc 'abcdefghjkmnpqrstuvwxyz23456789' </dev/urandom | head -c 6)

    echo "aa-File-$part_one-$part_two"
}

if [ "$#" -ne 2 ]; then
    echo
    echo "Usage: $0 filePathListFile user"
    exit 1
fi

listFile=$1
user=$2

# Check if the file path list file exists
if [ ! -f "$listFile" ]; then
    echo "File path list file not found!"
    exit 1
fi

echo listFile = $listFile
echo user = $user

(for file in $(cat $listFile); do
    accid=$(generate_accession_id 2>/dev/null)
    echo $accid
    sda-admin file set-accession -filepath $file -user $user -accession-id $accid
done) > $listFile.accession
