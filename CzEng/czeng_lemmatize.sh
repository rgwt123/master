#!/bin/bash

# Script constants are listed below:

PWD=$(pwd)
SCRIPT=$(basename $0)
SCRIPT_DIR=$(dirname $0)

TOOLS_DIR="$SCRIPT_DIR"/../Tools
MORPHODITA_TAGGER="$TOOLS_DIR"/morphodita/src/run_tagger
MORPOHODITA_CS_MODEL="$TOOLS_DIR"/morphodita_models/czech-morfflex-pdt-131112/czech-morfflex-pdt-131112.tagger-best_accuracy
MORPOHODITA_EN_MODEL="$TOOLS_DIR"/morphodita_models/english-morphium-wsj-140407/english-morphium-wsj-140407.tagger

PART_SIZE=1000000
UNKNOWN='\x{2022}'
ENDLINE='\x{2016}'

# Script subroutines are listed below:

function handle_options() {
  
  while [ "$#" -gt 0 ]; do
    case $1 in
      -c|--czeng)
        CZENG_FILE="$2"
        shift ;;
      -l|--lemma)
        CZENG_LEMMA_FILE="$2"
        shift ;;
      *) ;;
    esac
    shift
  done

  if [ -z "$CZENG_FILE" ] || [ ! -f "$CZENG_FILE" ]; then
    echo ">>> [$SCRIPT][$(date)] ERROR: Invalid -c|--czeng option!"
    exit 1
  fi

  if [ -z "$CZENG_LEMMA_FILE" ]; then
    echo ">>> [$SCRIPT][$(date)] ERROR: Invalid -l|--lemma option!"
    exit 1
  fi

  echo ">>> [$SCRIPT][$(date)] Option -c|--czeng = $CZENG_FILE."
  echo ">>> [$SCRIPT][$(date)] Option -l|--lemma = $CZENG_LEMMA_FILE."

}

function prepare_temp() {

  TEMP_DIR=$(mktemp -d "$SCRIPT""_XXXXX")
  czeng_file_base=$(basename $CZENG_FILE)

  TEMP_CS_FILE="$TEMP_DIR"/"$czeng_file_base"_cs
  TEMP_CS_FILE_PART="$TEMP_DIR"/"$czeng_file_base"_cs_
  TEMP_CS_LEMMA_FILE="$TEMP_DIR"/"$czeng_file_base"_cs_lemma
  TEMP_EN_FILE="$TEMP_DIR"/"$czeng_file_base"_en
  TEMP_EN_FILE_PART="$TEMP_DIR"/"$czeng_file_base"_en_
  TEMP_EN_LEMMA_FILE="$TEMP_DIR"/"$czeng_file_base"_en_lemma
  TEMP_INFO_FILE="$TEMP_DIR"/"$czeng_file_base"_info

  echo ">>> [$SCRIPT][$(date)] Temporary folder is $TEMP_DIR."
  
}

function terminate() {

  echo ">>> [$SCRIPT][$(date)] Killing process tree."
  jobs -p | xargs --no-run-if-empty kill -9

  echo ">>> [$SCRIPT][$(date)] Cleaning temporary files."
  rm -rf $TEMP_DIR

  echo ">>> [$SCRIPT][$(date)] Cleaning erroneous output."
  rm -rf $CZENG_LEMMA_FILE

  echo ">>> [$SCRIPT][$(date)] Script ended unsucessfully!"
  trap - EXIT TERM INT
  exit 1

}

# Script execution starts below:

echo ">>> [$SCRIPT][$(date)] Handling command line options."
handle_options "$@"

echo ">>> [$SCRIPT][$(date)] Starting execution in $PWD."
trap terminate EXIT TERM INT
cd $PWD

echo ">>> [$SCRIPT][$(date)] Preparing temporary folder."
prepare_temp

echo ">>> [$SCRIPT][$(date)] Separating Czech part."
cut -f 3 $CZENG_FILE > $TEMP_CS_FILE

echo ">>> [$SCRIPT][$(date)] Splitting Czech part into multiple files."
split -d -l $PART_SIZE $TEMP_CS_FILE $TEMP_CS_FILE_PART
rm -f $TEMP_CS_FILE

echo ">>> [$SCRIPT][$(date)] Replacing unknown symbols in Czech part."
perl -CSAD -pe 's/[^\s\w[:ascii:]]+/'$UNKNOWN'/g' -i $TEMP_CS_FILE_PART*

echo ">>> [$SCRIPT][$(date)] Marking line endings in Czech part."
perl -CSAD -pe 's/$/\ '$ENDLINE'/s' -i $TEMP_CS_FILE_PART*

rm -f $TEMP_CS_LEMMA_FILE
for temp_cs_file_part in $TEMP_CS_FILE_PART*; do

  echo ">>> [$SCRIPT][$(date)] Running Tagger on Czech part $temp_cs_file_part."
  ( $MORPHODITA_TAGGER --convert_tagset=strip_lemma_id --output=vertical $MORPOHODITA_CS_MODEL $temp_cs_file_part | tee \
    >( cut -f 2 | tr -s '[:space:]' ' ' | perl -CSAD -pe 's/ *'$ENDLINE' */\n/g' >> $TEMP_CS_LEMMA_FILE ) \
  ) 3>&1 1>&2 2>&3 3>&- > /dev/null | awk '{ print ">>> [morphodita]["strftime()"] " $0; fflush(); }'

  rm -f $temp_cs_file_part

done

echo ">>> [$SCRIPT][$(date)] Separating English part."
cut -f 4 $CZENG_FILE > $TEMP_EN_FILE

echo ">>> [$SCRIPT][$(date)] Splitting English part into multiple files."
split -d -l $PART_SIZE $TEMP_EN_FILE $TEMP_EN_FILE_PART
rm -f TEMP_EN_FILE

echo ">>> [$SCRIPT][$(date)] Replacing unknown symbols in English part."
perl -CSAD -pe 's/[^\s\w[:ascii:]]+/'$UNKNOWN'/g' -i $TEMP_EN_FILE_PART*

echo ">>> [$SCRIPT][$(date)] Marking line endings in English part."
perl -CSAD -pe 's/$/\ '$ENDLINE'/s' -i $TEMP_EN_FILE_PART*

rm -f $TEMP_EN_LEMMA_FILE
for temp_en_file_part in $TEMP_EN_FILE_PART*; do

  echo ">>> [$SCRIPT][$(date)] Running Tagger on English part $temp_en_file_part."
  ( $MORPHODITA_TAGGER --convert_tagset=strip_lemma_id --output=vertical $MORPOHODITA_EN_MODEL $temp_en_file_part | tee \
    >( cut -f 2 | tr -s '[:space:]' ' ' | perl -CSAD -pe 's/ *'$ENDLINE' */\n/g' >> $TEMP_EN_LEMMA_FILE ) \
  ) 3>&1 1>&2 2>&3 3>&- > /dev/null | awk '{ print ">>> [morphodita]["strftime()"] " $0; fflush(); }'

  rm -f $temp_en_file_part

done

echo ">>> [$SCRIPT][$(date)] Separating Info part."
cut -f 1,2 $CZENG_FILE > $TEMP_INFO_FILE

echo ">>> [$SCRIPT][$(date)] Generating output file."
paste $TEMP_INFO_FILE $TEMP_CS_LEMMA_FILE $TEMP_EN_LEMMA_FILE > $CZENG_LEMMA_FILE

echo ">>> [$SCRIPT][$(date)] Cleaning temporary files."
rm -rf $TEMP_DIR

echo ">>> [$SCRIPT][$(date)] Script ended successfully."
trap - EXIT TERM INT
exit 0