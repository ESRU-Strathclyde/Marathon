# This script scans time step data for devation from criteria
# defined by the user.
# Assumes first column is time, and always prints this.
# This variant uses hard-coded overheating criteria from CIBSE TM52 for free-running building.
# This assumes that the second column is outdoor dry bulb temperature.
# Arguments are:
# max: zone string (liv, kit, bed, bath, WC, hall)
# min: minimum criterion
# cols: comma separated list of columns to scan
# Output:
# '-': not occupied or other n/a
# 'x': passes criteria
# [a number]: deviation from criteria

BEGIN {
  ORS=" ";
  curday=0;
  alpha=0.8;
}

{
  if (substr($1,1,1)=="#") {next}

  # Track running mean of daily mean outdoor air temperature.
  split($1,a,".");
  day=a[1];
  if (day>curday) {
    if (curday==0) {
      # TODO: more intelligent initial guess
      trm=$2+1;     
    }
    else {
      tod=tot/n;
      trm=(1-alpha)*tod + alpha*trm;
    }
    tmax=0.33*trm+21.8;
    n=0;
    tot=0.0;
    curday=day;
  }
  n++;
  tot+=$2;

  # Calculate deviation.
  print $1;
  j=2;
  for (i=3;i<=NF;i++) {
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
        dif=$i-tmax;
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
