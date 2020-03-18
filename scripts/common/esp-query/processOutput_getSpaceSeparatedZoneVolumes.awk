BEGIN {
  FS="="
}

{
  if ($1=="zone_volumes") {
    gsub(/,/," ",$2)
    print $2
    exit
  }
}
