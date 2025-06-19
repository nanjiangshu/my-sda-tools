# compare checksums 

# this script compares the checksums of a filepath based on manually calculated and that is obtained from the image.xml

# format of the manually calculated checksum file:
# 01733ca8a8fa38dc4691b6706755cf7be14e09cc75a14b774391dc791bb44367  1.2.826.0.1.3680043.8.498.11405055567645907541267706263167049611.dcm.c4gh

# format of the image_checksum.txt file:
# IMAGES/IMAGE_sONgLorBsa/1.2.826.0.1.3680043.8.498.16951329567204080982037606505677017403.dcm 1388f7d988794341a00f98fc154dcd3153b48aae5842ee456067f83da598153a

if [ "$#" -ne 3 ]; then
    echo
    echo "Usage: $0  <calculated_checksum_file> <image_checksum_file> <filepath>"
    exit 1
fi

calculated_checksum_file=$1
image_checksum_file=$2
filepath=$3

basename=$(basename "$filepath" .c4gh)

# Extract the checksum from the manually calculated checksum file
calculated_checksum=$(grep "$basename" "$calculated_checksum_file" | awk '{print $1}')
if [ -z "$calculated_checksum" ]; then
    echo "Checksum not found in the manually calculated checksum file for $basename"
    exit 1
fi

# Extract the checksum from the image_checksum.txt file
newfilepath=$(echo "$filepath" | sed -E 's|^[^/]*lifescience-ri.eu/DATASET_[^/]*/||' | sed 's|\.c4gh$||')
image_checksum=$(grep "$newfilepath" "$image_checksum_file" | awk '{print $2}')
if [ -z "$image_checksum" ]; then
    echo "Checksum not found in the image checksum file for $newfilepath"
    exit 1
fi

# Compare the checksums
if [ "$calculated_checksum" = "$image_checksum" ]; then
    echo "Checksums match for $basename"
else
    echo "Checksums do not match for $basename"
    echo "Calculated checksum: $calculated_checksum"
    echo "Image checksum: $image_checksum"
fi
# Exit with status 0 if checksums match, 1 if they do not       
if [ "$calculated_checksum" = "$image_checksum" ]; then
    exit 0
else
    exit 1
fi
