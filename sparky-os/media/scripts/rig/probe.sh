for f in "$@"; do
  for th in 1 4; do
    n=$(ffprobe -v error -threads $th -show_frames -select_streams v -show_entries frame=pict_type:frame_side_data=side_data_type -of csv=p=0 $f | grep -c "Stereo 3D")
    t=$(ffprobe -v error -threads $th -count_frames -select_streams v -show_entries stream=nb_read_frames -of csv=p=0 $f)
    echo "$(basename $f) threads=$th stereo3d_frames=$n of $t"
  done
done
