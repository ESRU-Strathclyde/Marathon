BEGIN {
  FS="="
}

{
  if ($1=="number_printers") {
    gsub(/,/," ",$2)
    print $2
    exit
  }
}
