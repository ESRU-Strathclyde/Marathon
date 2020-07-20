# This script converts time step data using multiplication
# factor(s) supplied on the command line.
# Assumes first column is time, and always prints this.
# Arguments are:
# mult: multiplication factor
# multlist: comma separated list of multipliers for each data column

BEGIN {
  # Default mult=1
  if (mult=="" && multlist=="") {mult=1;}
  else if (multlist != "") {split(multlist,arr_mult,",");}
  ORS=" ";
}

{
  if (substr($1,1,1)=="#") {next}
  print $1;
  j=0;
  for (i=2;i<=NF;i++) {
    j++;
    if ($i ~ /^-?[0-9]+\.?[0-9]*$/) {
      if (mult) {
        print $i*mult;
      }
      else if (multlist) {
        print $i*arr_mult[j];
      }
    }
    else {
      if ($i=="not" || $i=="no" || $i=="invl") {i++;}
      print "-";
    }
  }
  print "\n";
}
