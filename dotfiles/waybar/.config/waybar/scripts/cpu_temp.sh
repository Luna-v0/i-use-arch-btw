read -r used_mb total_mb <<< $(free -m | awk '/Mem:/ {print $3, $2}')

# Convert to GiB (rounded up)
used_gb=$(( (used_mb + 1023) / 1024 ))
total_gb=$(( (total_mb + 1023) / 1024 ))
ram_usage="${used_gb}/${total_gb} GB"

# CPU usage
cpu_usage=$(mpstat 1 1 | awk '/Average/ {print 100 - $NF}')


# CPU temp rounded
if [[ $(hostname) == "fantasy2" ]]; then
    cpu_temp=$(sensors | awk '/k10temp-pci-00c3/,/^$/' | grep 'Tctl' | awk '{printf("%d°C", $2)}')
else
    cpu_temp=$(sensors | awk '/coretemp-isa-0000/,/^$/' | grep 'Package id 0' | awk '{printf("%d°C", $4)}')
fi
echo "$ram_usage | CPU $cpu_usage% | $cpu_temp"

