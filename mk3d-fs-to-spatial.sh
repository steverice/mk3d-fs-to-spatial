#!/usr/bin/env bash

RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

ENCODER='libx265'
TOOLBOX_QUALITY="85"
SPATIAL_QUALITY="75"
KEEP_FILES=false
LOGLEVEL='error'

print_error() {
    printf "${RED}ERROR: %s${NC}\n\n" "${@}"
}

print_info() {
    printf "${CYAN}%s${NC}\n" "${@}"
}

print_command() {
  if [ "$LOGLEVEL" == 'info' ]; then
    echo "$@"
  fi
  "$@"
}

usage() {
    cat << EOM
Convert frame-sequential 3D video to Apple spatial video

Usage:
  $0 [-x|--software] [-s|--spatial-quality QUALITY] [-a|--audio-bitrate BITRATE] [-k|--keep-intermediate-files] [-v|--verbose] input_video.mk3d
  $0 [-t|--hardware] [-q|--hevc-quality QUALITY] [-s|--spatial-quality QUALITY] [-a|--audio-bitrate BITRATE] [-k|--keep-intermediate-files] [-v|--verbose] input_video.mk3d

positional arguments:
    input_video.mk3d       Path to frame-sequential 3d video

optional arguments:
    -x, --software                  Use libx265 software encoder (slower, higher quality) [default]
    -t, --hardware                  Use hevc_videotoolbox hardware encoder (faster, lower quality)
    -q, --hevc-quality QUALITY      Quality to use with hevc_videotoolbox (1 to 100, 100 is highest quality/bitrate; default $TOOLBOX_QUALITY)
    -s, --spatial-quality QUALITY   Quality to use with spatial-media-kit-tool (1 to 100, 100 is highest quality/bitrate; default $SPATIAL_QUALITY)
    -a, --audio-bitrate BITRATE     Compress audio with AAC at this bitrate (uncompressed LPCM is used if omitted)
    -k, --keep-intermediate-files   Instead of removing intermediate files when they are no longer needed, leave them on disk
    -v, --verbose                   Enable verbose output
    -h, --help                      Show this help message and exit

EOM
}

# Transform long options to short ones
for arg in "$@"; do
    shift
        case "$arg" in
        '--verbose')                 set -- "$@" '-v'   ;;
        '--software')                set -- "$@" '-x'  ;;
        '--hardware')                set -- "$@" '-t'  ;;
        '--hevc-quality')            set -- "$@" '-q'  ;;
        '--spatial-quality')         set -- "$@" '-s'  ;;
        '--audio-bitrate')           set -- "$@" '-a'  ;;
        '--keep-intermediate-files') set -- "$@" '-k'  ;;
        '--help')                    set -- "$@" '-h'   ;;
        *)                           set -- "$@" "$arg" ;;
    esac
done


optspec="vxtka:q:s:h"
while getopts "$optspec" opt; do
    case "${opt}" in
        'v') LOGLEVEL='info' ;;
        'x') ENCODER='libx265' ;;
        't') ENCODER='hevc_videotoolbox' ;;
        'q') TOOLBOX_QUALITY=${OPTARG} ;;
        's') SPATIAL_QUALITY=${OPTARG} ;;
        'a') AUDIO_BITRATE=${OPTARG} ;;
        'k') KEEP_FILES=true;;
        '--'*) usage; exit 2;;
        *) usage; exit ;;
    esac
done
shift $((OPTIND-1))

INPUT=$1
if [ -z "$INPUT" ]; then print_error "Missing input file"; usage; exit 2; fi
input_name=${INPUT%.*}
OUTPUT="$input_name-spatial.mov"

if [ "$ENCODER" == "hevc_videotoolbox" ]; then
  VIDEO_ENCODER_PARAMS="-q:v ${TOOLBOX_QUALITY}"
else
  VIDEO_ENCODER_PARAMS="-x265-params keyint=1:min-keyint=1:lossless=1:log-level=$LOGLEVEL"
fi

if [ -n "$AUDIO_BITRATE" ]; then
  AUDIO_ENCODER_PARAMS="aac_at -b:a $AUDIO_BITRATE"
else
  AUDIO_ENCODER_PARAMS="pcm_s24le"
fi

if [ "$TOOLBOX_QUALITY" -lt 1 ] || [ "$TOOLBOX_QUALITY" -gt 100 ]; then print_error "HEVC quality must be between 1 and 100"; usage; exit 2; fi
if [ "$SPATIAL_QUALITY" -lt 1 ] || [ "$SPATIAL_QUALITY" -gt 100 ]; then print_error "Spatial quality must be between 1 and 100"; usage; exit 2; fi

if [ -z "$(which ffmpeg)" ]; then print_error "ffmpeg not found. Install with homebrew (brew install ffmpeg)"; exit 3; fi
if [ -z "$(which ldecod)" ]; then print_error "ldecod not found. Download from https://github.com/steverice/h264-tools"; exit 3; fi
if [ -z "$(which spatial-media-kit-tool)" ]; then print_error "spatial-media-kit-tool not found. Download from https://github.com/sturmen/SpatialMediaKit"; exit 3; fi
if [ -z "$(which mp4box)" ]; then print_error "mp4box not found. Install gpac from homebrew (brew install gpac)"; exit 3; fi

tmp_dir="$input_name-$(date +%s)"

if [ "$LOGLEVEL" == 'info' ]; then
  print_info "Processing file ${INPUT}"
  print_info "Using encoder:                   ${ENCODER}"
  print_info "Using hevc_videotoolbox quality: ${TOOLBOX_QUALITY}"
  print_info "Using spatial quality:           ${SPATIAL_QUALITY}"
  print_info "Using audio bitrate:             ${AUDIO_BITRATE:-LPCM Lossless}"
fi

mkdir "$tmp_dir"
filename_eyes=("$tmp_dir/eye_0.mov" "$tmp_dir/eye_1.mov")
filename_demuxed="$tmp_dir/demuxed.h264"
filename_audio="$tmp_dir/audio.mov"
filename_decoded="$tmp_dir/dec.yuv"
filename_decoded_0="$tmp_dir/dec_ViewId0000.yuv"
filename_decoded_1="$tmp_dir/dec_ViewId0001.yuv"
filename_spatial="$tmp_dir/spatial.mov"
filename_wait="$tmp_dir/wait.fifo"

symlinks="$filename_decoded_0 $filename_decoded_1"

cleanup() {
  # shellcheck disable=SC2086
  rm -f $symlinks $filename_wait
  trap - TERM # restore standard SIGTERM behavior
  kill -- -$$ # kill child processes
}

trap cleanup INT TERM EXIT

FRAMERATE=$(ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate "$INPUT" 2>/dev/null | head -1)
FSWIDTH=$(ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=width "$INPUT" 2>/dev/null | head -1)
FSHEIGHT=$(ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=height "$INPUT" 2>/dev/null | head -1)
STEREO_MODE=$(ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream_tags=stereo_mode "$INPUT" 2>/dev/null | head -1)
duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 -sexagesimal "$INPUT" 2>/dev/null | head -1)


case "${STEREO_MODE}" in
    'block_lr') PRIMARY_EYE='left'; left_index=0; right_index=1 ;;
    'block_rl') PRIMARY_EYE='right'; left_index=1; right_index=0 ;;
    *) echo "Unexpected stereo mode ${STEREO_MODE}"; exit 1 ;;
esac

if [ "$LOGLEVEL" == 'info' ]; then
  print_info "Video duration:                  ${duration}"
  print_info "Detected frame rate:             ${FRAMERATE}"
  print_info "Detected frame width:            ${FSWIDTH}"
  print_info "Detected frame height:           ${FSHEIGHT}"
  print_info "Detected stereo mode:            ${STEREO_MODE}"
fi

# Extract audio and video
# shellcheck disable=SC2086
print_command \
ffmpeg -y \
  -hide_banner \
  -i "$INPUT" \
  -loglevel error \
  -f h264 \
  -c:v copy \
  -bsf:v h264_mp4toannexb \
  "$filename_demuxed" \
  -map 0:a:0 \
  -c:a $AUDIO_ENCODER_PARAMS \
  "$filename_audio"

ln -s /dev/fd/3 "$filename_decoded_0"
ln -s /dev/fd/4 "$filename_decoded_1"

ffmpeg_command="ffmpeg -y \
  -f rawvideo \
  -loglevel error \
  -pixel_format yuv420p \
  -video_size ${FSWIDTH}x${FSHEIGHT} \
  -framerate $FRAMERATE \
  -i pipe: \
  $VIDEO_ENCODER_PARAMS \
  -c:v $ENCODER \
  -c:s copy \
  -vtag hvc1 \
  -movflags +faststart"

mkfifo "$filename_wait"

print_command \
ldecod -s \
  -p DecodeAllLayers=1 \
  -p "InputFile=$filename_demuxed" \
  -p "OutputFile=$filename_decoded" \
  -p Silent=1 \
3> >($ffmpeg_command -stats "${filename_eyes[0]}"; : >"$filename_wait") \
4> >($ffmpeg_command "${filename_eyes[1]}"; : >"$filename_wait")

# Wait until all subshells are done
# shellcheck disable=SC2162
for (( i=0;i<2;i++ )); do read < "$filename_wait"; done

# shellcheck disable=SC2086
rm -f $symlinks $filename_wait

if ! $KEEP_FILES; then rm "$filename_demuxed"; fi

print_command \
spatial-media-kit-tool merge \
  --left-file "${filename_eyes[left_index]}" \
  --right-file "${filename_eyes[right_index]}" \
  --quality "${SPATIAL_QUALITY}" \
  --${PRIMARY_EYE}-is-primary \
  --horizontal-field-of-view 90 \
  --output-file "$filename_spatial"

if ! $KEEP_FILES; then rm "${filename_eyes[*]}"; fi

print_command \
mp4box -new \
  -add "$filename_spatial" \
  -add "$filename_audio" \
  "$OUTPUT"

if ! $KEEP_FILES; then rm "$filename_spatial $filename_audio"; rmdir "$tmp_dir"; fi