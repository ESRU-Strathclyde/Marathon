BEGIN {
  FS="="
}

{
  if ($1=="FMU_names") {
    gsub(/,/," ",$2)
    print $2
    exit
  }
}
