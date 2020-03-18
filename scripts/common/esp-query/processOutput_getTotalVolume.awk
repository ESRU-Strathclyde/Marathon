BEGIN {
  FS="="
}

{
  if ($1=="total_volume") { 
    print $2
    exit
  }
}
