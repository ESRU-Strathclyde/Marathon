#! /bin/bash

# Resilience Assessment script for domestic buildings without mechanical cooling.
# ESP-r implementation.
# Version 1.0 of March 2020.

# Implementation-specific error codes:

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
# do_detailed_report=false

# Get paths to call the various other scripts used by this program.
script_dir="$(dirname "$(readlink -f "$0")")"
common_dir="$script_dir/../../common"

# Parse command line.
while getopts ":hvf:p:t:s:d:r:R:j:c:P:U" opt; do
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
    R) do_detailed_report=true
       detailed_report_final="$OPTARG";;
    \?) echo "Error: unknown option -$OPTARG. Use option -h for help." >&2
        exit 107;;
    :) echo "Error: option -$OPTARG requires and argument." >&2
       exit 107;;
  esac
done
shift $((OPTIND-1))
building="$1"
shift $((OPTIND-1))
cri_en_heating="$1"
shift $((OPTIND-1))
cri_en_lighting="$1"
shift $((OPTIND-1))
cri_en_equipment="$1"
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
  exit 107
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
    exit 107
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
    exit 201
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

if "$do_detailed_report"; then
  detailed_report="$tmp_dir/detailed_report.tex"
fi

