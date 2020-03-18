BEGIN {
  FS="="
}

{
  if ($1=="QA_report") { 
    print $2
    exit
  }
}
