# This script sums alternate columns of fresh air supply time step data.
# The two are then averaged.
# If variable "vol" is non-blank, convert to AC/h with this value
# as volume in m^3.
# Assumes first column is time, and always prints this.

{
  if (substr($1,1,1)=="#") {next}
  sum1=0.0;
  sum2=0.0;
  tog=0
  occ=0
  for (i=2;i<=NF;i++) {
    if ($i ~ /^-?[0-9]+\.?[0-9]*$/) {
      if (tog) {
        sum1+=$i
        tog=0
        occ=1
      }
      else {
        sum2+=$i
        tog=1
        occ=1
      }
    }
    else {
      if ($i=="not" || $i=="no" || $i=="invl") {i++;}
    }
  }
  if (occ) {
    if (vol) {
      print $1,((sum1+sum2)*60*60)/(2*1000*vol); 
    }
    else {
      print $1,(sum1+sum2)/2;
    }
  }
  else {
    print $1,"not_occ"
  }
}
