BEGIN {
  FS="="
}

{
  if ($1=="plant_network") { 
    print $2
    exit
  }
}
