BEGIN {
  FS="="
}

{
  if ($1=="plant_components") {
    gsub(/,/," ",$2)
    print $2
    exit
  }
}
