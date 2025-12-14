#!/bin/bash
# Compare file hashes between two directories

if [ $# -ne 2 ]; then
    echo "Usage: $0 <dir1> <dir2>"
    exit 1
fi

dir1="$1"
dir2="$2"

if [ ! -d "$dir1" ] || [ ! -d "$dir2" ]; then
    echo "Error: Both arguments must be valid directories"
    exit 1
fi

# Find all files in dir1 and compare with dir2
total_savings=0

while IFS= read -r file; do
    filename=$(basename "$file")
    
    # Check if file exists in dir2
    if [ -f "$dir2/$filename" ]; then
        hash1=$(sha256sum "$file" | awk '{print $1}')
        hash2=$(sha256sum "$dir2/$filename" | awk '{print $1}')
        
        if [ "$hash1" = "$hash2" ]; then
            filesize=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
            echo "✓ $filename - MATCH ($(numfmt --to=iec-i --suffix=B $filesize 2>/dev/null || echo $filesize bytes))"
            total_savings=$((total_savings + filesize))
        fi
    fi
done < <(find "$dir1" -type f)

echo ""
echo "Total deduplication savings: $(numfmt --to=iec-i --suffix=B $total_savings 2>/dev/null || echo $total_savings bytes)"

exit 0