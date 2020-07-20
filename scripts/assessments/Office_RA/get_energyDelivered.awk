# This script gets the total sensible heating per m2
# from the "energy delivered" ESP-r res output.

# Start from line 8, then continue until we get to a blank line.
# Next one should be the one we want.

BEGIN {
  l=0;
  active=0;
}

{
  l++;
  if (l<8) {next;}
  # Strip whitespace.
  gsub(/^[ \t]+|[ \t]+$/,"");
  if ($0 == "") {active=1;}
  else if (active) {
    print $3
    exit
  }
}
