# This script checks a value against criteria.
# Output:
# '-': not occupied or other n/a
# 'x': passes criteria
# [a number]: deviation from criteria
# Arguments are:
# max: maximum criterion
# min: minimum criterion
{
  if ($i ~ /^-?[0-9]+\.?[0-9]*$/) {
    if (max) {
      dif=$i-max;
      if (dif>0) {
          print dif;
          exit
      }
    }
    if (min) {
      dif=min-$i;
      if (dif>0) {
          print -dif;
          exit
      }
    }
    print "x";
  }
  else {
    print "-";
  }
}
