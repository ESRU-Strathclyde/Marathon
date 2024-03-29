#! /bin/bash

containsElement () {
  local e match="$1"
  shift
  for e; do [ "$e" == "$match" ] && return 0; done
  return 1
}

removeX () {
  local __var="$1"
  local __val="$2"
  if [ "$__val" == 'X' ]; then
    eval "$__var"=''
  else
    eval "$__var"="'$__val'"
  fi
}

# Resilience Assessment script for domestic buildings without mechanical cooling.
# ESP-r implementation.
# Version 1.0 of June 2020.

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
do_CFD=false
num_years=10
# do_detailed_report=false
limit_multiplier='0.1' # 0.1 = 10% allowable deviation

# Get paths to call the various other scripts used by this program.
script_dir="$(dirname "$(readlink -f "$0")")"
common_dir="$script_dir/../../common"

# Get current directory.
current_dir="$PWD"

# Parse command line.
while getopts ":hvf:p:t:s:d:r:j:c:P:SIC" opt; do
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
    S) do_simulation=false;;
    I) do_indra=false;;
    C) do_CFD=false;;
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
shift
removeX 'cri_en_heat_max' "$1"
shift
removeX 'cri_en_light_max' "$1"
shift
removeX 'cri_en_equip_max' "$1"
shift
removeX 'cri_en_DHW_max' "$1"
shift
removeX 'cri_em_CO2_max' "$1"
shift
removeX 'cri_em_NOX_max' "$1"
shift
removeX 'cri_em_SOX_max' "$1"
shift
removeX 'cri_em_O3_max' "$1"
shift
removeX 'cri_tc_opt_liv_max' "$1"
shift
removeX 'cri_tc_opt_liv_min' "$1"
shift
removeX 'cri_tc_opt_kit_max' "$1"
shift
removeX 'cri_tc_opt_kit_min' "$1"
shift
removeX 'cri_tc_opt_bed_max' "$1"
shift
removeX 'cri_tc_opt_bed_min' "$1"
shift
removeX 'cri_tc_opt_bath_max' "$1"
shift
removeX 'cri_tc_opt_bath_min' "$1"
shift
removeX 'cri_tc_opt_WC_max' "$1"
shift
removeX 'cri_tc_opt_WC_min' "$1"
shift
removeX 'cri_tc_opt_hall_max' "$1"
shift
removeX 'cri_tc_opt_hall_min' "$1"
shift
removeX 'cri_aq_fas_min' "$1"
shift
removeX 'cri_aq_fas_unit' "$1"
shift
removeX 'cri_aq_CO2_max' "$1"

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
  echo "                       -S" 
  echo "                          Do not simulate and use existing results libraries"
  echo "                          default: off"
  echo "                       -I" 
  echo "                          Do not run Indra and use existing weather database"
  echo "                          default: off"
  echo "                       -C" 
  echo "                          Switch off CFD in simulations"
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



if $verbose; then echo "***** DOMESTIC (MECHANICALLY COOLED) RA START"; fi

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
# elif $do_simulation && $do_indra; then
#   rm -f "$tmp_dir"/*
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

# if "$do_detailed_report"; then
#   detailed_report="$tmp_dir/detailed_report.tex"
# fi




# *** CHECK MODEL ***

# Get model reporting variables, check values.
"$common_dir/esp-query/esp-query.py" -o "$tmp_dir/query_results.txt" "$building" "model_name" "model_description" "number_zones" "CFD_domains" "zone_control" "zone_setpoints" "MRT_sensors" "MRT_sensor_names" "afn_network" "afn_zon_nod_nums" "ctm_network" "number_ctm" "zone_names" "zone_floor_surfs" "uncertainties_file" "weather_file" "QA_report" "total_volume" "zone_volumes"

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
  afn_zon_nod_nums="$(awk -f "$common_dir/esp-query/processOutput_getSpaceSeparatedAFNnodNums.awk" "$tmp_dir/query_results.txt")"
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
# is_CFDandMRT=false
CFDdomain_count=0
# j=0
# number_zones_with_CFDandMRT=0
for i in "${array_zone_indices[@]}"; do
  n="${array_CFD_domains[i]}"
  if [ "$n" -gt 1 ]; then
    is_CFD=true
    ((CFDdomain_count++))
    CFD_start_hour='1.0'
    CFD_finish_hour='24.99'
#    CFD_start_hour='6.0'
#    CFD_finish_hour='20.99'
    # m="${array_MRT_sensors[i]}"
    # if [ "$m" -gt 0 ]; then
    #   is_CFDandMRT=true
    #   array_zones_with_CFDandMRT[j]="$((i+1))"
    #   ((j++))
    #   ((number_zones_with_CFDandMRT++))
    # fi
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
      if [ "$cfd_results_preset" == 'disabled' ]; then
        is_CFD=false
      else
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

# But is true of the CFD library.
  if $is_CFD; then cfd_results_preset=~/"$(basename "$cfd_results_preset")"; fi
fi

# Check for uncertainties definitions.
ucn="$(awk -f "$common_dir/esp-query/processOutput_getUncertaintiesFile.awk" "$tmp_dir/query_results.txt")"
if [ "X$ucn" == "X" ]; then
  is_ucn=false
else
  is_ucn=true
fi

# Check for a QA file.
QA="$(awk -f "$common_dir/esp-query/processOutput_getQAreport.awk" "$tmp_dir/query_results.txt")"
if [ "X$QA" == "X" ]; then
  # No QA file; generate one.
  if [ "X$up_one" == 'X' ]; then cd "$building_dir"; fi
  if ! prj -file "$building_base" -mode script -act QA > ../../"$tmp_dir"/prj.out; then
    echo "Error: failed to generate QA report"
    exit 666
  fi
  if [ "X$up_one" == 'X' ]; then cd "$current_dir"; fi
  # Add reference to cfg file.
  sed -e 's/^\(\*ctl .*\)$/\1\n*contents ..\/doc\/'"$model_name"'.contents/' -i "$building"
  # Now re-run esp-query to get total volume and zone volumes.
  query2="$("$common_dir/esp-query/esp-query.py" "$building" "total_volume" "zone_volumes")"
  total_volume="$(echo "$query2" | awk -f "$common_dir/esp-query/processOutput_getTotalVolume.awk")"
  zone_volumes="$(echo "$query2" | awk -f "$common_dir/esp-query/processOutput_getSpaceSeparatedZoneVolumes.awk")"
  array_zone_volumes=($zone_volumes)
else
  # Get total volume.
  total_volume="$(awk -f "$common_dir/esp-query/processOutput_getTotalVolume.awk" "$tmp_dir/query_results.txt")"
  # Get zone volumes.
  zone_volumes="$(awk -f "$common_dir/esp-query/processOutput_getSpaceSeparatedZoneVolumes.awk" "$tmp_dir/query_results.txt")"
  array_zone_volumes=($zone_volumes)
fi

# Set results library names.
sim_results="${results_file}.res"
if $is_afn; then mf_results="${results_file}.mfr"; fi
if $is_CFD; then cfd_results="${results_file}.dfr"; fi

# Scan command line input to determine what metrics we are interested in.
if [ "X$cri_en_heat_max" == 'X' ]; then get_en_heat=false; else get_en_heat=true; fi
if [ "X$cri_en_light_max" == 'X' ]; then get_en_light=false; else get_en_light=true; fi
if [ "X$cri_en_equip_max" == 'X' ]; then get_en_equip=false; else get_en_equip=true; fi
if [ "X$cri_en_DHW_max" == 'X' ]; then
  # TODO: If DHW energy use is required, we need a plant network.
  get_en_DHW=false
else
  get_en_DHW=true
fi
if [ "X$cri_em_CO2_max" == 'X' ]; then get_em_CO2=false; else get_em_CO2=true; fi
if [ "X$cri_em_NOX_max" == 'X' ]; then get_em_NOX=false; else get_em_NOX=true; fi
if [ "X$cri_em_SOX_max" == 'X' ]; then get_em_SOX=false; else get_em_SOX=true; fi
if [ "X$cri_em_O3_max" == 'X' ]; then get_em_O3=false; else get_em_O3=true; fi
get_tc_opt=false
if ! [ "X$cri_tc_opt_liv_max" == 'X' ] || ! [ "X$cri_tc_opt_liv_min" == 'X' ]; then 
  get_tc_opt=true
  get_tc_opt_liv=true
else
  get_tc_opt_liv=false
fi
if ! [ "X$cri_tc_opt_kit_max" == 'X' ] || ! [ "X$cri_tc_opt_kit_min" == 'X' ]; then 
  get_tc_opt=true
  get_tc_opt_kit=true
else
  get_tc_opt_kit=false
fi
if ! [ "X$cri_tc_opt_bed_max" == 'X' ] || ! [ "X$cri_tc_opt_bed_min" == 'X' ]; then 
  get_tc_opt=true
  get_tc_opt_bed=true
else
  get_tc_opt_bed=false
fi
if ! [ "X$cri_tc_opt_bath_max" == 'X' ] || ! [ "X$cri_tc_opt_bath_min" == 'X' ]; then 
  get_tc_opt=true
  get_tc_opt_bath=true
else
  get_tc_opt_bath=false
fi
if ! [ "X$cri_tc_opt_WC_max" == 'X' ] || ! [ "X$cri_tc_opt_WC_min" == 'X' ]; then 
  get_tc_opt=true
  get_tc_opt_WC=true
else
  get_tc_opt_WC=false
fi
if ! [ "X$cri_tc_opt_hall_max" == 'X' ] || ! [ "X$cri_tc_opt_hall_min" == 'X' ]; then 
  get_tc_opt=true
  get_tc_opt_hall=true
else
  get_tc_opt_hall=false
fi
if ! [ "X$cri_aq_fas_min" == 'X' ]; then
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
if ! [ "X$cri_aq_CO2_max" == 'X' ]; then
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

# Debug.
echo "get_en_heat $get_en_heat" > "$tmp_dir/gets.trace"
echo "get_en_light $get_en_light" >> "$tmp_dir/gets.trace"
echo "get_en_equip $get_en_equip" >> "$tmp_dir/gets.trace"
echo "get_en_DHW $get_en_DHW" >> "$tmp_dir/gets.trace"
echo "get_em_CO2 $get_em_CO2" >> "$tmp_dir/gets.trace"
echo "get_em_NOX $get_em_NOX" >> "$tmp_dir/gets.trace"
echo "get_em_SOX $get_em_SOX" >> "$tmp_dir/gets.trace"
echo "get_em_O3 $get_em_O3" >> "$tmp_dir/gets.trace"
echo "get_tc_opt $get_tc_opt" >> "$tmp_dir/gets.trace"
echo "get_aq_fas $get_aq_fas" >> "$tmp_dir/gets.trace"
echo "get_aq_CO2 $get_aq_CO2" >> "$tmp_dir/gets.trace"

# Scan zone names to find ...
liv=0
kit=0
bed=0
bath=0
WC=0
hall=0
for i0_zone in "${array_zone_indices[@]}"; do
  i1_zone="$((i0_zone+1))"
  zoneName="${array_zone_names[i0_zone]}"
  # living room(s)
  if [[ "$zoneName" == *liv* ]]; then
    array_liv_zoneNums[liv]="$i1_zone"
    ((liv++))
  fi
  # kitchen(s)
  if [[ "$zoneName" == *kit* ]]; then
    array_kit_zoneNums[kit]="$i1_zone"
    ((kit++))
  fi
  # bedroom(s)
  if [[ "$zoneName" == *bed* ]]; then
    array_bed_zoneNums[bed]="$i1_zone"
    ((bed++))
  fi
  # bathroom(s)
  if [[ "$zoneName" == *bath* ]]; then
    array_bath_zoneNums[bath]="$i1_zone"
    ((bath++))
  fi
  # WC(s)
  if [[ "$zoneName" == *WC* ]]; then
    array_WC_zoneNums[WC]="$i1_zone"
    ((WC++))
  fi
  # hall(s)
  if [[ "$zoneName" == *hall* ]]; then
    array_hall_zoneNums[hall]="$i1_zone"
    ((hall++))
  fi
done




# *** PRE-SIMULATION ***

# Use indra to generate num_years years of different weather data from
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





# *** START OF SIMULATION LOOP ***

# Update progress file.
echo '4' > "$tmp_dir/progress.txt"

# Loop for the prescribed number of years.
iyear=1
while [ "$iyear" -le "$num_years" ]; do

  # * SIMULATE *
  if "$do_simulation"; then

    # Remove any files that might cause unexpected questions from ESP-r.
    # Suppress output to prevent chatter.
    rm -f "$sim_results_tmp" > /dev/null
    if $is_afn; then rm -f "$mf_results_tmp" > /dev/null; fi
    if $is_CFD; then rm -f "$cfd_results_tmp" > /dev/null; fi
    rm -f "$building_dir_tmp"/ACC-actions_*.rec > /dev/null
    rm -f "$building_dir_tmp"/cfd3dascii_* > /dev/null

    # if ! [ "X$up_one" == "X" ]; then
    #   cd ..
    # fi

    # Retrieve weather data from indra.
    if $do_indra; then
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
        if $do_CFD; then
          # Run CFD for whole period.
          bps_script="$bps_script
y
${start}
${finish}
${CFD_start_hour}
${CFD_finish_hour}"
        else
          # Disable CFD for the simulation.
          bps_script="$bps_script
n"
        fi
      fi
      bps_script="$bps_script
s
y"
      if $is_ucn; then
        bps_script="$bps_script
d
-"
      fi
      bps_script="$bps_script
RA simulation
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

    if $is_CFD && $do_CFD && ! [ -f "$cfd_results_tmp" ]; then
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
${tmp_dir_tmp}/occupied_hours.txt
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
  if [ "$?" -ne 0 ] || ! [ -f "$tmp_dir_tmp/occupied_hours.txt" ]; then
    echo "Error: occupancy results extraction failed." >&2
    exit 105
  fi

  # Extract data from res output.
  ocup="$(awk -f "$script_dir/get_occupiedHours.awk" "$tmp_dir_tmp/occupied_hours.txt")"

  # Debug.
  echo "$ocup" > "$tmp_dir_tmp/ocup.trace"

  # Check data for occupancy.
  count=0
  ind=0
  is_occ=false
  num_occ_zones=0
  for a in $ocup; do
    ((count++))
    if [ $count -eq 1 ]; then
      zone_num="${a}"
      zone_ind="$((zone_num - 1))"
      if $verbose; then echo " Checking zone $zone_num."; fi
    elif [ $count -eq 2 ]; then 
      if $verbose; then echo " Occupied hours = $a"; fi
      # if [ "${a/.}" -gt 0 ] && [ "${array_MRT_sensors[ind]}" -gt 0 ]; then
      if [ "${a/.}" -gt 0 ]; then
        if $verbose; then echo " Occupied."; fi
        if ! $is_occ; then is_occ=true; fi
        array_is_occ[zone_ind]=true
        array_occ_zoneNums[num_occ_zones]=$zone_num
        ((num_occ_zones++))
      else
        if $verbose; then echo " Not occupied."; fi
        array_is_occ[zone_ind]=false
      fi
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
  if $is_CFD && $do_CFD; then
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

  # Open mass flow library to avoid unexpected prompts.
  # ESP-r looks for the mass flow library relative to the cfg file.
  if $is_afn; then
    res_script="$res_script
c
i
../../${mf_results_tmp}
-
-"
  fi

  # Get energy delivered for zones.
  # Include unnocupied zones in this; this gets ESP-r to work out
  # per m2 for us.
  if $get_en_heat; then
    res_script="$res_script
d
4
*
-
>
b
${tmp_dir_tmp}/energy_delivered.txt

f
>
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
-"
  fi

  # TODO: Get annual DHW energy use.

  # Emissions are post-processing.

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

a
a
-
b
e
-
!
>
-
-"
  fi

  # Get timestep air from ambient.
  # Because we frequently exceed the selection limit doing this,
  # do one node at a time.
  # Always get l/s even if we need ACH, because we need to
  # convert to ACH based on total volume which ESP-r doesn't do.
  if $get_aq_fas; then    
    for i0_zone in "${array_zone_indices[@]}"; do
      i1_zone="$((i0_zone + 1))"
      i1_zone_pad="$(printf "%03d" $i1_zone)"
      i1_nod="${array_zone_AFNnodNums[i0_zone]}"
      if [ "$i1_nod" -gt 0 ]; then
        res_script="$res_script
c
i
*
a
>
b
${tmp_dir_tmp}/air_from_ambient_z${i1_zone_pad}.txt

j
b
d      
<
1
${i1_nod}
!
>
-
-"
      fi
    done
  fi

  # Get timestep total air in.
  # Total air in must equal total air out, so this is equivalent to 
  # total extract (not necessarily to ambient).
  # Because we frequently exceed the selection limit doing this,
  # do one node at a time.
  # Always get l/s even if we need ACH, because we need to
  # convert to ACH based on total volume which ESP-r doesn't do.
  if $get_aq_fas; then    
    for i0_zone in "${array_zone_indices[@]}"; do
      i1_zone="$((i0_zone + 1))"
      i1_zone_pad="$(printf "%03d" $i1_zone)"
      i1_nod="${array_zone_AFNnodNums[i0_zone]}"
      if [ "$i1_nod" -gt 0 ]; then
        res_script="$res_script
c
i
*
a
>
b
${tmp_dir_tmp}/air_total_extract_z${i1_zone_pad}.txt

j
b
c      
<
1
${i1_nod}
!
>
-
-"
      fi
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

  res_script="$res_script
-
"

  echo "$res_script" >> "$tmp_dir_tmp/res.script"

  # Run res.
  res -mode script -file "$sim_results_tmp" >> "$tmp_dir_tmp/res.out" <<~
${res_script}
~



  # * PROCESS RESULTS *

  # Get heating energy use deviation.
  if $get_en_heat; then
    en_heat="$(awk -f "$script_dir/get_energyDelivered.awk" "$tmp_dir_tmp/energy_delivered.txt")"
    en_heat_deviation="$(echo "$en_heat" | awk -f "$script_dir/get_deviation_value.awk" -v max="$cri_en_heat_max")"
    en_heat_limit="$(echo "$cri_en_heat_max" | awk '{print $1*'"${limit_multiplier}}")"
    desc="${desc}
$(echo "$en_heat_deviation" | awk -f "$script_dir/check_deviation_value.awk" -v max="$en_heat_limit" -v met='Annual heating energy use' -v unit='kWh/ m\\textsuperscript{2}.y')"
    if ! $fail; then
      if [ "$?" -eq 1 ]; then fail=true; fi
    fi
  fi

  # TODO: get other energy use deviations.

  # TODO: get emissions deviations.

  # Get operative temperature deviation.
  # First, assemble column lists for each zone type.
  # First column is time, second column is outdoor dry bulb temperature,
  # so we sart at column 3.
  i3_col=2
  for i0 in "${array_zone_indices[@]}"; do      
    if ${array_is_occ[i0]}; then
      ((i3_col++))
      i1="$((i0+1))"
      if containsElement "$i1" "${array_liv_zoneNums[@]}"; then
        i3_liv_cols="${i3_liv_cols}${i3_col},"
      fi
      if containsElement "$i1" "${array_kit_zoneNums[@]}"; then
        i3_kit_cols="${i3_kit_cols}${i3_col},"
      fi
      if containsElement "$i1" "${array_bed_zoneNums[@]}"; then
        i3_bed_cols="${i3_bed_cols}${i3_col},"
      fi
      if containsElement "$i1" "${array_bath_zoneNums[@]}"; then
        i3_bath_cols="${i3_bath_cols}${i3_col},"
      fi
      if containsElement "$i1" "${array_WC_zoneNums[@]}"; then
        i3_WC_cols="${i3_WC_cols}${i3_col},"
      fi
      if containsElement "$i1" "${array_hall_zoneNums[@]}"; then
        i3_hall_cols="${i3_hall_cols}${i3_col},"
      fi
    fi
  done

  # # Debug.
  # echo "$i3_liv_cols"
  # echo "$i3_kit_cols"
  # echo "$i3_bed_cols"
  # echo "$i3_bath_cols"
  # echo "$i3_WC_cols"
  # echo "$i3_hall_cols"

  # Now get deviation and check for failures.
  # Assemble description strings for each zone.
  if $get_tc_opt_liv && [ "${#array_liv_zoneNums[@]}" -gt 0 ]; then
    if [ "$cri_tc_opt_liv_max" == 'CIBSE TM52' ]; then
      opt_deviation_liv="$(awk -f "$script_dir/get_deviation_timeStep_CIBSETM52_mechCool.awk" -v max='liv' -v min="$cri_tc_opt_liv_min" -v cols="$i3_liv_cols" "$tmp_dir_tmp/resultant_temp.txt")"
    else
      opt_deviation_liv="$(awk -f "$script_dir/get_deviation_timeStep.awk" -v max="$cri_tc_opt_liv_max" -v min="$cri_tc_opt_liv_min" -v cols="$i3_liv_cols" "$tmp_dir_tmp/resultant_temp.txt")"
    fi
    i2_col=1
    for i1 in "${array_liv_zoneNums[@]}"; do      
      i0="$((i1-1))"
      if ${array_is_occ[i0]}; then
        ((i2_col++))
        if [ "$cri_tc_opt_liv_max" == 'CIBSE TM52' ]; then
          array_zone_desc[i0]="${array_zone_desc[i0]}
$(echo "$opt_deviation_liv" | awk -f "$script_dir/check_deviation_timeStep_CIBSETM52.awk" -v col="$i2_col" -v tsph="$timesteps")"
          if ! $fail; then
            if [ "$?" -eq 1 ]; then fail=true; fi
          fi
          array_zone_desc[i0]="${array_zone_desc[i0]}
$(echo "$opt_deviation_liv" | awk -f "$script_dir/check_deviation_timeStep.awk" -v col="$i2_col" -v met='Temperature' -v unit='C' -v min='-4' -v perc='3' -v percmin='-1')"
        else
          array_zone_desc[i0]="${array_zone_desc[i0]}
$(echo "$opt_deviation_liv" | awk -f "$script_dir/check_deviation_timeStep.awk" -v col="$i2_col" -v met='Temperature' -v unit='C' -v max='4' -v min='-4' -v perc='3' -v percmax='1' -v percmin='-1')"
        fi
        if ! $fail; then
          if [ "$?" -eq 1 ]; then fail=true; fi
        fi
      fi
    done
  fi
  if $get_tc_opt_kit && [ "${#array_kit_zoneNums[@]}" -gt 0 ]; then
    if [ "$cri_tc_opt_kit_max" == 'CIBSE TM52' ]; then
      opt_deviation_kit="$(awk -f "$script_dir/get_deviation_timeStep_CIBSETM52_mechCool.awk" -v max='kit' -v min="$cri_tc_opt_kit_min" -v cols="$i3_kit_cols" "$tmp_dir_tmp/resultant_temp.txt")"
    else
      opt_deviation_kit="$(awk -f "$script_dir/get_deviation_timeStep.awk" -v max="$cri_tc_opt_kit_max" -v min="$cri_tc_opt_kit_min" -v cols="$i3_kit_cols" "$tmp_dir_tmp/resultant_temp.txt")"
    fi
    i2_col=1
    for i1 in "${array_kit_zoneNums[@]}"; do      
      i0="$((i1-1))"
      if ${array_is_occ[i0]}; then
        ((i2_col++))
        if [ "$cri_tc_opt_kit_max" == 'CIBSE TM52' ]; then
          array_zone_desc[i0]="${array_zone_desc[i0]}
$(echo "$opt_deviation_kit" | awk -f "$script_dir/check_deviation_timeStep_CIBSETM52.awk" -v col="$i2_col" -v tsph="$timesteps")"
          if ! $fail; then
            if [ "$?" -eq 1 ]; then fail=true; fi
          fi
          array_zone_desc[i0]="${array_zone_desc[i0]}
$(echo "$opt_deviation_kit" | awk -f "$script_dir/check_deviation_timeStep.awk" -v col="$i2_col" -v met='Temperature' -v unit='C' -v min='-4' -v perc='3' -v percmin='-1')"
        else
          array_zone_desc[i0]="${array_zone_desc[i0]}
$(echo "$opt_deviation_kit" | awk -f "$script_dir/check_deviation_timeStep.awk" -v col="$i2_col" -v met='Temperature' -v unit='C' -v max='4' -v min='-4' -v perc='3' -v percmax='1' -v percmin='-1')"
        fi
        if ! $fail; then
          if [ "$?" -eq 1 ]; then fail=true; fi
        fi
      fi
    done
  fi
  if $get_tc_opt_bed && [ "${#array_bed_zoneNums[@]}" -gt 0 ]; then
    if [ "$cri_tc_opt_bed_max" == 'CIBSE TM52' ]; then
      opt_deviation_bed="$(awk -f "$script_dir/get_deviation_timeStep_CIBSETM52_mechCool.awk" -v max='bed' -v min="$cri_tc_opt_bed_min" -v cols="$i3_bed_cols" "$tmp_dir_tmp/resultant_temp.txt")"
    else
      opt_deviation_bed="$(awk -f "$script_dir/get_deviation_timeStep.awk" -v max="$cri_tc_opt_bed_max" -v min="$cri_tc_opt_bed_min" -v cols="$i3_bed_cols" "$tmp_dir_tmp/resultant_temp.txt")"
    fi
    i2_col=1
    for i1 in "${array_bed_zoneNums[@]}"; do      
      i0="$((i1-1))"
      if ${array_is_occ[i0]}; then
        ((i2_col++))
        if [ "$cri_tc_opt_bed_max" == 'CIBSE TM52' ]; then
          array_zone_desc[i0]="${array_zone_desc[i0]}
$(echo "$opt_deviation_bed" | awk -f "$script_dir/check_deviation_timeStep_CIBSETM52.awk" -v col="$i2_col" -v tsph="$timesteps")"
          if ! $fail; then
            if [ "$?" -eq 1 ]; then fail=true; fi
          fi
          array_zone_desc[i0]="${array_zone_desc[i0]}
$(echo "$opt_deviation_bed" | awk -f "$script_dir/check_deviation_timeStep.awk" -v col="$i2_col" -v met='Temperature' -v unit='C' -v min='-4' -v perc='3' -v percmin='-1')"
        else
          array_zone_desc[i0]="${array_zone_desc[i0]}
$(echo "$opt_deviation_bed" | awk -f "$script_dir/check_deviation_timeStep.awk" -v col="$i2_col" -v met='Temperature' -v unit='C' -v max='4' -v min='-4' -v perc='3' -v percmax='1' -v percmin='-1')"
        fi
        if ! $fail; then
          if [ "$?" -eq 1 ]; then fail=true; fi
        fi
      fi
    done
  fi
  if $get_tc_opt_bath && [ "${#array_bath_zoneNums[@]}" -gt 0 ]; then
    if [ "$cri_tc_opt_bath_max" == 'CIBSE TM52' ]; then
      opt_deviation_bath="$(awk -f "$script_dir/get_deviation_timeStep_CIBSETM52_mechCool.awk" -v max='bath' -v min="$cri_tc_opt_bath_min" -v cols="$i3_bath_cols" "$tmp_dir_tmp/resultant_temp.txt")"
    else
      opt_deviation_bath="$(awk -f "$script_dir/get_deviation_timeStep.awk" -v max="$cri_tc_opt_bath_max" -v min="$cri_tc_opt_bath_min" -v cols="$i3_bath_cols" "$tmp_dir_tmp/resultant_temp.txt")"
    fi
    i2_col=1
    for i1 in "${array_bath_zoneNums[@]}"; do      
      i0="$((i1-1))"
      if ${array_is_occ[i0]}; then
        ((i2_col++))
        if [ "$cri_tc_opt_bath_max" == 'CIBSE TM52' ]; then
          array_zone_desc[i0]="${array_zone_desc[i0]}
$(echo "$opt_deviation_bath" | awk -f "$script_dir/check_deviation_timeStep_CIBSETM52.awk" -v col="$i2_col" -v tsph="$timesteps")"
          if ! $fail; then
            if [ "$?" -eq 1 ]; then fail=true; fi
          fi
          array_zone_desc[i0]="${array_zone_desc[i0]}
$(echo "$opt_deviation_bath" | awk -f "$script_dir/check_deviation_timeStep.awk" -v col="$i2_col" -v met='Temperature' -v unit='C' -v min='-4' -v perc='3' -v percmin='-1')"
        else
          array_zone_desc[i0]="${array_zone_desc[i0]}
$(echo "$opt_deviation_bath" | awk -f "$script_dir/check_deviation_timeStep.awk" -v col="$i2_col" -v met='Temperature' -v unit='C' -v max='4' -v min='-4' -v perc='3' -v percmax='1' -v percmin='-1')"
        fi
        if ! $fail; then
          if [ "$?" -eq 1 ]; then fail=true; fi
        fi
      fi
    done
  fi
  if $get_tc_opt_WC && [ "${#array_WC_zoneNums[@]}" -gt 0 ]; then
    if [ "$cri_tc_opt_WC_max" == 'CIBSE TM52' ]; then
      opt_deviation_WC="$(awk -f "$script_dir/get_deviation_timeStep_CIBSETM52_mechCool.awk" -v max='WC' -v min="$cri_tc_opt_WC_min" -v cols="$i3_WC_cols" "$tmp_dir_tmp/resultant_temp.txt")"
    else
      opt_deviation_WC="$(awk -f "$script_dir/get_deviation_timeStep.awk" -v max="$cri_tc_opt_WC_max" -v min="$cri_tc_opt_WC_min" -v cols="$i3_WC_cols" "$tmp_dir_tmp/resultant_temp.txt")"
    fi
    i2_col=1
    for i1 in "${array_WC_zoneNums[@]}"; do      
      i0="$((i1-1))"
      if ${array_is_occ[i0]}; then
        ((i2_col++))
        if [ "$cri_tc_opt_WC_max" == 'CIBSE TM52' ]; then
          array_zone_desc[i0]="${array_zone_desc[i0]}
$(echo "$opt_deviation_WC" | awk -f "$script_dir/check_deviation_timeStep_CIBSETM52.awk" -v col="$i2_col" -v tsph="$timesteps")"
          if ! $fail; then
            if [ "$?" -eq 1 ]; then fail=true; fi
          fi
          array_zone_desc[i0]="${array_zone_desc[i0]}
$(echo "$opt_deviation_WC" | awk -f "$script_dir/check_deviation_timeStep.awk" -v col="$i2_col" -v met='Temperature' -v unit='C' -v min='-4' -v perc='3' -v percmin='-1')"
        else
          array_zone_desc[i0]="${array_zone_desc[i0]}
$(echo "$opt_deviation_WC" | awk -f "$script_dir/check_deviation_timeStep.awk" -v col="$i2_col" -v met='Temperature' -v unit='C' -v max='4' -v min='-4' -v perc='3' -v percmax='1' -v percmin='-1')"
        fi
        if ! $fail; then
          if [ "$?" -eq 1 ]; then fail=true; fi
        fi
      fi
    done
  fi
  if $get_tc_opt_hall && [ "${#array_hall_zoneNums[@]}" -gt 0 ]; then
    if [ "$cri_tc_opt_hall_max" == 'CIBSE TM52' ]; then
      opt_deviation_hall="$(awk -f "$script_dir/get_deviation_timeStep_CIBSETM52_mechCool.awk" -v max='hall' -v min="$cri_tc_opt_hall_min" -v cols="$i3_hall_cols" "$tmp_dir_tmp/resultant_temp.txt")"
    else
      opt_deviation_hall="$(awk -f "$script_dir/get_deviation_timeStep.awk" -v max="$cri_tc_opt_hall_max" -v min="$cri_tc_opt_hall_min" -v cols="$i3_hall_cols" "$tmp_dir_tmp/resultant_temp.txt")"
    fi
    i2_col=1
    for i1 in "${array_hall_zoneNums[@]}"; do      
      i0="$((i1-1))"
      if ${array_is_occ[i0]}; then
        ((i2_col++))
        if [ "$cri_tc_opt_hall_max" == 'CIBSE TM52' ]; then
          array_zone_desc[i0]="${array_zone_desc[i0]}
$(echo "$opt_deviation_hall" | awk -f "$script_dir/check_deviation_timeStep_CIBSETM52.awk" -v col="$i2_col" -v tsph="$timesteps")"
          if ! $fail; then
            if [ "$?" -eq 1 ]; then fail=true; fi
          fi
          array_zone_desc[i0]="${array_zone_desc[i0]}
$(echo "$opt_deviation_hall" | awk -f "$script_dir/check_deviation_timeStep.awk" -v col="$i2_col" -v met='Temperature' -v unit='C' -v min='-4' -v perc='3' -v percmin='-1')"
        else
          array_zone_desc[i0]="${array_zone_desc[i0]}
$(echo "$opt_deviation_hall" | awk -f "$script_dir/check_deviation_timeStep.awk" -v col="$i2_col" -v met='Temperature' -v unit='C' -v max='4' -v min='-4' -v perc='3' -v percmax='1' -v percmin='-1')"
        fi
        if ! $fail; then
          if [ "$?" -eq 1 ]; then fail=true; fi
        fi
      fi
    done
  fi

  # Get fresh air supply deviation.
  if $get_aq_fas; then

    # Combine data into a single file.
    awk -f "$script_dir/combine_columnData.awk" "$tmp_dir_tmp"/air_from_ambient_z*.txt > "$tmp_dir_tmp/air_from_ambient.txt"
    awk -f "$script_dir/combine_columnData.awk" "$tmp_dir_tmp"/air_total_extract_z*.txt > "$tmp_dir_tmp/air_total_extract.txt"

    if [ "$cri_aq_fas_min" == 'approved document F' ]; then
      # Approved document F criteria:
      # 5.5: Minimum extract ventilation in -
      #      kitchens 13 l/s
      #      bathrooms 8 l/s
      #      WC 6 l/s
      # 5.6: Minimum whole building l/s ventilation rate
      #      depending on number of bedrooms
      # 5.7: Windows in lounges and bedrooms
      #      providing 4 AC/h minimum purge ventilation

      # Assess whole building minimum ventilation rate.
      awk -f "$script_dir/combine_freshAirSupply.awk" "$tmp_dir_tmp/air_from_ambient.txt" > "$tmp_dir_tmp/air_from_ambient_sum.txt"
      # Check number of bedrooms.
      num_beds="${#array_bed_zoneNums[@]}"
      min_wbvr="$(echo "$num_beds" | awk '{print ($1-1)*4+13}')"
      # Get deviation.
      aq_fas_deviation_wbvr="$(awk -f "$script_dir/get_deviation_timeStep.awk" -v min="$min_wbvr" "$tmp_dir_tmp/air_from_ambient_sum.txt")"
      # Check 10% failure criteria.
      wbvr_limit="$(echo "$min_wbvr" | awk '{print -$1*'"${limit_multiplier}}")"
      desc="${desc}
$(echo "$aq_fas_deviation_wbvr" | awk -f "$script_dir/check_deviation_timeStep.awk" -v min="$wbvr_limit" -v perc='10' -v col=2 -v met='Whole building ventilation rate' -v unit='l/ s' -v notocc='1')"
      if ! $fail; then
        if [ "$?" -eq 1 ]; then fail=true; fi
      fi

      # Assess maximum ventilation rate against minimum extract criteria
      # for kitchens, bathrooms and WCs.
      # Get column lists for these zone types.
      i2_col=1
      for i0 in "${array_zone_indices[@]}"; do      
        if [ "${array_zone_AFNnodNums[i0]}" -gt 0 ]; then
          ((i2_col+=1))
          i1="$((i0+1))"
          if containsElement "$i1" "${array_kit_zoneNums[@]}"; then
            i2_kit_cols="${i2_kit_cols}${i2_col},"
          fi
          if containsElement "$i1" "${array_bath_zoneNums[@]}"; then
            i2_bath_cols="${i2_bath_cols}${i2_col},"
          fi
          if containsElement "$i1" "${array_WC_zoneNums[@]}"; then
            i2_WC_cols="${i2_WC_cols}${i2_col},"
          fi
        fi
      done
      # Get deviation.
      aq_fas_deviation_ex_kit="$(awk -f "$script_dir/get_deviation_timeStep.awk" -v max='12.99' -v cols="$i2_kit_cols" "$tmp_dir_tmp/air_total_extract.txt")"
      aq_fas_deviation_ex_bath="$(awk -f "$script_dir/get_deviation_timeStep.awk" -v max='7.99' -v cols="$i2_bath_cols" "$tmp_dir_tmp/air_total_extract.txt")"
      aq_fas_deviation_ex_WC="$(awk -f "$script_dir/get_deviation_timeStep.awk" -v max='5.99' -v cols="$i2_WC_cols" "$tmp_dir_tmp/air_total_extract.txt")"
      # Check inverse criteria.
      # If we have any positive deviation, it means the maximum extract
      # rate is above the minimum criterion, so the model passes.
      # Kitchens.
      i2_col=1
      for i1 in "${array_kit_zoneNums[@]}"; do
        i0="$((i1-1))"
        if [ "${array_zone_AFNnodNums[i0]}" -gt 0 ]; then
          ((i2_col++))
          echo "$aq_fas_deviation_ex_kit" | awk -f "$script_dir/check_deviation_timeStep.awk" -v max='0.01' -v col="$i2_col" -v notocc='1' > /dev/null
          if [ "$?" -eq 0 ]; then
            if ! $fail; then fail=true; fi
            if [ "${array_zone_desc[i0]}" == '' ]; then
              array_zone_desc[i0]="Extract ventilation rate does not meet the requirement of 13 l/ s."
            else
              array_zone_desc[i0]="${array_zone_desc[i0]}
Extract ventilation rate does not meet the requirement of 13 l/ s."
            fi    
          fi
        fi
      done
      # Bathrooms.
      i2_col=1
      for i1 in "${array_bath_zoneNums[@]}"; do
        i0="$((i1-1))"
        if [ "${array_zone_AFNnodNums[i0]}" -gt 0 ]; then
          ((i2_col++))
          echo "$aq_fas_deviation_ex_bath" | awk -f "$script_dir/check_deviation_timeStep.awk" -v max='0.01' -v col="$i2_col" -v notocc='1' > /dev/null
          if [ "$?" -eq 0 ]; then
            if ! $fail; then fail=true; fi
            if [ "${array_zone_desc[i0]}" == '' ]; then
              array_zone_desc[i0]="Extract ventilation rate does not meet the requirement of 8 l/ s."
            else
              array_zone_desc[i0]="${array_zone_desc[i0]}
Extract ventilation rate does not meet the requirement of 8 l/ s."
            fi    
          fi
        fi
      done
      # WCs.
      i2_col=1
      for i1 in "${array_WC_zoneNums[@]}"; do
        i0="$((i1-1))"
        if [ "${array_zone_AFNnodNums[i0]}" -gt 0 ]; then
          ((i2_col++))
          echo "$aq_fas_deviation_ex_WC" | awk -f "$script_dir/check_deviation_timeStep.awk" -v max='0.01' -v col="$i2_col" -v notocc='1' > /dev/null
          if [ "$?" -eq 0 ]; then
            if ! $fail; then fail=true; fi
            if [ "${array_zone_desc[i0]}" == '' ]; then
              array_zone_desc[i0]="Extract ventilation rate does not meet the requirement of 6 l/ s."
            else
              array_zone_desc[i0]="${array_zone_desc[i0]}
Extract ventilation rate does not meet the requirement of 6 l/ s."
            fi    
          fi
        fi
      done

      # Assess maximum ventilation rate against minimum purge ventilation criteria
      # for occupied lounges, and bedrooms.
      # Get time step per zone AC/h.
      multlist="$(echo "${array_zone_volumes[@]}" | awk 'BEGIN{ORS=",";OFS=","}{for (i=1;i<=NF;i++) {v=(60*60)/(1000*$i);print v,v}}')"
      awk -f "$script_dir/convert_timeStep.awk" -v multlist="$multlist" "$tmp_dir_tmp/air_from_ambient.txt" > "$tmp_dir_tmp/air_from_ambient_ACh.txt"
      # Assess maximum of "from ambient" and "to ambient" columns for each time step.
      awk -f "$script_dir/combine_2columnMax.awk" "$tmp_dir_tmp/air_from_ambient_ACh.txt" > "$tmp_dir_tmp/air_from_ambient_ACh_max.txt"
      # Get column lists for these zone types.
      i2_col=1
      for i0 in "${array_zone_indices[@]}"; do      
        if [ "${array_zone_AFNnodNums[i0]}" -gt 0 ]; then
          ((i2_col++))
          if ${array_is_occ[i0]}; then
            i1="$((i0+1))"
            if containsElement "$i1" "${array_liv_zoneNums[@]}"; then
              i2_liv_cols="${i2_liv_cols}${i2_col},"
            fi
            if containsElement "$i1" "${array_bed_zoneNums[@]}"; then
              i2_bed_cols="${i2_bed_cols}${i2_col},"
            fi
          fi
        fi
      done
      # Get deviation.
      aq_fas_deviation_ex_liv="$(awk -f "$script_dir/get_deviation_timeStep.awk" -v max='3.99' -v cols="$i2_liv_cols" "$tmp_dir_tmp/air_from_ambient_ACh_max.txt")"
      aq_fas_deviation_ex_bed="$(awk -f "$script_dir/get_deviation_timeStep.awk" -v max='3.99' -v cols="$i2_bed_cols" "$tmp_dir_tmp/air_from_ambient_ACh_max.txt")"
      # Check inverse criteria.
      # If we have any positive deviation, it means the maximum purge ventilation
      # rate is above the minimum criterion, so the model passes.
      # Lounges.
      i2_col=1
      for i1 in "${array_liv_zoneNums[@]}"; do
        i0="$((i1-1))"
        if [ "${array_zone_AFNnodNums[i0]}" -gt 0 ]; then
          if ${array_is_occ[i0]}; then
            ((i2_col++))
            echo "$aq_fas_deviation_ex_liv" | awk -f "$script_dir/check_deviation_timeStep.awk" -v max='0.01' -v col="$i2_col" -v notocc='1' > /dev/null
            if [ "$?" -eq 0 ]; then
              if ! $fail; then fail=true; fi
              if [ "${array_zone_desc[i0]}" == '' ]; then
                array_zone_desc[i0]="Purge ventilation rate does not meet the requirement of 4 AC/ h."
              else
                array_zone_desc[i0]="${array_zone_desc[i0]}
Purge ventilation rate does not meet the requirement of 4 AC/ h."
              fi    
            fi
          fi
        fi
      done
      # Bedrooms
      i2_col=1
      for i1 in "${array_bed_zoneNums[@]}"; do
        i0="$((i1-1))"
        if [ "${array_zone_AFNnodNums[i0]}" -gt 0 ]; then
          if ${array_is_occ[i0]}; then
            ((i2_col++))
            echo "$aq_fas_deviation_ex_bed" | awk -f "$script_dir/check_deviation_timeStep.awk" -v max='0.01' -v col="$i2_col" -v notocc='1' > /dev/null
            if [ "$?" -eq 0 ]; then
              if ! $fail; then fail=true; fi
              if [ "${array_zone_desc[i0]}" == '' ]; then
                array_zone_desc[i0]="Purge ventilation rate does not meet the requirement of 4 AC/ h."
              else
                array_zone_desc[i0]="${array_zone_desc[i0]}
Purge ventilation rate does not meet the requirement of 4 AC/ h."
              fi              
            fi
          fi
        fi
      done

    else
      # We only have a limiting value; assess whole-building air supply.
      # Sum all "from ambient" and all "to ambient" columns, and then average the two.
      # If we have an AC/h criterion, need to convert the l/s values.
      # A blank value of "total volumne" tells the awk script it does not need to convert.
      if [ "$cri_aq_fas_unit" == 'l/ s' ]; then
        total_volume=''
      fi
      echo "$total_volume"
      awk -f "$script_dir/combine_freshAirSupply.awk" -v vol="$total_volume" "$tmp_dir_tmp/air_from_ambient.txt" > "$tmp_dir_tmp/air_from_ambient_sum.txt"
      # Get deviation.
      aq_fas_deviation="$(awk -f "$script_dir/get_deviation_timeStep.awk" -v min="$cri_aq_fas_min" "$tmp_dir_tmp/air_from_ambient_sum.txt")"
      # Check 10% failure criteria.
      aq_fas_limit="$(echo "$cri_aq_fas_min" | awk '{print -$1*'"${limit_multiplier}}")"
      desc="${desc}
$(echo "$aq_fas_deviation" | awk -f "$script_dir/check_deviation_timeStep.awk" -v min="$aq_fas_limit" -v perc='10' -v col=2 -v met='Whole building ventilation rate' -v unit="$cri_aq_fas_unit" -v notocc='1')"
      if ! $fail; then
        if [ "$?" -eq 1 ]; then fail=true; fi
      fi
    fi
  fi

  # Get CO2 deviation in occupied zones.
  if $get_aq_CO2; then
    # Combine data into a single file.
    awk -f "$script_dir/combine_columnData.awk" "$tmp_dir_tmp"/CO2_concentration_z*.txt > "$tmp_dir_tmp/CO2_concentration.txt"
    # Get deviation.
    # Results from ESP-r are in g/kg, so we need to divide the PPM (by mass) criteria by 1000.
    cri_esp="$(echo "$cri_aq_CO2_max" | awk '{print $1/1000}')"
    aq_CO2_deviation="$(awk -f "$script_dir/get_deviation_timeStep.awk" -v max="$cri_esp" "$tmp_dir_tmp/CO2_concentration.txt")" 
    # Check 10% failure criteria.
    aq_CO2_limit="$(echo "$cri_esp" | awk '{print -$1*'"${limit_multiplier}}")"
    i2_col=1
    for i1 in "${array_occ_zoneNums[@]}"; do      
      i0="$((i1-1))"
      ((i2_col++))
      array_zone_desc[i0]="${array_zone_desc[i0]}$(echo "$aq_CO2_deviation" | awk -f "$script_dir/check_deviation_timeStep.awk" -v col="$i2_col" -v met='CO2 concentration' -v unit='g/kg' -v max="$aq_CO2_limit" -v perc='10')"
      if ! $fail; then
        if [ "$?" -eq 1 ]; then fail=true; fi
      fi
    done
  fi

  # Debug.
  echo "$en_heat_deviation" > "$tmp_dir_tmp/en_heat_deviation.trace"
  echo "$opt_deviation_liv" > "$tmp_dir_tmp/opt_deviation_liv.trace"
  echo "$opt_deviation_kit" > "$tmp_dir_tmp/opt_deviation_kit.trace"
  echo "$opt_deviation_bed" > "$tmp_dir_tmp/opt_deviation_bed.trace"
  echo "$opt_deviation_bath" > "$tmp_dir_tmp/opt_deviation_bath.trace"
  echo "$opt_deviation_WC" > "$tmp_dir_tmp/opt_deviation_WC.trace"
  echo "$opt_deviation_hall" > "$tmp_dir_tmp/opt_deviation_hall.trace"
  echo "$aq_fas_deviation" > "$tmp_dir_tmp/aq_fas_deviation.trace"
  echo "$aq_CO2_deviation" > "$tmp_dir_tmp/aq_CO2_deviation.trace"
  echo "$desc" > "$tmp_dir_tmp/desc.trace"
  for i in "${array_zone_indices[@]}"; do
    echo "Zone ${array_zone_names[i]}:" >> "$tmp_dir_tmp/desc.trace"
    echo "${array_zone_desc[i]}" >> "$tmp_dir_tmp/desc.trace"
  done

  # At this point, if we have failed, stop the assessment.
  if $fail; then

    # Write performance flag.
    performance_flag=1
    echo "$performance_flag" > "$tmp_dir_tmp/pflag.txt"

    # Update progress file.
    echo '6' > "$tmp_dir/progress.txt" 

    # Write feedback report.
    report="$tmp_dir_tmp/report.tex"
    echo '\nonstopmode' > "$report"
    echo '\documentclass[a4paper,11pt]{report}' >> "$report"
    echo '\usepackage[tmargin=2cm,bmargin=2cm,lmargin=2cm,rmargin=2cm]{geometry}' >> "$report"
    echo '\usepackage{fontspec}' >> "$report"
    echo '\setmainfont{TeX Gyre Termes}' >> "$report"
    echo '\usepackage{underscore}' >> "$report"
    echo '\usepackage{scrextend}' >> "$report"
    echo '\setlength{\parindent}{0cm}' >> "$report"
    echo '\pagestyle{empty}' >> "$report"

    echo '\begin{document}' >> "$report"

    echo '\begin{Large}' >> "$report"
    echo 'Marathon resilience testing environment \\' >> "$report"
    echo 'Resilience assessment report \\' >> "$report"
    echo '\end{Large}' >> "$report"
    echo '' >> "$report"

    # Preamble (analysis parameters).
    if ! [ "X$preamble_file" == "X" ]; then
      cat "$preamble_file" >> "$report"
      echo '' >> "$report"
    fi

    echo 'Analysis outcomes' >> "$report"
    echo '\begin{addmargin}[0.5cm]{0cm}' >> "$report"

    echo 'The model has failed the resilience assessment. A list of reasons for failure follows.' >> "$report"
    echo '\begin{itemize}' >> "$report"
    IFS=$'\n' read -rd '' -a array_desc <<< "$desc"
    for l in "${array_desc[@]}"; do
      echo '\item '"${l//%/\\%}" >> "$report"
    done
    for i in "${array_zone_indices[@]}"; do
      if ! [ "X$(echo ${array_zone_desc[i]})" == 'X' ]; then      
        IFS=$'\n' read -rd '' -a array_desc <<< "${array_zone_desc[i]}"
        # if [ "${#array_desc[@]}" -gt 0 ]; then
          echo '\item In zone ``'"${array_zone_names[i]}\"": >> "$report"
          echo '\begin{itemize}' >> "$report"
          for l in "${array_desc[@]}"; do
            echo '\item '"${l//%/\\%}" >> "$report"
          done
          echo '\end{itemize}' >> "$report"
        # fi
      fi
    done
    echo '\end{itemize}' >> "$report"

    echo '\end{addmargin}' >> "$report"
    echo '\end{document}' >> "$report"

    # Compile report.
    rm -f "${report:0:-4}.aux"
    lualatex -halt-on-error -output-directory="$tmp_dir_tmp" "$report" > "$tmp_dir_tmp/lualatex.out"
    mv "${report:0:-4}.pdf" "$report_final"

    # Exit.
    exit 0
  fi

  ((iyear++))

done

# If we get to the end and havn't failed then the model has passed.
# Write performance flag.
performance_flag=0
echo "$performance_flag" > "$tmp_dir_tmp/pflag.txt"

# Exit.
exit 0