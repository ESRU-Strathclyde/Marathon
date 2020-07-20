# Aggregates all values in a timestep column file.
# Assumes first column is time, and ignores this.

BEGIN {
  total=0.0;
}

{
  for (i=2;i<=NF;i++) {
    total+=$i;
  }
}

END {
  print total;
}