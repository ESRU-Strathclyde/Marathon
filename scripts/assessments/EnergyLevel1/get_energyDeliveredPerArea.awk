BEGIN { 
  i_line=0;
  active=0;
  ORS=" ";
}

{
  i_line++;
  if ( i_line > 7 ) {active=1}
  if ( active ) {
    if ( $1 == "All" ) {exit}
    print $4;
  }
}