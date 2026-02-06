#!/bin/bash
# Deduplicate identical files in /opt, replace duplicates with symlinks

declare -A file_hashes
declare -A file_paths
total_saved=0

while IFS= read -r file; do
    hash=$(sha256sum "$file" | awk '{print $1}')
    file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
    
    if [[ -v file_hashes[$hash] ]]; then
        original="${file_hashes[$hash]}"
        rm "$file"
        ln -s "$original" "$file"
        echo "Symlinked $(basename $file) -> $(basename $original) (saved $(numfmt --to=iec-i --suffix=B $file_size 2>/dev/null || echo $file_size bytes))"
        ((total_saved += file_size))
    else
        file_hashes[$hash]="$file"
    fi
done < <(find /opt -type f ! -path "*/.*" 2>/dev/null)

# Convert bytes to human-readable format
if command -v numfmt &> /dev/null; then
    saved_formatted=$(numfmt --to=iec-i --suffix=B $total_saved)
else
    # Fallback: simple conversion for macOS
    if (( total_saved > 1048576 )); then
        saved_formatted="$(printf '%.2f' $(echo "scale=2; $total_saved / 1048576" | bc)) MB"
    elif (( total_saved > 1024 )); then
        saved_formatted="$(printf '%.2f' $(echo "scale=2; $total_saved / 1024" | bc)) KB"
    else
        saved_formatted="$total_saved bytes"
    fi
fi

echo ""
echo "=== Deduplication Complete ==="
echo "Total space saved: $saved_formatted"
