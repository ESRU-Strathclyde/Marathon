#! /bin/bash

# Resilience test - energy level 1
# Version 0.1 of Sep 2019.

# Set up defaults.
building=""
results_file="simulation_results"
start="1 1"
finish="31 12"
year="2000"
timesteps=1
startup=5
preset=""
tmp_dir="./tmp"
report_final="./report.pdf"
information=false
verbose=false
preamble_file=""
do_training=true

# Get paths to call the various other scripts used by this program.
script_dir="$(dirname "$(readlink -f "$0")")"
common_dir="$script_dir/../../common"

# Parse command line.
while getopts ":hvf:p:t:s:d:r:j:P:U" opt; do
  case "$opt" in
    h) information=true;;
    v) verbose=true;;
    f) results_file="$OPTARG";;
    p) start="$(echo "$OPTARG" | awk -v FS='_' -v OFS=' ' '{print $1,$2}')"
       finish="$(echo "$OPTARG" | awk -v FS='_' -v OFS=' ' '{print $3,$4}')"
       year="$(echo "$OPTARG" | awk -v FS='_' -v OFS=' ' '{print $5}')";;
    t) timesteps="$OPTARG";;
    s) preset="$OPTARG";;
    d) tmp_dir="$OPTARG";;
    r) report_final="$OPTARG";;
    j) JSON="$OPTARG";;
    P) preamble_file="$OPTARG";;
    U) do_training=false;;
    \?) echo "Error: unknown option -$OPTARG. Use option -h for help." >&2
        exit 107;;
    :) echo "Error: option -$OPTARG requires and argument." >&2
       exit 107;;
  esac
done
shift $((OPTIND-1))
building="$1"

if "$information" ; then
  echo
  echo " Usage: ./EnergyLevel1.sh [OPTIONS] model-cfg-file"
  echo
  echo " ESP-r implementation of the Ebergy Level 1 resilience test."
  echo
  echo " Command line options: -h"
  echo "                          display help text and exit"
  echo "                          default: off"
  echo "                       -v"
  echo "                          verbose output to stdout"
  echo "                          default: off"
  echo "                       -f results-file"
  echo "                          file name of the simulation results (output from BPS), without extension"
  echo "                          simulation results will be called [results-file].res"
  echo "                          mass flow results will be called [results-file].mfr"
  echo "                          CFD results will be called [results-file].dfr"
  echo "                          default: ./simulation_results"
  echo "                       -p start-day_start-month_finish-day_finish-month_year"
  echo "                          start and end days of simulation period"
  echo "                          default: 1_1_31_12_2000"
  echo "                       -t timesteps"
  echo "                          number of timesteps per hour"
  echo "                          default: 1"
  echo "                       -s simulation-preset"
  echo "                          name of the simulation preset to be run"
  echo "                          default:"
  echo "                       -d temporary-files-directory"
  echo "                          directory into which temporary files will be placed"
  echo "                          default: ./tmp"
  echo "                       -r pdf-report"
  echo "                          file name of the pdf report"
  echo "                          default: ./report.pdf"
  echo "                       -j JSON-file"
  echo "                          file name of the json report"
  echo "                          default: ./data.json"
  echo "                       -P preamble-file"
  echo "                          text in this file will be placed in the report before analysis outcomes"
  echo "                          default: none"
  echo "                       -U" 
  echo "                          Do not simulate and use existing results libraries"
  echo "                          default: off"
  echo
  echo " If a simulation preset is defined and present, it will override the period and time steps parameters."
  echo " If the simulation preset is not found this will not cause a fatal error; the PAM will use user-defined"
  echo " or default period and time steps for the simulation."

  exit 0
fi

# Check model exists.
if ! [ -f "$building" ]; then
  echo "Error: model not found." >&2
  exit 107
fi

# Set criteria.
ED_criteria=40 # kWh/m2

# Check simluation period and timesteps.
check="$(echo "$start" | awk '{ if ($0 ~ /^[0-9]+ +[0-9]+$/) {print "yes"} }')"
if [ "$check" != "yes" ]; then
  echo "Error: invalid simulation start date." >&2
  exit 107
fi
check="$(echo "$finish" | awk '{ if ($0 ~ /^[0-9]+ +[0-9]+$/) {print "yes"} }')"
if [ "$check" != "yes" ]; then
  echo "Error: invalid simulation finish date." >&2
  exit 107
fi
check="$(echo "$timesteps" | awk '{ if ($0 ~ /^[0-9]+$/) {print "yes"} }')"
if [ "$check" != "yes" ]; then
  echo "Error: invalid number of timesteps per hour." >&2
  exit 107
fi

# Check preamble file exists.
if ! [ "X$preamble_file" == "X" ]; then
  if ! [ -f "$preamble_file" ]; then
    echo "Error: preamble file not found." >&2
    exit 107
  fi
fi



if $verbose; then echo "***** EnergyLevel1 start"; fi

# Test if tmp directory exists.
if [ ! -d "$tmp_dir" ]; then
  if $verbose; then echo " Temporary directory \"$tmp_dir\" not found, attempting to create....."; fi
  mkdir "$tmp_dir"
  if [ -d "$tmp_dir" ]; then
    if $verbose; then echo " .....done."; fi
  else
    if $verbose; then echo ".....failed."; fi
    echo "Error: could not create temporary files directory." >&2
    exit 201
  fi
#else
#  rm -f $tmp_dir/*
fi

# Create progress file.
echo '2' > "$tmp_dir/progress.txt"

# ESP-r seems to have problems if locations have a dot in
# front of them; check for this and remove it.
if [ "${results_file:0:2}" == "./" ]; then
  results_file="${results_file:2}"
fi
if [ "${tmp_dir:0:2}" == "./" ] && ! [ "$tmp_dir" == "./" ]; then
  tmp_dir="${tmp_dir:2}"
fi

# Currently, res asks a question if the cfg file is not in the directory from
# which it is called. Unless this is accounted for, it will break
# scripted results recovery if it happens. We get around this by forcing
# res to ask the question. So we need to check if the cfg file is in
# the local directory; if it is, we need go up one directory level when
# invoking res.
# TODO - This is a pain in the ass, and should probably be disabled in
# script mode.
# Also need to do this for bps so the library knows where to look for the
# model config file.
up_one=""
building_base="$(basename "$building")"
building_dir="$(dirname "$building")"
if [ "$building_base" == "$building" ] || [ "./$building_base" == "$building" ]; then
  up_one="${PWD##*/}"
fi

report="$tmp_dir/report.tex"



# *** CHECK MODEL ***

# Get model reporting variables, check values.
"$common_dir/esp-query/esp-query.py" -o "$tmp_dir/query_results.txt" "$building" "number_zones" "zone_control" "zone_names" "weather_file" "afn_network" "CFD_domains"

if [ "$?" -ne 0 ]; then
  echo "Error: model reporting script failed." >&2
  exit 101
fi

# Check number of zones.
number_zones="$(awk -f "$common_dir/esp-query/processOutput_getNumZones.awk" "$tmp_dir/query_results.txt")"
if [ "X$number_zones" == "X" ] || [ "$number_zones" -eq 0 ]; then
  echo "Error: no thermal zones found in this model." >&2
  exit 102
fi

# Assemble array of zone indices.
i=0
while [ "$i" -lt "$number_zones" ]; do
  array_zone_indices[i]="$i"
  ((i++))
done

# Assemble array of zone names.
zone_names="$(awk -f "$common_dir/esp-query/processOutput_getSpaceSeparatedZoneNames.awk" "$tmp_dir/query_results.txt")"
array_zone_names=($zone_names)

# Check zone control.
zone_control="$(awk -f "$common_dir/esp-query/processOutput_getZoneControl.awk" "$tmp_dir/query_results.txt")"
if [ "$zone_control" == "0" ]; then
  echo "Error: no heating or cooling detected in this model." >&2
  exit 205
fi

# Check weather file.
weather_file="$(awk -f "$common_dir/esp-query/processOutput_getWeatherFile.awk" "$tmp_dir/query_results.txt")"
if [ ! -f "$building_dir/$weather_file" ]; then
  echo "Error: weather file referenced in cfg file not found." >&2
  exit 101
fi

# Check for afn network.
afn_network="$(awk -f "$common_dir/esp-query/processOutput_getAFNnetwork.awk" "$tmp_dir/query_results.txt")"
if [ "X$afn_network" == "X" ]; then
  is_afn=false
else
  is_afn=true
fi

# Check for CFD domains.
CFD_domains="$(awk -f "$common_dir/esp-query/processOutput_getSpaceSeparatedCFDdomains.awk" "$tmp_dir/query_results.txt")"
array_CFD_domains=($CFD_domains)
is_CFD=false
is_CFDandMRT=false
CFDdomain_count=0
j=0
for i in "${array_zone_indices[@]}"; do
  n="${array_CFD_domains[i]}"
  if [ "$n" -gt 1 ]; then
    is_CFD=true
    ((CFDdomain_count++))
#    CFD_start_hour='1.0'
#    CFD_finish_hour='24.99'
    CFD_start_hour='6.0'
    CFD_finish_hour='20.99'
  fi
done

# Get results file location, simulation period, timesteps and startup days if a simulation preset is defined.
sim_results_preset=""
mf_results_preset=""
cfd_results_preset=""
if ! [ "X$preset" == "X" ]; then

# Check if simulation preset exists. If it doesn't, fall back on default values.
  preset_check="$(awk -v preset="$preset" -f "$script_dir/check_simPreset_exists.awk" "$building")"
  if  [ "$preset_check" == "0" ]; then
    echo "Warning: simulation preset \"$preset\" not found, using default simulation setup."
    preset=""

  else
    sim_results_preset="$(awk -v mode="$preset_check" -v preset="$preset" -f "$script_dir/get_simPreset_resFile.awk" "$building")"
    if [ "X$sim_results_preset" == "X" ]; then
      echo "Error: could not retrieve simulation results library name." >&2
      exit 202
    fi
    if $is_afn; then
      mf_results_preset="$(awk -v mode="$preset_check" -v preset="$preset" -f "$script_dir/get_simPreset_mfrFile.awk" "$building")"
      if [ "X$mf_results_preset" == "X" ]; then
        echo "Error: could not retrieve mass flow results library name." >&2
        exit 202
      fi
    fi
    if $is_CFD; then
      cfd_results_preset="$(awk -v mode="$preset_check" -v preset="$preset" -f "$script_dir/get_simPreset_dfrFile.awk" "$building")"
      if [ "$cfd_results_preset" == "error" ] || [ "X$cfd_results_preset" == "X" ]; then
        echo "Error: invalid simulation preset - old format." >&2
        exit 202
      fi
      cfd_period_preset="$(awk -v mode="$preset_check" -v preset="$preset" -f "$script_dir/get_simPreset_dfrPeriod.awk" "$building")"
      if [ "$cfd_period_preset" == "error" ]; then
        echo "Error: invalid simulation preset - old format." >&2
        exit 202
      fi
    fi
    period="$(awk -v mode="$preset_check" -v preset="$preset" -f "$script_dir/get_simPreset_period.awk" "$building")"
    start="$(expr "$period" : '\([0-9]* [0-9]* \)')"
    start="${start:0:-1}"
    finish="$(expr "$period" : '.*\( [0-9]* [0-9]*\)')"
    finish="${finish:1}"
    timesteps="$(awk -v mode="$preset_check" -v preset="$preset" -f "$script_dir/get_simPreset_timesteps.awk" "$building")"
    startup="$(awk -v mode="$preset_check" -v preset="$preset" -f "$script_dir/get_simPreset_startup.awk" "$building")"

# Check startup is at least 3 days.
    if [ "$startup" -lt 3 ]; then
      echo "Error: invalid simulation preset - startup is less than 3 days." >&2
      exit 202
    fi
  fi

# If running with a simulation preset, and not in the cfg directory,
# bps will place the results libraries in your home directory.
  sim_results_preset=~/"$(basename "$sim_results_preset")"

# This is not true of the mass flow results library.
#  if $is_afn; then mf_results_preset=~/"$(basename "$mf_results_preset")"; fi
  if $is_CFD; then cfd_results_preset=~/"$(basename "$cfd_results_preset")"; fi
fi

# Set results library names.
sim_results="${results_file}.res"
if $is_afn; then mf_results="${results_file}.mfr"; fi
if $is_CFD; then cfd_results="${results_file}.dfr"; fi




# *** SIMULATE ***

# Set up paths.
if [ "X$up_one" == "X" ]; then
  building_tmp="$building"
  building_dir_tmp="$building_dir"
  tmp_dir_tmp="$tmp_dir"
  sim_results_tmp="$sim_results"
  mf_results_tmp="$mf_results"
  cfd_results_tmp="$cfd_results"
  weather_file_tmp="$building_dir/$weather_file"
else
  cd ..
  building_tmp="$up_one/$building"
  building_dir_tmp="$(dirname "$building_tmp")"
  tmp_dir_tmp="$up_one/$tmp_dir"
  sim_results_tmp="$up_one/$sim_results"
  mf_results_tmp="$up_one/$mf_results"
  cfd_results_tmp="$up_one/$cfd_results"
  if [ "${weather_file:0:1}" == '/' ]; then
    weather_file_tmp="$weather_file"
  else
    weather_file_tmp="$building_dir_tmp/$weather_file"
  fi
fi

if $do_training; then

  mkdir "$tmp_dir_tmp/indra"

  # Create ASCII version of weather file. 
  if ! clm -file "$weather_file_tmp" -act bin2asci silent "$tmp_dir_tmp/indra/weather.txt"; then
    echo 'Error: failed to create ASCII version of weather file referenced in cfg file.'
    exit 101
  fi

  # Train indra to the referenced climate file.
  if ! python3 "$common_dir/SyntheticWeather/indra.py" --train 1 --station_code 'marathon' --n_samples 50 --path_file_in "$tmp_dir_tmp/indra/weather.txt" --path_file_out "$tmp_dir_tmp/indra/weather_syn.txt" --file_type 'espr' --store_path "$tmp_dir_tmp/indra"; then
    echo 'Error: failed to train indra.'
    exit 101
  fi

fi

# Update progress file.
echo '3' > "$tmp_dir_tmp/progress.txt"

# Make sure there is no existing results library or ACC-actions file. 
# Suppress output in case there isn't to prevent chatter.
rm -f "$sim_results_tmp" > /dev/null
if $is_afn; then rm -f "$mf_results_tmp" > /dev/null; fi
if $is_CFD; then rm -f "$cfd_results_tmp" > /dev/null; fi
rm -f "$building_dir_tmp"/ACC-actions_*.rec > /dev/null
rm -f "$building_dir_tmp"/cfd3dascii_* > /dev/null

# Update simulation year in cfg file.
sed -i -e 's/\*year *[0-9]*/*year '"$year"'/' "$building_tmp"

if $verbose; then
  echo
  echo " Model: $building"
  echo " Simulation results: $results_file"
  echo " Report: $report_final"
  echo " JSON file: $JSON"
  if [ "X$preset" = "X" ]; then
    echo " Analysis period from $start to $finish with $timesteps timesteps per hour"
  else
    echo " Analysis defined by simulation preset \"$preset\""
  fi
  echo
  echo " Simulations commencing, please wait ....."
  echo
fi

# Do 50 runs, each with different weather.
for i_run in $(seq 1 50); do

  if $verbose; then echo "Run $i_run ..."; fi

  # Generate weather.
  if ! python3 "$common_dir/SyntheticWeather/indra.py" --train 0 --station_code 'marathon' --path_file_in "$tmp_dir_tmp/indra/weather.txt" --path_file_out "$tmp_dir_tmp/indra/weather_syn.txt" --file_type 'espr' --store_path "$tmp_dir_tmp/indra"; then
    echo "Error: failed to generate weather file for run $i_run."
    exit 101
  fi
  mv $tmp_dir_tmp/indra/weather_syn.txt "$building_dir_tmp/../dbs/weather_syn.txt"

  # Replace weather file reference in cfg file.
  sed -i -e 's/*stdclm/*clm/' "$building_tmp"
  sed -i -e 's/^\*\(std\)*clm .*$/*clm ..\/dbs/weather_syn.txt\/' "$building_tmp"

  if ! [ "X$preset" == "X" ]; then
    bps_script=""
    bps -mode script -file "$building_tmp" -p "$preset" silent > "$tmp_dir_tmp/bps.out"

    mv "$sim_results_preset" "$sim_results_tmp"
    if $is_afn; then
      mv "$mf_results_preset" "$mf_results_tmp"
    fi
    if $is_CFD; then
      mv "$cfd_results_preset" "$cfd_results_tmp"
    fi
  else
    bps_script="
c
${sim_results_tmp}"
    if $is_afn; then
      bps_script="$bps_script
${mf_results_tmp}"
    fi
    if $is_CFD; then
      bps_script="$bps_script
${cfd_results_tmp}"
    fi
    bps_script="$bps_script
${start}
${finish}
${startup}
${timesteps}"
    if [ "$timesteps" -gt 1 ]; then
      bps_script="$bps_script
n"
    fi
    if $is_CFD; then
  # Run CFD for whole period.
      bps_script="$bps_script
y
${start}
${finish}
${CFD_start_hour}
${CFD_finish_hour}"

  # # Disable CFD for the initial simulation.
  #     bps_script="$bps_script
  # n"
    fi
    bps_script="$bps_script
s
"
    if $is_ucn; then
      bps_script="$bps_script
d
-"
    fi
    bps_script="$bps_script
PAM simulation
y
y
-
-
"

    echo "$bps_script" > "$tmp_dir_tmp/bps_script.trace"

    bps -mode script -file "$building_tmp" > "$tmp_dir_tmp/bps.out" <<~
${bps_script}
~
  fi

  if ! [ "X$up_one" == "X" ]; then
    cd "$up_one" || exit 1
  fi

  # Check error code and existence of results libraries.
  if [ "$?" -ne 0 ]; then
    echo "Error: simulation failed, please check model manually." >&2
    exit 104
  fi

  if ! [ -f "$sim_results" ]; then
    echo "Error: simulation failed, please check model manually." >&2
    exit 104
  fi

  if $is_afn && ! [ -f "$mf_results" ]; then
    echo "Error: simulation failed, please check model manually." >&2
    exit 104
  fi

  if $is_CFD && ! [ -f "$cfd_results" ]; then
    echo "Error: simulation failed, please check model manually." >&2
    exit 104
  fi



  # *** EXTRACT RESULTS ***

  # Update progress file.
  echo '4' > "$tmp_dir/progress.txt"

  if ! [ "X$up_one" == "X" ]; then
    cd .. || exit 1
  fi

  # Define res commands.

  # Get heat delivered per zone.
  res_script="
d
>
$tmp_dir_tmp/energy_delivered

f
>
-
-
"

  echo "$res_script" > "$tmp_dir_tmp/res_script.trace"

  # Run res.
  res -mode script -file "$sim_results_tmp" > "$tmp_dir_tmp/res.out" <<~
${res_script}
~



  # *** POST PROCESSING ***

  # Update progress file.
  echo '5' > "$tmp_dir_tmp/progress.txt"

  # Get energy delivered per unit area for each zone.
  ED="$(awk -f "$script_dir/get_energyDeliveredPerArea" "$tmp_dir_tmp/energy_delivered")"
  echo "$ED" > "$tmp_dir_tmp/ED.trace"

  # Get deviation.
  deviation="$(echo "$ED" | awk -v criteria="$ED_criteria" -f "$script_dir/get_deviation")"
  echo "$deviation" > "$tmp_dir_tmp/deviation_opt.trace"

  # Get severity.
  PTD="$(echo "$deviation" | awk -f "$script_dir/get_percentTimeDiscomfort.awk")"
  echo "$PTD" > "$tmp_dir_tmp/PTD.trace"
  severity="$(echo "$PTD" | awk -f "$script_dir/get_severityRating.awk")"
  echo "$severity" > "$tmp_dir_tmp/severity.trace"
  array_severity=($severity)

  # Performance flag:
  # 0 = pass
  # 1 = fail
  performance_flag=0

  for sev in "${array_severity[@]}"; do
    if [ "$sev" -eq 1 ]; then 
      performance_flag=1
      break
    fi
  done

  if [ "$performance_flag" -eq 1 ]; then
    break
    if $verbose; then echo 'Fail, stopping test.'; fi
  fi

  if $verbose; then echo "Pass"; fi

done

echo "$performance_flag" > "$tmp_dir/pflag.txt"



# *** Write report - latex ***

# TODO

if "$verbose"; then 
  echo " Done"
  echo
  echo "***** ISO7730 PAM END"
fi
