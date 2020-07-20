BEGIN {
  FS="="
}

{
  if ($1=="number_photocopy") {
    gsub(/,/," ",$2)
    print $2
    exit
  }
}
