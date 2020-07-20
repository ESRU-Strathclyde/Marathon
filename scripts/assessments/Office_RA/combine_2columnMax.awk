# This script takes the maximum of each pair of columns
# for each time step.
# Assumes first column is time, and always prints this.

BEGIN {
  ORS=" ";
}

{
  if (substr($1,1,1)=="#") {next}
  print $1
  tog=0
  for (i=2;i<=NF;i++) {
    if ($i ~ /^-?[0-9]+\.?[0-9]*$/) {
      if (tog) {
        if (v) {
          if ($i>v) {print $i}
          else {print v}
        }
        else {print $i}
        tog=0
      }
      else {
        v=$i
        tog=1
      }
    }
    else {
      if ($i=="not" || $i=="no" || $i=="invl") {i++;}
      if (tog) {
        if (v) {print v}
        else {print "not_occ"}
        tog=0
      }
      else {
        v=""
        tog=1
      }
    }
  }
  print "\n"
}
