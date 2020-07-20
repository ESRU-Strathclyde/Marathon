# This script scans time step data for devation from criteria
# defined by the user.
# Assumes first column is time, and always prints this.
# Output:
# '-': not occupied or other n/a
# 'x': passes criteria
# [a number]: deviation from criteria
# Arguments are:
# max: maximum criterion
# maxlist: comma separated list of the same length as cols
#      in this case a different value of max will be applied to each column
#      will override max if given
# min: minimum criterion
# cols: comma separated list of columns to scan

BEGIN {
  ORS=" ";
  split(cols,arr_cols,",");
  if (maxlist) {split(maxlist,arr_max,",")}
}

{
  if (substr($1,1,1)=="#") {next}
  print $1;
  j=1;
  for (i=2;i<=NF;i++) {
    if (cols) {
      j++;
      ic=1;
      found=0;
      for (ic in arr_cols) {
        if (arr_cols[ic]==j) {
          found=1;
          if (maxlist) {max=arr_max[ic]}
        }
      }
      if (!found) {
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
