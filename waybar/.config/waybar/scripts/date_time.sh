#!/bin/bash

# Output JSON with time as text and date/day as tooltip
time=$(date +"%H:%M")
date_day=$(date +"%d/%m - %a")

echo "{\"text\": \"$time\", \"tooltip\": \"$date_day\"}"
