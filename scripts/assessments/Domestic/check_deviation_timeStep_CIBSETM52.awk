# This script scans time step deviation data against CIBSE TM52 overhaeting criteria.
# Note that this does not scan for discomfort due to cold;
# use check_deviation_timeStep.awk for this.
# Input:
# '-': not occupied or other n/a
# 'x': passes criteria
# [a number]: deviation from criteria
# Arguments are:
# tsph: number of time steps per hour
# col: column to scan
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
  dayfail=0;
  fail=0;
  desc="";
  we=0.0;
  if (col=="") {col=2;}
  output="";
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

    # Criterion 1: hours of exceedance.
    # Only applies May to September.
    if (day>=121 && day<=273) {      
      if ($i=="x") {occ_tsteps++;}
      else if ($i!="-") {
        occ_tsteps++;
        if ($i>=1.0) {dev_tsteps++;}
      }
    }

    # Criterion 2: daily weighted exceedance.
    if (daychange) {
      we=we/tsph;
      if (we>6) {
        fail=1;
        desc=desc"Daily weighted temperature exceedance on "strftime("%B %d",(day-1)*24*60*60)" is greater than 6.\n";
      }
      we=0.0;
    }
    if ($i!="x" && $i!="-") {
      if ($i>=0.0) {we+=$i;}
    }

    # Criterion 3: upper limit temperature.
    if ($i!="x" && $i!="-") {
      if ($i>=4.0) {
        print "fail3"
        fail=1;
        dayfail=1
        if (daychange && dayfail) {
          desc=desc"Temperature exceeded the upper limit by more than 4 C on "strftime("%B %d",(day-1)*24*60*60)".\n";
          dayfail=0;
        }
      }
    }
  }
}

END {
  if (occ_tsteps>0) {
    if (dev_tsteps/occ_tsteps*100 > 3.0) {
      fail=1;
      desc=desc"Temperature exceedance occurs for more than 3 % of occupied hours.";
    }
  }
  print desc
  if (fail) {exit 1}
}
