# This script scans time step deviation data.
# Failure criteria must be specified on the command line,
# otherwise none will not be checked.
# Input:
# '-': not occupied or other n/a
# 'x': passes criteria
# [a number]: deviation from criteria
# Arguments are:
# max: limit of allowable positive deviation
# min: limit of allowable negative deviation
# met: name of metric for description messages (first letter should be capitalised)
# unit: units for description messages
# Output:
# exit code is result
# 0 = no problem
# 1 = criteria violated
# Outputs a string describing all failure instances.

BEGIN {
  fail=0;
}

{
  if (substr($1,1,1)=="#") {next}

  # Absolute deviation.
  if ($i!="x" && $i!="-") {
    if (max) {
      if ($i>max) {
        fail=1;
        desc=met" exceeded the upper limit by more than "max" "unit".";
      }
    }
    if (min) {
      if ($i<min) {
        fail=1;
        desc=met" exceeded the lower limit by more than "min" "unit".";
      }
    }
  }
}

END {
  print desc
  if (fail) {exit 1}
}
