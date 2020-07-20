BEGIN {
  FS="="
}

{
  if ($1=="number_showers") {
    gsub(/,/," ",$2)
    print $2
    exit
  }
}
