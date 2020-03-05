#! /bin/bash

# Resilience Assessment script for domestic buildings without mechanical cooling.
# ESP-r implementation.
# Version 1.0 of March 2020.

# Error codes:
# 101: Problem with command line options.
# 102: Problem with command line input.
# 666: General 
# TODO: sort error codes

# Set up defaults.
building=""
results_file="simulation_results"
start="1 1"
finish="31 12"
year="2020"
timesteps=1
startup=5
preset=""
tmp_dir="./tmp"
report_final="./report.pdf"
# detailed_report_final="./detailed_report.pdf"
JSON="./data.json"
information=false
verbose=false
preamble_file=""
do_simulation=true
do_indra=true
num_years=50
# do_detailed_report=false

# Get paths to call the various other scripts used by this program.
script_dir="$(dirname "$(readlink -f "$0")")"
common_dir="$script_dir/../../common"

# Parse command line.
while getopts ":hvf:p:t:s:d:r:j:c:P:UI" opt; do
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
    c) comfort_category="$OPTARG";;
    P) preamble_file="$OPTARG";;
    U) do_simulation=false;;
    I) do_indra=false;;
    # R) do_detailed_report=true
    #    detailed_report_final="$OPTARG";;
    \?) echo "Error: unknown option -$OPTARG. Use option -h for help." >&2
        exit 101;;
    :) echo "Error: option -$OPTARG requires and argument." >&2
       exit 101;;
  esac
done
shift $((OPTIND-1))
building="$1"
shift $((OPTIND-1))
cri_en_heat="$1"
shift $((OPTIND-1))
cri_en_light="$1"
shift $((OPTIND-1))
cri_en_equip="$1"
shift $((OPTIND-1))
cri_en_DHW="$1"
shift $((OPTIND-1))
cri_em_CO2="$1"
shift $((OPTIND-1))
cri_em_NOX="$1"
shift $((OPTIND-1))
cri_em_SOX="$1"
shift $((OPTIND-1))
cri_em_O3="$1"
shift $((OPTIND-1))
cri_tc_opt_liv_max="$1"
shift $((OPTIND-1))
cri_tc_opt_liv_min="$1"
shift $((OPTIND-1))
cri_tc_opt_kit_max="$1"
shift $((OPTIND-1))
cri_tc_opt_kit_min="$1"
shift $((OPTIND-1))
cri_tc_opt_bed_max="$1"
shift $((OPTIND-1))
cri_tc_opt_bed_min="$1"
shift $((OPTIND-1))
cri_tc_opt_bath_max="$1"
shift $((OPTIND-1))
cri_tc_opt_bath_min="$1"
shift $((OPTIND-1))
cri_tc_opt_WC_max="$1"
shift $((OPTIND-1))
cri_tc_opt_WC_min="$1"
shift $((OPTIND-1))
cri_tc_opt_hall_max="$1"
shift $((OPTIND-1))
cri_tc_opt_hall_min="$1"
shift $((OPTIND-1))
cri_aq_fas_min="$1"
shift $((OPTIND-1))
cri_aq_fas_unit="$1"
shift $((OPTIND-1))
cri_aq_CO2_max="$1"

if "$information" ; then
  echo
  echo " Usage: ./ISO7730.sh [OPTIONS] model-cfg-file"
  echo
  echo " Resilience Assessment script for domestic buildings without mechanical cooling."
  echo " ESP-r implementation."
  echo " Version 1.0 of March 2020."
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
  echo "                       -R detailed-pdf-report"
  echo "                          file name of a detailed pdf report, with added graphs"
  echo "                          default: no detailed report will be generated"
  echo "                       -j JSON-file"
  echo "                          file name of the json report"
  echo "                          default: ./data.json"
  echo "                       -c {A,B,C}"
  echo "                          Comfort criteria category as defined in BS EN ISO 7730"
  echo "                          default: B"
#  echo "                       -i model-image"
#  echo "                          image in .pdf, .png, .jpg or .eps format."
#  echo "                          default: PAM will automatically generate a wireframe image of the model"
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
  exit 102
fi

# # Check simluation period and timesteps.
# check="$(echo "$start" | awk '{ if ($0 ~ /^[0-9]+ +[0-9]+$/) {print "yes"} }')"
# if [ "$check" != "yes" ]; then
#   echo "Error: invalid simulation start date." >&2
#   exit 107
# fi
# check="$(echo "$finish" | awk '{ if ($0 ~ /^[0-9]+ +[0-9]+$/) {print "yes"} }')"
# if [ "$check" != "yes" ]; then
#   echo "Error: invalid simulation finish date." >&2
#   exit 107
# fi
# check="$(echo "$timesteps" | awk '{ if ($0 ~ /^[0-9]+$/) {print "yes"} }')"
# if [ "$check" != "yes" ]; then
#   echo "Error: invalid number of timesteps per hour." >&2
#   exit 107
# fi

# Check preamble file exists.
if ! [ "X$preamble_file" == "X" ]; then
  if ! [ -f "$preamble_file" ]; then
    echo "Error: preamble file not found." >&2
    exit 102
  fi
fi



if $verbose; then echo "***** DOMESTIC (FREE RUNNING) RA START"; fi

# Test if tmp directory exists.
if [ ! -d "$tmp_dir" ]; then
  if $verbose; then echo " Temporary directory \"$tmp_dir\" not found, attempting to create....."; fi
  mkdir "$tmp_dir"
  if [ -d "$tmp_dir" ]; then
    if $verbose; then echo " .....done."; fi
  else
    if $verbose; then echo ".....failed."; fi
    echo "Error: could not create temporary files directory." >&2
    exit 666
  fi
elif do_simulation; then
  rm -f "$tmp_dir"/*
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

# if "$do_detailed_report"; then
#   detailed_report="$tmp_dir/detailed_report.tex"
# fi




# *** CHECK MODEL ***

# Get model reporting variables, check values.
"$common_dir/esp-query/esp-query.py" -o "$tmp_dir/query_results.txt" "$building" "model_name" "model_description" "number_zones" "CFD_domains" "zone_control" "zone_setpoints" "MRT_sensors" "MRT_sensor_names" "afn_network" "afn_zon_nod_nums" "ctm_network" "number_ctm" "zone_names" "zone_floor_surfs" "uncertainties_file" "weather_file"

if [ "$?" -ne 0 ]; then
  echo "Error: model reporting script failed." >&2
  exit 666
fi

# Check model name.
model_name="$(awk -f "$common_dir/esp-query/processOutput_getModelName.awk" "$tmp_dir/query_results.txt")"
if [ "X$model_name" == "X" ]; then
# This really should be impossible, but check anyway.
  echo "Error: model name is empty." >&2
  exit 666
fi

# Check weather file.
weather_base="$(awk -f "$common_dir/esp-query/processOutput_getWeatherFile.awk" "$tmp_dir/query_results.txt")"
if [ "X$weather_base" == "X" ]; then
# This really should be impossible, but check anyway.
  echo "Error: no weather file detected." >&2
  exit 666
fi
if [ "${weather_base:0:1}" == '/' ]; then
  weather_base_abs="$weather_base"
else
  weather_base_abs="$PWD/model/cfg/$weather_base"
fi
if ! [ -f "$weather_base_abs" ]; then
  echo "Error: weather file does not exist." >&2
  exit 666
fi

# Check number of zones.
number_zones="$(awk -f "$common_dir/esp-query/processOutput_getNumZones.awk" "$tmp_dir/query_results.txt")"
if [ "X$number_zones" == "X" ] || [ "$number_zones" -eq 0 ]; then
  echo "Error: no thermal zones found in this model." >&2
  exit 666
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

# Check for afn network.
afn_network="$(awk -f "$common_dir/esp-query/processOutput_getAFNnetwork.awk" "$tmp_dir/query_results.txt")"
if [ "X$afn_network" == "X" ]; then
  is_afn=false
else
  is_afn=true  
  afn_zon_nod_nums="$(awk -f "$common_dir/esp-query/processOutput_getNumCTM.awk" "$tmp_dir/query_results.txt")"
  array_zone_AFNnodNums=($afn_zon_nod_nums)
fi

# Check for contaminant network.
ctm_network="$(awk -f "$common_dir/esp-query/processOutput_getCTMnetwork.awk" "$tmp_dir/query_results.txt")"
if [ "X$ctm_network" == "X" ]; then
  is_ctm=false
else
  is_ctm=true
  number_ctm="$(awk -f "$common_dir/esp-query/processOutput_getNumCTM.awk" "$tmp_dir/query_results.txt")"
fi

# Check for MRT sensors.
# While we're here, assemble an array mapping sensor indices to zones,
# and an array of indices for looping over sensor arrays.
MRT_sensors="$(awk -f "$common_dir/esp-query/processOutput_getSpaceSeparatedMRTsensors.awk" "$tmp_dir/query_results.txt")"
array_MRT_sensors=($MRT_sensors)
is_MRT=false
number_MRT_sensors=0
number_zones_with_MRTsensors=0
i_zone=0
i_ind=0
j=0
for n in "${array_MRT_sensors[@]}"; do
  ((i_zone++))
  if [ "$n" -gt 0 ]; then 
    if ! $is_MRT; then is_MRT=true; fi
    ((number_MRT_sensors+=n))
    ((number_zones_with_MRTsensors++))
    array_zones_with_MRTsensors[j]="$i_zone"
    ((j++))
    i=0
    while [ "$i" -lt "$n" ]; do
      array_sensor_zones=(${array_sensor_zones[@]} $i_zone)
      array_sensor_indices[i_ind]="$i_ind"
      ((i_ind++))
      ((i++))
    done
  fi
done
# if ! $is_MRT; then
#   echo "Error: no occupant locations detected in this model." >&2
#   exit 103
# fi

# Assemble array of MRT sensor names.
if $is_MRT; then
  MRTsensor_names="$(awk -f "$common_dir/esp-query/processOutput_getSpaceSeparatedAllMRTsensorNames.awk" "$tmp_dir/query_results.txt")"
  array_MRTsensor_names=($MRTsensor_names)
fi

# Check for CFD domains.
CFD_domains="$(awk -f "$common_dir/esp-query/processOutput_getSpaceSeparatedCFDdomains.awk" "$tmp_dir/query_results.txt")"
array_CFD_domains=($CFD_domains)
is_CFD=false
is_CFDandMRT=false
CFDdomain_count=0
j=0
number_zones_with_CFDandMRT=0
for i in "${array_zone_indices[@]}"; do
  n="${array_CFD_domains[i]}"
  if [ "$n" -gt 1 ]; then
    is_CFD=true
    ((CFDdomain_count++))
    CFD_start_hour='1.0'
    CFD_finish_hour='24.99'
#    CFD_start_hour='6.0'
#    CFD_finish_hour='20.99'
    m="${array_MRT_sensors[i]}"
    if [ "$m" -gt 0 ]; then
      is_CFDandMRT=true
      array_zones_with_CFDandMRT[j]="$((i+1))"
      ((j++))
      ((number_zones_with_CFDandMRT++))
    fi
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

# Check for uncertainties definitions.
ucn="$(awk -f "$common_dir/esp-query/processOutput_getUncertaintiesFile.awk" "$tmp_dir/query_results.txt")"
if [ "X$ucn" == "X" ]; then
  is_ucn=false
else
  is_ucn=true
fi

# Set results library names.
sim_results="${results_file}.res"
if $is_afn; then mf_results="${results_file}.mfr"; fi
if $is_CFD; then cfd_results="${results_file}.dfr"; fi

# Scan command line input to determine what metrics we are interested in.
if [ "$cri_en_heat" == 'X' ]; then get_en_heat=false; else get_en_heat=true; fi
if [ "$cri_en_light" == 'X' ]; then get_en_light=false; else get_en_light=true; fi
if [ "$cri_en_equip" == 'X' ]; then get_en_equip=false; else get_en_equip=true; fi
if [ "$cri_en_DHW" == 'X' ]; then
  # TODO: If DHW energy use is required, we need a plant network.
  get_en_DHW=false
else
  get_en_DHW=true
fi
if [ "$cri_em_CO2" == 'X' ]; then get_em_CO2=false; else get_em_CO2=true; fi
if [ "$cri_em_NOX" == 'X' ]; then get_em_NOX=false; else get_em_NOX=true; fi
if [ "$cri_em_SOX" == 'X' ]; then get_em_SOX=false; else get_em_SOX=true; fi
if [ "$cri_em_O3" == 'X' ]; then get_em_O3=false; else get_em_O3=true; fi
get_tc_opt=false
if ! $get_tc_opt; then if ! [ "$cri_tc_opt_liv_max" == 'X' ]; then get_tc_opt=true; fi; fi
if ! $get_tc_opt; then if ! [ "$cri_tc_opt_liv_min" == 'X' ]; then get_tc_opt=true; fi; fi
if ! $get_tc_opt; then if ! [ "$cri_tc_opt_kit_max" == 'X' ]; then get_tc_opt=true; fi; fi
if ! $get_tc_opt; then if ! [ "$cri_tc_opt_kit_min" == 'X' ]; then get_tc_opt=true; fi; fi
if ! $get_tc_opt; then if ! [ "$cri_tc_opt_bed_max" == 'X' ]; then get_tc_opt=true; fi; fi
if ! $get_tc_opt; then if ! [ "$cri_tc_opt_bed_min" == 'X' ]; then get_tc_opt=true; fi; fi
if ! $get_tc_opt; then if ! [ "$cri_tc_opt_bath_max" == 'X' ]; then get_tc_opt=true; fi; fi
if ! $get_tc_opt; then if ! [ "$cri_tc_opt_bath_min" == 'X' ]; then get_tc_opt=true; fi; fi
if ! $get_tc_opt; then if ! [ "$cri_tc_opt_WC_max" == 'X' ]; then get_tc_opt=true; fi; fi
if ! $get_tc_opt; then if ! [ "$cri_tc_opt_WC_min" == 'X' ]; then get_tc_opt=true; fi; fi
if ! $get_tc_opt; then if ! [ "$cri_tc_opt_hall_max" == 'X' ]; then get_tc_opt=true; fi; fi
if ! $get_tc_opt; then if ! [ "$cri_tc_opt_hall_min" == 'X' ]; then get_tc_opt=true; fi; fi
if ! [ "$cri_aq_fas_min" == 'X' ]; then
  # If fresh air supply is required, we need a flow network.
  if $is_afn; then
    get_aq_fas=true
  else
    echo 'Error: need a flow network to assess fresh air supply.'
    exit 666
  fi
else
  get_aq_fas=false
fi
if ! [ "$cri_aq_CO2_max" == 'X' ]; then
  # If CO2 concentration is required, we need a flow network and a contaminant network.
  if $is_afn && $is_ctm; then
    # Assume that we need only 1 contamimant in network.
    if [ "$number_ctm" -ne "1" ]; then
      echo "Error: need 1 contaminant defined in network." >&2
      exit 666
    fi
    get_aq_CO2=true
  else
    echo 'Error: need flow and contamimant networks to assess CO2 concentration.'
    exit 666
  fi
else
  get_aq_CO2=false
fi




# *** PRE-SIMULATION ***

# Use indra to generate 50 years of different weather data from
# that supplied with the model.
if $do_indra; then

  # Update progress file.
  echo '3' > "$tmp_dir/progress.txt"

  # Generate an ASCII version of the seed weather file.
  clm -file "$weather_base_abs" -act bin2asci silent "$tmp_dir/weather_base.txt"
  if [ $? -ne 0 ]; then  
    echo "Error: failed to convert base weather to ASCII."
    exit 666
  fi

  # Train indra from the seed weather file.
  mkdir "$tmp_dir/indra"
  python3 "$common_dir/SyntheticWeather/indra.py" --train 1 --station_code 'ra' --n_samples "$num_years" --path_file_in "$tmp_dir/weather_base.txt" --path_file_out "$weather_base_abs.txt" --file_type 'espr' --store_path "$tmp_dir/indra" > "$tmp_dir/indra.out"
  if [ $? -ne 0 ]; then
    echo "Error: failed to train indra."
    exit 666
  fi
fi

# Set up paths.
if [ "X$up_one" == "X" ]; then
  building_tmp="$building"
  building_dir_tmp="$building_dir"
  tmp_dir_tmp="$tmp_dir"
  sim_results_tmp="$sim_results"
  mf_results_tmp="$mf_results"
  cfd_results_tmp="$cfd_results"
else
  cd ..
  building_tmp="$up_one/$building"
  building_dir_tmp="$(dirname "$building_tmp")"
  tmp_dir_tmp="$up_one/$tmp_dir"
  sim_results_tmp="$up_one/$sim_results"
  mf_results_tmp="$up_one/$mf_results"
  cfd_results_tmp="$up_one/$cfd_results"
fi

# Update simulation year in cfg file.
sed -i -e 's/\*year *[0-9]*/*year '"$year"'/' "$building_tmp"

# Remove any files that might cause unexpected questions from ESP-r.
# Suppress output to prevent chatter.
rm -f "$sim_results_tmp" > /dev/null
if $is_afn; then rm -f "$mf_results_tmp" > /dev/null; fi
if $is_CFD; then rm -f "$cfd_results_tmp" > /dev/null; fi
rm -f "$building_dir_tmp"/ACC-actions_*.rec > /dev/null
rm -f "$building_dir_tmp"/cfd3dascii_* > /dev/null

 


# *** START OF SIMULATION LOOP ***

# Loop for the prescribed number of years.
iyear=1
while "$iyear" <= "$num_years"; do

  # * SIMULATE *
  if "$do_simulation"; then

    # Update progress file.
    echo '4' > "$tmp_dir/progress.txt"

    # if ! [ "X$up_one" == "X" ]; then
    #   cd ..
    # fi

    # Retrieve weather data from indra.
    python3 "$common_dir/SyntheticWeather/indra.py" --train 0 --station_code 'ra' --path_file_in "$tmp_dir_tmp/weather_base.txt" --path_file_out "$weather_base_abs.txt" --file_type 'espr' --store_path "$tmp_dir_tmp/indra" >> "$tmp_dir_tmp/indra.out"
    if [ $? -ne 0 ]; then  
      echo "Error: failed to retrieve weather data from indra."
      exit 666
    fi

    # Convert ASCII weather data to binary.
    rm "$weather_base_abs"
    clm -file "$weather_base_abs" -act asci2bin silent "$weather_base_abs.txt"
    if [ $? -ne 0 ]; then  
      echo "Error: failed to convert weather data to binary."
      exit 666
    fi

    # Run ESP-r simulation.
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

#         # Disable CFD for the initial simulation.
#         bps_script="$bps_script
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

      echo "$bps_script" > "$tmp_dir_tmp/bps.script"

      bps -mode script -file "$building_tmp" > "$tmp_dir_tmp/bps.out" <<~
${bps_script}
~
    fi

    # if ! [ "X$up_one" == "X" ]; then
    #   cd "$up_one" || exit 666
    # fi

    # Check error code and existence of results libraries.
    if [ "$?" -ne 0 ]; then
      echo "Error: simulation failed, please check model manually." >&2
      exit 104
    fi

    if ! [ -f "$sim_results_tmp" ]; then
      echo "Error: simulation failed, please check model manually." >&2
      exit 104
    fi

    if $is_afn && ! [ -f "$mf_results_tmp" ]; then
      echo "Error: simulation failed, please check model manually." >&2
      exit 104
    fi

    if $is_CFD && ! [ -f "$cfd_results_tmp" ]; then
      echo "Error: simulation failed, please check model manually." >&2
      exit 104
    fi
  fi

  # * EXTRACT RESULTS *

  # Update progress file.
  echo '4' > "$tmp_dir_tmp/progress.txt"

  # if ! [ "X$up_one" == "X" ]; then
  #   cd .. || exit 1
  # fi

  # Run res to get occupied hours.
  res -mode script -file "$sim_results_tmp" > "$tmp_dir_tmp/res.out" <<~

d
c
>
b
${tmp_dir_tmp}/occupied_hours
j
e
-
0.001
>
-
-
-
~

  # Check error code and existence of output.
  if [ "$?" -ne 0 ] || ! [ -f "$tmp_dir_tmp/occupied_hours" ]; then
    echo "Error: occupancy results extraction failed." >&2
    exit 105
  fi

  # Extract data from res output.
  ocup="$(awk -f "$script_dir/get_occupiedHoursLatex.awk" "$tmp_dir_tmp/occupied_hours")"

  # Check data for occupancy.
  count=0
  ind=0
  is_occ=false
  num_occ_zones=0
  for a in $ocup; do
    ((count++))
    if [ $count -eq 1 ]; then
      zone_num="${a:0:-1}"
      zone_ind="$((zone_num - 1))"
      if $verbose; then echo " Checking zone $zone_num."; fi
    elif [ $count -eq 4 ]; then 
      if $verbose; then echo " Occupied hours = $a"; fi
      # if [ "${a/.}" -gt 0 ] && [ "${array_MRT_sensors[ind]}" -gt 0 ]; then
      if [ "${a/.}" -gt 0 ]; then
        if $verbose; then echo " Occupied."; fi
        if ! $is_occ; then is_occ=true; fi
        array_is_occ[zone_ind]=true
        array_occ_zoneNums[num_occ_zones]=zone_num
        ((num_occ_zones++))
      else
        if $verbose; then echo " Not occupied."; fi
        array_is_occ[zone_ind]=false
      fi
    elif [ $count -eq 7 ]; then 
      count=0
      ((ind++))
    fi
  done

  if ! $is_occ; then
  # No occupancy, exit with an error.
    echo "Error: no occupancy detected in this model." >&2
    exit 106
  fi 

  # Define res commands
  
  # Only need to activate filtering once; will stay on for the rest of results.
  filter_on=false
  res_script=""

  # Open CFD library to avoid unexpected prompts.
  if $is_CFD; then
    res_script="$res_script
h
${cfd_results_tmp}"
    if [ "$CFDdomain_count" -gt 1 ]; then
      res_script="$res_script
1"
    fi
    res_script="$res_script
-"
  fi

  # Open mass flow library to avoid unexpected prompts
  if $is_afn; then
    res_script="$res_script
c
i
${current_dir}/${mf_results_tmp}
-
-"
  fi

  # Get time step resultant temperature for all occupied zones.
  if $get_tc_opt; then
    res_script="$res_script
c
g
4
<
${num_occ_zones}"
    for i in "${array_occ_zoneNums[@]}"; do
      res_script="$res_script
${i}"
    done
    res_script="$res_script
*
a"
    if ! $filter_on; then
      res_script="$res_script
+
b"
      filter_on=true
    fi
    res_script="$res_script
>
b
${tmp_dir_tmp}/resultant_temp.txt

b
e
-
!
>
-
-"
  fi

  # Get energy delivered for all occupied zones.
  if $get_en_heat; then
    res_script="$res_script
d
4
<
${num_occ_zones}"
    for i in "${array_occ_zoneNums[@]}"; do
      res_script="$res_script
${i}"
    done
    res_script="$res_script
>
b
${tmp_dir_tmp}/energy_delivered.txt

f
>
-
-"
  fi

  # Get casual gain distribution for all occupied zones.
  if $get_en_light || $get_en_equip; then
    res_script="$res_script
d
4
<
${num_occ_zones}"
    for i in "${array_occ_zoneNums[@]}"; do
      res_script="$res_script
${i}"
    done
    res_script="$res_script
>
b
${tmp_dir_tmp}/casual_gain_distribution.txt

g
>
-
-"
  fi

  # TODO: Get annual DHW energy use.

  # Emissions are post-processing.

  # Get timestep air from ambient.
  # Because we frequently exceed the selection limit doing this, do one node at a time.
  if $get_aq_fas; then    
    for i0_zone in "${array_zone_indices[@]}"; do
      i1_zone="$((i0_zone + 1))"
      i1_zone_pad="$(printf "%03d" $i1_zone)"
      i1_nod="${array_zone_AFNnodNums[i0_zone]}"
      res_script="$res_script
c
i
>
b
${tmp_dir_tmp}/air_from_ambient_z${i1_zone_pad}.txt

j
b
d      
<
1
${i1_nod}
>
-
-"
    done
  fi

  # Get timestep CO2 concentration for occupied zones.
  # To enable filtering, do this one zone at a time.
  if $get_aq_CO2; then
    for i1_zone in "${array_occ_zoneNums[@]}"; do
      i0_zone="$((i1_zone - 1))"
      i1_zone_pad="$(printf "%03d" $i1_zone)"
      i1_nod="${array_zone_AFNnodNums[i0_zone]}"
      res_script="$res_script
c
i
*
a"
      if $filter_on; then
        res_script="$res_script
+"
      fi
      res_script="$res_script
+
b
<
1
${i1_zone}
>
b
${tmp_dir_tmp}/CO2_concentration_z${i1_zone_pad}.txt

m
<
1
${i1_nod}
a
-
+
>
-
-"
      filter_on=false
    done
  fi

  # * PROCESS RESULTS *
  # HERE
    

  ((iyear++))

done
