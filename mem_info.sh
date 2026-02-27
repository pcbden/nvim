#!/bin/bash

# Memory Regions Analyzer - Auto-detecting from linker script
# Usage: ./memory_regions.sh [elf_file] [map_file] [linker_script]

ELF_FILE="$1"
MAP_FILE="$2"
LINKER_SCRIPT="$3"

# Auto-detect files if not provided
if [ -z "$ELF_FILE" ]; then
    if [ -d "build" ]; then
        ELF_FILE=$(find build -name "*.elf" | head -1)
    fi
    if [ -z "$ELF_FILE" ]; then
        ELF_FILE=$(find . -maxdepth 2 -name "*.elf" | head -1)
    fi
fi

if [ -z "$MAP_FILE" ]; then
    if [ -d "build" ]; then
        MAP_FILE=$(find build -name "*.map" | head -1)
    fi
    if [ -z "$MAP_FILE" ]; then
        MAP_FILE=$(find . -maxdepth 2 -name "*.map" | head -1)
    fi
fi


# Automatically extract linker script path from .map file or fallback to find
if [ -z "$LINKER_SCRIPT" ]; then
    if [ -f "$MAP_FILE" ]; then
        LINKER_SCRIPT=$(grep -o '[^ ]*\.ld' "$MAP_FILE" | head -n1)
    fi
    if [ ! -f "$LINKER_SCRIPT" ]; then
        LINKER_SCRIPT=$(find . -name "*.ld" -o -name "*.lds" | head -n1)
    fi
fi


# Check if required files exist
if [ ! -f "$ELF_FILE" ]; then
    echo "Error: ELF file not found: $ELF_FILE"
    echo "Usage: $0 [elf_file] [map_file] [linker_script]"
    exit 1
fi

format_size() {
    local bytes=$1
    if [ "$bytes" -lt 1024 ]; then
        printf "%d B" "$bytes"
    elif [ "$bytes" -lt $((1024 * 1024)) ]; then
        awk -v b="$bytes" 'BEGIN { printf "%.3f KB", b / 1024 }'
    else
        awk -v b="$bytes" 'BEGIN { printf "%.3f MB", b / (1024 * 1024) }'
    fi
}


echo "================================================================================"
echo "                             MEMORY REGIONS"
echo "================================================================================"
printf "%-12s %-10s %-10s %-12s %-12s %-12s %-7s\n" "Region" "Start" "End" "Used" "Total" "Free" "Usage%"
echo "--------------------------------------------------------------------------"

# Function to extract memory regions from sources
get_memory_regions() {
    local regions_found=0
    
    # Method 1: Extract from MAP file if available
    if [ -f "$MAP_FILE" ]; then
        awk '
        BEGIN { in_memory = 0 }
        /^Memory Configuration/ { in_memory = 1; next }
        /^Linker script and memory map/ { in_memory = 0 }
        in_memory && /^[A-Za-z]/ && !/^Name/ && !/^----/ && NF >= 4 {
            name = $1
            origin = $2
            length = $3
            
            # Remove 0x prefix for calculation
            gsub(/^0x/, "", origin)
            gsub(/^0x/, "", length)
            
            # Convert to decimal
            cmd = "printf \"%d\" 0x" origin
            cmd | getline start_dec
            close(cmd)
            
            cmd = "printf \"%d\" 0x" length  
            cmd | getline size_dec
            close(cmd)
            
            end_dec = start_dec + size_dec
            
            printf "%s 0x%08X 0x%08X\n", name, start_dec, end_dec
            regions_found++
        }
        END { if (regions_found == 0) exit 1 }
        ' "$MAP_FILE" 2>/dev/null
        regions_found=$?
    fi
    
    # Method 2: Extract from linker script if MAP failed or not available
    if [ $regions_found -ne 0 ] && [ -f "$LINKER_SCRIPT" ]; then
        
        # Use sed and grep to extract memory regions more reliably
        sed -n '/MEMORY/,/^}/p' "$LINKER_SCRIPT" | \
        grep -E '^\s*[A-Za-z_][A-Za-z0-9_]*.*:.*ORIGIN.*LENGTH' | \
        while IFS= read -r line; do
            # Extract region name (everything before the colon, excluding parentheses)
            region_name=$(echo "$line" | sed -E 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*(\([^)]*\))?[[:space:]]*:.*/\1/')
            
            # Extract ORIGIN value
            origin_val=$(echo "$line" | sed -E 's/.*ORIGIN[[:space:]]*=[[:space:]]*([^,[:space:]]+).*/\1/')
            
            # Extract LENGTH value  
            length_val=$(echo "$line" | sed -E 's/.*LENGTH[[:space:]]*=[[:space:]]*([^,[:space:]}]+).*/\1/')
            
            # Convert origin to decimal - FIXED to handle 0x00000000 properly
            if [[ $origin_val =~ ^0x ]]; then
                start_dec=$(printf "%d" "$origin_val" 2>/dev/null || echo "0")
            else
                start_dec=$(printf "%d" "0x$origin_val" 2>/dev/null || echo "0")
            fi
            
            # Parse LENGTH with K/M suffixes
            if [[ $length_val =~ ^([0-9]+)[kK]$ ]]; then
                # Decimal with K suffix (like 128K)
                num=$(echo "$length_val" | sed 's/[kK]$//')
                size_dec=$((num * 1024))
            elif [[ $length_val =~ ^([0-9]+)[mM]$ ]]; then
                # Decimal with M suffix (like 2M)
                num=$(echo "$length_val" | sed 's/[mM]$//')
                size_dec=$((num * 1024 * 1024))
            elif [[ $length_val =~ ^0x([0-9a-fA-F]+)[kK]$ ]]; then
                # Hex with K suffix
                hex_part=$(echo "$length_val" | sed 's/[kK]$//')
                size_dec=$(($hex_part * 1024))
            elif [[ $length_val =~ ^0x([0-9a-fA-F]+)[mM]$ ]]; then
                # Hex with M suffix
                hex_part=$(echo "$length_val" | sed 's/[mM]$//')
                size_dec=$(($hex_part * 1024 * 1024))
            elif [[ $length_val =~ ^0x ]]; then
                # Pure hex - FIXED to use printf
                size_dec=$(printf "%d" "$length_val" 2>/dev/null || echo "0")
            else
                # Pure decimal
                size_dec=$((length_val))
            fi
            
            # Don't filter out regions with start address 0x00000000 - only check size
            if [[ $size_dec -gt 0 ]]; then
                end_dec=$((start_dec + size_dec))
                printf "%s 0x%08X 0x%08X\n" "$region_name" "$start_dec" "$end_dec"
            fi
        done
        
        # Return success if we processed the linker script
        return 0
    fi
    
    # Method 3: Fallback to common STM32 regions if nothing found
    if [ $regions_found -ne 0 ]; then
        cat << 'EOF'
FLASH 0x08000000 0x08200000
RAM 0x20000000 0x20050000
CCMRAM 0x10000000 0x10010000
EOF
    fi
}

# Get memory regions and process each one
temp_regions=$(mktemp)
get_memory_regions > "$temp_regions"

# Remove duplicate regions - keep only unique region names
temp_unique=$(mktemp)
awk '!seen[$1]++' "$temp_regions" > "$temp_unique"
mv "$temp_unique" "$temp_regions"

# Get section information using arm-none-eabi-size
temp_sections=$(mktemp)
arm-none-eabi-size -A -d "$ELF_FILE" > "$temp_sections" 2>/dev/null

while IFS= read -r entry; do
    # Skip comment lines
    [[ $entry =~ ^#.*$ ]] && continue
    [[ -z "$entry" ]] && continue
    
    read name start_hex end_hex <<< "$entry"
    start=$((start_hex))
    end=$((end_hex))
    total=$((end - start))
    used=0
    
    # Calculate used memory by examining sections that fall within this region
    while IFS= read -r line; do
        if [[ $line =~ ^\..*[[:space:]]+([0-9]+)[[:space:]]+([0-9]+) ]]; then
            section_name=$(echo "$line" | awk '{print $1}')
            section_size=$(echo "$line" | awk '{print $2}')
            section_addr=$(echo "$line" | awk '{print $3}')
            
            # Special handling for ITCMRAM - it rarely has sections mapped to it in typical firmware
            if [[ $name == "ITCMRAM" ]]; then
                # For ITCMRAM, only count sections that are explicitly at address 0x00000000
                if [[ $section_addr -eq 0 && $section_size -gt 0 ]]; then
                    # Verify this section is actually meant for ITCMRAM by checking if it's a code section
                    if [[ $section_name =~ ^\.(text|isr_vector) ]]; then
                        used=$((used + section_size))
                    fi
                fi
                continue
            fi
            
            # For other regions, skip sections at address 0 (debug sections, etc.)
            if [[ $section_addr -eq 0 ]]; then
                continue
            fi
            
            # Check if this section falls within our memory region
            if [[ $section_addr -ge $start && $section_addr -lt $end ]]; then
                used=$((used + section_size))
            fi
        fi
    done < "$temp_sections"
    
    # If no sections found in region (except ITCMRAM which we handled specially), try alternative method using objdump
    if [[ $used -eq 0 && $name != "ITCMRAM" ]]; then
        section_info=$(arm-none-eabi-objdump -h "$ELF_FILE" 2>/dev/null | \
                      awk -v start="$start" -v end="$end" '
                      /^[[:space:]]*[0-9]+[[:space:]]+\./ {
                          addr_hex = "0x" $5
                          size_hex = "0x" $3
                          
                          # Convert hex to decimal using printf
                          cmd = "printf \"%d\" " addr_hex
                          cmd | getline addr_dec
                          close(cmd)
                          
                          cmd = "printf \"%d\" " size_hex  
                          cmd | getline size_dec
                          close(cmd)
                          
                          if (addr_dec >= start && addr_dec < end && size_dec > 0) {
                              total_used += size_dec
                          }
                      }
                      END { print total_used + 0 }')
        used=$section_info
    fi
    
    # Ensure used doesn't exceed total (prevents overflow in free calculation)
    if [[ $used -gt $total ]]; then
        used=$total
    fi
    
    free=$((total - used))
    
    # Calculate percentage, avoiding division by zero
    if [[ $total -gt 0 ]]; then
        usage_pct=$(awk "BEGIN { printf \"%.3f\", ($used*100)/$total }")
    else
        usage_pct=0
    fi
    
    # Show all defined regions (even if unused) - now in hex format

printf "%-12s %-10s %-10s %-12s %-12s %-12s %-7s\n" \
  "$name" "$start_hex" "$end_hex" \
  "$(format_size $used)" \
  "$(format_size $total)" \
  "$(format_size $free)" \
  "$usage_pct%"

           
done < "$temp_regions"

# Clean up
rm -f "$temp_sections" "$temp_regions"

