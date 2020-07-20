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
# perc: allowable deviation as percentage of occupied hours
#       will consider positive deviation if max is defined,
#       negative deviation if min is defined,
#       aggregate if both are defined.
# percmax: positive deviation below this will not count towards perc
#          default - 0.0
# percmin: negative deviation above this will not count towards perc
#          default - 0.0
# col: column to scan
# met: name of metric for description messages (first letter should be capitalised)
# unit: units for description messages
# notocc: if true (none-empty), will report perc against all hours
#         instead of occupied hours.
# Output:
# exit code is result
# 0 = no problem
# 1 = criteria violated
# Outputs a string describing all failure instances.

BEGIN {
  occ_tsteps=0;
  dev_tsteps=0;
  curday=1;
  daychange=0;
  dayfailhot=0;
  dayfailcold=0;
  if (percmax=="") {percmax=0.0}
  if (percmin=="") {percmin=0.0}
  fail=0;
}

{
  if (substr($1,1,1)=="#") {next}

  for (i=2;i<=NF;i++) {
    if (col != i) {
      continue
    }

    split($1,a,".");
    day=a[1];
    if (day>curday) {
      daychange=1;
      curday=day;
    }
    else {
      daychange=0;
    }

    # Percentage deviation.     
    if ($i=="x") {occ_tsteps++;}
    else if ($i!="-") {
      occ_tsteps++;
      if (max) {
        if ($i>percmax) {dev_tsteps++;}
      }
      if (min) {
        if ($i<percmin) {dev_tsteps++;}
      }
    }

    # Absolute deviation.
    if ($i!="x" && $i!="-") {
      if (max) {
        if ($i>max) {
          fail=1;
          dayfailhot=1;
          if (daychange && dayfailhot) {
            desc=desc met" exceeded the upper limit by more than "max" "unit" on "strftime("%d %B",(day-1)*24*60*60)".\n";
            dayfailhot=0;
          }
        }
      }
      if (min) {
        if ($i<min) {
          fail=1;
          dayfailcold=1;
          if (daychange && dayfailcold) {
            desc=desc met" exceeded the lower limit by more than "(-min)" "unit" on "strftime("%d %B",(day-1)*24*60*60)".\n";
            dayfailcold=0;
          }
        }
      }
    }
  }
}

END {
  if (occ_tsteps>0) {
    if (dev_tsteps/occ_tsteps*100 > perc) {
      fail=1;
      s="exceedance";
      if (notocc) {s2="the time"}
      else {s2="occupied hours"}
      desc=desc met" "s" occurs for more than "perc" % of "s2".";
    }
  }
  print desc
  if (fail) {exit 1}
}
