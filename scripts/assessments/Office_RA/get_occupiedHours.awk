# This awk script checks occupied hours for all zones. Output is 
# parsed by the calling bash script to extract individual pieces of information.

BEGIN {
  count=0
}

# Start at line 9, continue until blank line is found.
{
  if (NR >= 9) {
    if ($1 == "") {exit}
    count++
    print count,$7
  }
}
