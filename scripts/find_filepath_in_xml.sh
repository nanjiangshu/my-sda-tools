# this script finds a file path in an XML file and prints yes or no 
if [ "$#" -ne 2 ]; then
    echo
    echo "Usage: $0 <filepath> <xml-file>"
    exit 1
fi

filepath=$1
xml_file=$2
# Check if the XML file exists
if [ ! -f "$xml_file" ]; then
    echo "XML file not found!"
    exit 1
fi
# Check if the file path exists in the XML file

newfilepath=$(echo "$filepath" | sed -E 's|^[^/]*lifescience-ri.eu/DATASET_[^/]*/||' | sed 's|\.c4gh$||')

if grep -q "$newfilepath" "$xml_file"; then
    echo "yes $filepath"
else
    echo "no $filepath"
fi