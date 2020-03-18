BEGIN {
  FS="="
}

{
  if ($1=="total_floor_area") { 
    print $2
    exit
  }
}
