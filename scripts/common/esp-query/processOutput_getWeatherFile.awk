BEGIN {
  FS="=";
}

{
  if ($1=="weather_file") { 
    print $2;
    exit;
  }
}
