# This script scans time step data for devation from criteria
# defined by the user.
# Assumes first column is time, and always prints this.
# Output:
# '-': not occupied or other n/a
# 'x': passes criteria
# [a number]: deviation from criteria
# Arguments are:
# max: maximum criterion
# min: minimum criterion
# cols: comma separated list of columns to scan

BEGIN {
  ORS=" ";
}

{
  if (substr($1,1,1)=="#") {next}
  print $1;
  j=1;
  for (i=2;i<=NF;i++) {
    if (cols) {
      j++;
      regex="(^|,)"j"($|,)";
      if (cols !~ regex) {
        if ($i=="not" || $i=="no" || $i=="invl") {i++;}
        continue
      }
    }
    if ($i ~ /^-?[0-9]+\.?[0-9]*$/) {
      if (max) {
        dif=$i-max;
        if (dif>0) {
          print dif;
          continue
        }
      }
      if (min) {
        dif=min-$i;
        if (dif>0) {
          print -dif;
          continue
        }
      }
      print "x";
    }
    else {
      if ($i=="not" || $i=="no" || $i=="invl") {i++;}
      print "-";
    }
  }
  print "\n";
}
