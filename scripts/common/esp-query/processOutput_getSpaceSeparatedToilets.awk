BEGIN {
  FS="="
}

{
  if ($1=="number_toilets") {
    gsub(/,/," ",$2)
    print $2
    exit
  }
}
