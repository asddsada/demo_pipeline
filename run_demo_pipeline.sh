#!/bin/bash

. ./cmd.sh
. ./path.sh
set -e

stage=0
target_spk="target"

. ./utils/parse_options.sh

if [ $stage -le 0 ]; then
    ./inuse_script/data_prep_gowajee.sh audios_demo/ data/test_demo/ || (echo "ERROR 0" > report_outputs/log && exit 1);
    ./utils/fix_data_dir.sh data/test_demo || (echo "ERROR 0" > report_outputs/log && exit 1);
fi

if [ $stage -le 1 ]; then
     ./utils/combine_data.sh data/test_combined data/test_gowajee/ data/test_demo/ || (echo "ERROR 1" > report_outputs/log  && exit 1);
fi

if [ $stage -le 2 ]; then
    ./inuse_script/eval_with_unlabel.sh --test-set test_combined --unlabel train_gowajee --nj 32 --make-unlabel 0 --centering-unlabel 0 --train-plda-unlabel 0 --eval-unlabel 1 --stage 0  || (echo "ERROR 2" > report_outputs/log  && exit 1);
fi

if [ $stage -le 3 ]; then
    grep "${target_spk} demo_${target_spk}" exp/scores_train_unlabel_train_gowajee/scores_adapt/test_combined_adapt.trials >  report_outputs/trials.txt || (echo "ERROR 3" > report_outputs/log  && exit 1);
    echo < report_output/trials.txt
fi

echo "SUCCESS" > report_outputs/log;

echo "$0: success.";
exit 0;
