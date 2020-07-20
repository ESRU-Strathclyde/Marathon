BEGIN {
  FS="="
}

{
  if ($1=="is_building") { 
    print $2
    exit
  }
}
