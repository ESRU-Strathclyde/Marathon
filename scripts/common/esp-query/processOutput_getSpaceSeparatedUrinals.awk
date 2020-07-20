BEGIN {
  FS="="
}

{
  if ($1=="number_urinals") {
    gsub(/,/," ",$2)
    print $2
    exit
  }
}
