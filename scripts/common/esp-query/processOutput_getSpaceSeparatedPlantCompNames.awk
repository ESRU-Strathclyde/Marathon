BEGIN {
  FS="="
}

{
  if ($1=="plant_comp_names") {
    gsub(/,/," ",$2)
    print $2
    exit
  }
}
