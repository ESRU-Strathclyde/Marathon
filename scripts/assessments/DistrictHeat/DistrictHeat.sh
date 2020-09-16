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

# Resilience Assessment script for district heating networks.
# ESP-r implementation.
# Version 1.0 of May 2020.

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
timesteps=60
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
while getopts ":hvf:p:t:s:d:r:P:SIC" opt; do
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
removeX 'cri_eff' "$1"
shift
removeX 'cri_loss' "$1"
shift
removeX 'cri_temp' "$1"

if "$information" ; then
  echo
  echo " Usage: ./DistrictHeat.sh [OPTIONS] model-cfg-file"
  echo
  echo " Resilience Assessment script for district heating network models."
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



if $verbose; then echo "***** DISTRICT HEAT RA START"; fi

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

# First, check some basics and see if this is a plant only model.
"$common_dir/esp-query/esp-query.py" -o "$tmp_dir/query_results.txt" "$building" "model_name" "weather_file" "is_building" "plant_network" "plant_components" "plant_comp_names"

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

# Check for a building component.
i_building="$(awk -f "$common_dir/esp-query/processOutput_getIsBuilding.awk" "$tmp_dir/query_results.txt")"
if [ "X$i_building" == 'X' ]; then
  echo 'Error: could not find building flag.' >&2
  exit 666
else
  if [ "$i_building" == 1 ]; then
    is_building=true
  elif [ "$i_building" == 0 ]; then
    is_building=false
  else
    echo 'Error: unrecognised building flag.' >&2
    exit 666
  fi
fi

# Check for a plant network.
plant_network="$(awk -f "$common_dir/esp-query/processOutput_getPlantNetwork.awk" "$tmp_dir/query_results.txt")"
if [ "X$plant_network" == 'X' ]; then
  echo 'Error: no plant network found.' >&2
  exit 666
else
  is_plant=true
fi

# Check plant components.
if $is_plant; then
  plant_components="$(awk -f "$common_dir/esp-query/processOutput_getSpaceSeparatedPlantComponents.awk" "$tmp_dir/query_results.txt")"
  plant_comp_names="$(awk -f "$common_dir/esp-query/processOutput_getSpaceSeparatedPlantCompNames.awk" "$tmp_dir/query_results.txt")"
  if [ "X$plant_components" == 'X' ] || [ "X$plant_comp_names" == 'X' ]; then
    echo 'Error: no components detected in plant network.' >&2
    exit 666
  else
    # Sort through plant components.
    # We are looking for:
    # components with "gen" in the name, taken as generators
    # components with "load" in the name, taken as loads
    # component indices 43, 116, ... 
    # do not have "additional outputs" in ESP-r terms, so must be
    # omitted when forming component index lists.
    # TODO: this list is not exhaustive
    array_nonAO_pcomp_nums=(43 116)
    array_pcomp_nums=($plant_components)
    array_pcomp_names=($plant_comp_names)
    if [ "${#array_pcomp_nums[@]}" -ne "${#array_pcomp_names[@]}" ]; then
      echo 'Error: problem scanning plant components.' >&2
      exit 666
    fi
    num_pcomps="${#array_pcomp_nums[@]}"
    i0_pcomp=0
    i1_AO_pcomp=0
    i0_AO_pcomp_gen=-1
    i0_AO_pcomp_load=-1
    i0_pcomp_load=-1
    while [ "$i0_pcomp" -lt "$num_pcomps" ]; do
      pcomp_num="${array_pcomp_nums[i0_pcomp]}"
      pcomp_name="${array_pcomp_names[i0_pcomp]}"
      is_AO=true
      for i in "${array_nonAO_pcomp_nums[@]}"; do
        if [ "$pcomp_num" -eq "$i" ]; then
          is_AO=false
          break
        fi
      done
      if $is_AO; then
        ((i1_AO_pcomp++))
        if [[ "$pcomp_name" == *gen* ]]; then
          ((i0_AO_pcomp_gen++))
          array_AO_pcomp_gen_inds[i0_AO_pcomp_gen]="$i1_AO_pcomp"
        fi
        if [[ "$pcomp_name" == *load* ]]; then
          ((i0_AO_pcomp_load++))
          array_AO_pcomp_load_inds[i0_AO_pcomp_load]="$i1_AO_pcomp"
        fi
      fi
      i1_pcomp="$((i0_pcomp+1))"
      if [[ "$pcomp_name" == *load* ]]; then
        ((i0_pcomp_load++))
        array_pcomp_load_inds[i0_pcomp_load]="$i1_pcomp"
        array_pcomp_load_names[i1_pcomp]="$pcomp_name"
      fi
      ((i0_pcomp++))
    done
  fi
fi

# If there is no building component, set domain flags.
# TODO: If there is, check for domains.
# if $is_building; then
# else
  is_afn=false
  is_CFD=false
# fi

# Get results file location, simulation period, timesteps and startup days if a simulation preset is defined.
sim_results_preset=""
mf_results_preset=""
cfd_results_preset=""
plt_results_preset=""
if ! [ "X$preset" == "X" ]; then

# Check if simulation preset exists. If it doesn't, fall back on default values.
  preset_check="$(awk -v preset="$preset" -f "$script_dir/check_simPreset_exists.awk" "$building")"
  if  [ "$preset_check" == "0" ]; then
    echo "Warning: simulation preset \"$preset\" not found, using default simulation setup."
    preset=""

  else
    if $is_building; then
      sim_results_preset="$(awk -v mode="$preset_check" -v preset="$preset" -f "$script_dir/get_simPreset_resFile.awk" "$building")"
      if [ "X$sim_results_preset" == "X" ]; then
        echo "Error: could not retrieve simulation results library name." >&2
        exit 202
      fi
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
    if $is_plant; then
      plt_results_preset="$(awk -v mode="$preset_check" -v preset="$preset" -f "$script_dir/get_simPreset_plrFile.awk" "$building")"
      if [ "X$plt_results_preset" == "X" ]; then
        echo "Error: could not retrieve plant results library name." >&2
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

# This is not true of the mass flow results library or the plant library...
#  if $is_afn; then mf_results_preset=~/"$(basename "$mf_results_preset")"; fi

# but is true of the CFD library.
  if $is_CFD; then cfd_results_preset=~/"$(basename "$cfd_results_preset")"; fi
fi

# Set results library names.
if $is_building; then sim_results="${results_file}.res"; fi
if $is_afn; then mf_results="${results_file}.mfr"; fi
if $is_CFD; then cfd_results="${results_file}.dfr"; fi
if $is_plant; then plt_results="${results_file}.plr"; fi



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
  python3 "$common_dir/SyntheticWeather/indra.py" --train 1 --station_code 'ra' --n_samples "$num_years" --path_file_in "$tmp_dir/weather_base.txt" --path_file_out "$weather_base_abs.txt" --file_type 'espr' --store_path "$tmp_dir/indra" 1>"$tmp_dir/indra.out" 2>&1
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
  plt_results_tmp="$plt_results"
else
  cd ..
  building_tmp="$up_one/$building"
  building_dir_tmp="$(dirname "$building_tmp")"
  tmp_dir_tmp="$up_one/$tmp_dir"
  sim_results_tmp="$up_one/$sim_results"
  mf_results_tmp="$up_one/$mf_results"
  cfd_results_tmp="$up_one/$cfd_results"
  plt_results_tmp="$up_one/$plt_results"
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
    if $is_building; then rm -f "$sim_results_tmp" > /dev/null; fi
    if $is_afn; then rm -f "$mf_results_tmp" > /dev/null; fi
    if $is_CFD; then 
      rm -f "$cfd_results_tmp" > /dev/null
      rm -f "$building_dir_tmp"/ACC-actions_*.rec > /dev/null
      rm -f "$building_dir_tmp"/cfd3dascii_* > /dev/null
    fi
    if $is_plant; then rm -f "$plt_results_tmp" > /dev/null; fi

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

      if $is_building; then mv "$sim_results_preset" "$sim_results_tmp"; fi
      if $is_afn; then mv "$mf_results_preset" "$mf_results_tmp"; fi
      if $is_CFD; then mv "$cfd_results_preset" "$cfd_results_tmp"; fi
      if $is_plant; then mv "$plt_results_preset" "$plt_results_tmp"; fi
    else
      bps_script="
c"
      if $is_building; then
        bps_script="
${sim_results_tmp}"
      fi
      if $is_afn; then
        bps_script="$bps_script
${mf_results_tmp}"
      fi
      if $is_CFD; then
        bps_script="$bps_script
${cfd_results_tmp}"
      fi
      if $is_plant; then
        bps_script="$bps_script
${plt_results_tmp}"
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
#       if $is_ucn; then
#         bps_script="$bps_script
# d
# -"
#       fi
      bps_script="$bps_script
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

    if $is_building && ! [ -f "$sim_results_tmp" ]; then
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

    if $is_plant && ! [ -f "$plt_results_tmp" ]; then
      echo "Error: simulation failed, please check model manually." >&2
      exit 104
    fi
  fi

  # * EXTRACT RESULTS *

  rm "$tmp_dir_tmp/res.script" "$tmp_dir_tmp/res.out" 1>/dev/null 2>&1

  # Update progress file.
  echo '4' > "$tmp_dir_tmp/progress.txt"

  # if ! [ "X$up_one" == "X" ]; then
  #   cd .. || exit 1
  # fi

  if $is_building; then
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

  if $is_plant; then
    # Get timestep energy generated.
    for pcomp_gen_ind in "${array_AO_pcomp_gen_inds[@]}"; do
      i_pad="$(printf "%03d" $pcomp_gen_ind)"
      res_script="$res_script
>
b
${tmp_dir_tmp}/gen_kW_c${i_pad}.txt

h
<
1
${pcomp_gen_ind}
c
-
!
>
/"
    done

    # Get timestep generator efficiency.
    for pcomp_gen_ind in "${array_AO_pcomp_gen_inds[@]}"; do
      i_pad="$(printf "%03d" $pcomp_gen_ind)"
      res_script="$res_script
>
b
${tmp_dir_tmp}/gen_efficiency_frac_c${i_pad}.txt

h
<
1
${pcomp_gen_ind}
b
-
!
>
/"
    done

    # Get timestep energy consumed.
    for pcomp_load_ind in "${array_AO_pcomp_load_inds[@]}"; do
      i_pad="$(printf "%03d" $pcomp_load_ind)"
      res_script="$res_script
>
b
${tmp_dir_tmp}/load_W_c${i_pad}.txt

h
<
1
${pcomp_load_ind}
a
-
!
>
/"
    done

    # Get timestep residual demand.
    for pcomp_load_ind in "${array_AO_pcomp_load_inds[@]}"; do
      i_pad="$(printf "%03d" $pcomp_load_ind)"
      res_script="$res_script
>
b
${tmp_dir_tmp}/load_residual_W_c${i_pad}.txt

h
<
1
${pcomp_load_ind}
c
-
!
>
/"
    done

    # Get timestep return temperatures.
    for pcomp_load_ind in "${array_pcomp_load_inds[@]}"; do
      i_pad="$(printf "%03d" $pcomp_load_ind)"
      res_script="$res_script
>
b
${tmp_dir_tmp}/return_temps_c${i_pad}.txt

a
<
1
${pcomp_load_ind}
!
>
/"
    done
  fi

  res_script="$res_script
-
"

  echo "$res_script" >> "$tmp_dir_tmp/res.script"

  # Run res.
  res -mode script -file "$plt_results_tmp" >> "$tmp_dir_tmp/res.out" <<~
${res_script}
~



  # * PROCESS RESULTS *

  # Combine column data.
  awk -f "$script_dir/combine_columnData.awk" "$tmp_dir_tmp/"gen_kW_c*.txt > "$tmp_dir_tmp/gen_kW.txt"
  awk -f "$script_dir/combine_columnData.awk" "$tmp_dir_tmp/"load_W_c*.txt > "$tmp_dir_tmp/load_W.txt"

  # Convert W to Wh.
  WtoWh="$(echo "$timesteps" | awk '{print 1/$1}')"
  awk -f "$script_dir/convert_timeStep.awk" -v mult="$WtoWh" "$tmp_dir_tmp/gen_kW.txt" > "$tmp_dir_tmp/gen_kWh.txt"
  awk -f "$script_dir/convert_timeStep.awk" -v mult="$WtoWh" "$tmp_dir_tmp/load_W.txt" > "$tmp_dir_tmp/load_Wh.txt"

  # Aggregate energy generated.
  total_gen_kWh="$(awk -f "$script_dir/aggregate_all.awk" "$tmp_dir_tmp/gen_kWh.txt")"
  echo "total_gen_kWh $total_gen_kWh"

  # Aggregate energy consumed.
  total_load_Wh="$(awk -f "$script_dir/aggregate_all.awk" "$tmp_dir_tmp/load_Wh.txt")"
  echo "total_load_Wh $total_load_Wh"

  # Energy generated - energy consumed = energy lost
  total_loss_kWh="$(echo "$total_gen_kWh" "$total_load_Wh" | awk '{print $1+($2/1000)}')"
  echo "total_loss_kWh $total_loss_kWh"

  # Check loss as a percentage of energy generated.
  loss_perc="$(echo "$total_loss_kWh $total_gen_kWh" | awk '{print $1/$2*100}')"
  echo "loss_perc $loss_perc"
  echo "$loss_perc" > "$tmp_dir_tmp/loss_perc.txt"

  # Now check deviation and check for failure.
  loss_deviation="$(awk -f "$script_dir/get_deviation_value.awk" -v max="$cri_loss" "$tmp_dir_tmp/loss_perc.txt")"
  loss_limit="$(echo "$cri_loss" | awk '{print $1*'"${limit_multiplier}}")"
  desc="${desc}
$(echo "$loss_deviation" | awk -f "$script_dir/check_deviation_value.awk" -v max="$loss_limit" -v met='Network losses' -v unit='%')"
  if ! $fail; then
    if [ "$?" -eq 1 ]; then fail=true; fi
  fi

  # Check residual demand.
  # Combine column data.
  awk -f "$script_dir/combine_columnData.awk" "$tmp_dir_tmp/"load_residual_W_c*.txt > "$tmp_dir_tmp/load_residual_W.txt"

  # Results from ESP-r are in W, so convert to kW first.
  load_residual_kW="$(awk -f "$script_dir/convert_timeStep.awk" -v mult=0.001 "$tmp_dir_tmp/load_residual_W.txt")"
  echo "$load_residual_kW" > "$tmp_dir_tmp/load_residual_kW.txt"

  # Now check deviation and failure
  resid_deviation="$(awk -f "$script_dir/get_deviation_timeStep.awk" -v max="$cri_resid" "$tmp_dir_tmp/load_residual_kW.txt")"
  i2_col=1
  for i1 in "${array_pcomp_load_inds[@]}"; do
    ((i2_col++))
    array_load_desc[i1]="${array_load_desc[i1]}
$(echo "$resid_deviation" | awk -f "$script_dir/check_deviation_timeStep.awk" -v col="$i2_col" -v max="0" -v perc='10' -v met='Residual demand' -v unit='kW' -v notocc='1')"
    if ! $fail; then
      if [ "$?" -eq 1 ]; then fail=true; fi
    fi
  done

  # Check boiler efficiency.
  # Combine column data.
  awk -f "$script_dir/combine_columnData.awk" "$tmp_dir_tmp/"gen_efficiency_frac_c*.txt > "$tmp_dir_tmp/gen_efficiency_frac.txt"

  # Convert efficiency fraction to percentage.
  gen_efficiency_perc="$(awk -f "$script_dir/convert_timeStep.awk" -v mult=100 "$tmp_dir_tmp/gen_efficiency_frac.txt")"
  echo "$gen_efficiency_perc" > "$tmp_dir_tmp/gen_efficiency_perc.txt"

  # Now check deviation and failure.
  eff_deviation="$(awk -f "$script_dir/get_deviation_timeStep.awk" -v min="$cri_eff" "$tmp_dir_tmp/gen_efficiency_perc.txt")"
  i2_col=1
  for i1 in "${array_pcomp_load_inds[@]}"; do
    ((i2_col++))
    array_load_desc[i1]="${array_load_desc[i1]}
$(echo "$eff_deviation" | awk -f "$script_dir/check_deviation_timeStep.awk" -v col="$i2_col" -v min="0" -v perc='10' -v met='Generator efficiency' -v unit='%' -v notocc='1')"
    if ! $fail; then
      if [ "$?" -eq 1 ]; then fail=true; fi
    fi
  done

  # Check return temperatures.
  # Combine column data.
  awk -f "$script_dir/combine_columnData.awk" "$tmp_dir_tmp/"return_temps_c*.txt > "$tmp_dir_tmp/return_temps.txt"

  temp_limit="$(echo "$cri_temp" | awk '{print $1*'"${limit_multiplier}}")"
  temp_deviation="$(awk -f "$script_dir/get_deviation_timeStep.awk" -v max="$cri_temp" "$tmp_dir_tmp/return_temps.txt")"
  i2_col=1
  for i1 in "${array_pcomp_load_inds[@]}"; do
    ((i2_col++))
    array_load_desc[i1]="${array_load_desc[i1]}
$(echo "$temp_deviation" | awk -f "$script_dir/check_deviation_timeStep.awk" -v col="$i2_col" -v max="$temp_limit" -v perc='10' -v met='Load return temperature' -v unit='C' -v notocc='1')"
    if ! $fail; then
      if [ "$?" -eq 1 ]; then fail=true; fi
    fi
  done

  # Debug.
  echo "$loss_deviation" > "$tmp_dir_tmp/loss_deviation.trace"
  echo "$resid_deviation" > "$tmp_dir_tmp/resid_deviation.trace"
  echo "$eff_deviation" > "$tmp_dir_tmp/eff_deviation.trace"
  echo "$temp_deviation" > "$tmp_dir_tmp/temp_deviation.trace"
  echo "$desc" > "$tmp_dir_tmp/desc.trace"
  i=0
  for s in "${array_pcomp_load_names[@]}"; do
    echo "Load ${s}:" >> "$tmp_dir_tmp/desc.trace"
    echo "${array_load_desc[i]}" >> "$tmp_dir_tmp/desc.trace"
    ((i++))
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
    i=0
    for i in "${array_pcomp_load_inds[@]}"; do
      if ! [ "X${array_load_desc[i]}" == 'X' ]; then   
        IFS=$'\n' read -rd '' -a array_desc <<< "${array_load_desc[i]}"
        # if [ "${#array_desc[@]}" -gt 0 ]; then
        echo '\item At load ``'"${array_pcomp_load_names[i]}\"": >> "$report"        
        echo '\begin{itemize}' >> "$report"
        for l in "${array_desc[@]}"; do
          echo '\item '"${l//%/\\%}" >> "$report"
        done
        echo '\end{itemize}' >> "$report"
        # fi
      fi
      ((i++))
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