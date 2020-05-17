#!/bin/bash

if [ "$#" -ne 2 ]; then
echo "Usage: $0 <src-dir> <dst-dir>"
echo "e.g.: $0 gowajee/test data/test_gowajee"
exit 1
fi

src=$1
dst=$2

# all utterances are FLAC compressed
if ! which sox >&/dev/null; then
echo "Please install 'sox' on ALL worker nodes!"
exit 1
fi


mkdir -p $dst || exit 1;

[ ! -d $src ] && echo "$0: no such directory $src" && exit 1


wav_scp=$dst/wav.scp; [[ -f "$wav_scp" ]] && rm $wav_scp
#text=$dst/text; [[ -f "$text" ]] && rm $text
utt2spk=$dst/utt2spk; [[ -f "$utt2spk" ]] && rm $utt2spk

for reader_dir in $(find -L $src -mindepth 1 -maxdepth 1 -type d | sort); do
  find -L $reader_dir/ -iname "*.wav" | sort | xargs -I% basename % .wav | \
    awk -v "dir=${reader_dir}" '{printf "%s sox %s/%s.wav -b 16 -r 16000 -t wav - |\n",  $0, dir, $0}' >>$wav_scp|| exit 1

  find -L $reader_dir/ -iname "*.wav" | sort | xargs -I% basename % .wav | \
    awk '{split($0,a,"_"); printf "%s %s\n", $0, a[1]}' >>$utt2spk|| exit 1
    
done

spk2utt=$dst/spk2utt
utils/utt2spk_to_spk2utt.pl <$utt2spk >$spk2utt || exit 1

#ntext=$(wc -l <$text)
#nutt2spk=$(wc -l <$utt2spk)
#! [ "$ntext" -eq "$nutt2spk" ] && \
#  echo "Inconsistent #textcripts($ntext) and #utt2spk($nutt2spk)" && exit 1;

utils/validate_data_dir.sh --no-feats --no-text $dst || exit 1;

echo "$0: successfully prepared data in $dst"

exit 0
