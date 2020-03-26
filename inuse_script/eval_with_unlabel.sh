#!/bin/bash

. ./cmd.sh
. ./path.sh

set -e -o pipefail

mfccdir=`pwd`/mfcc
vaddir=`pwd`/mfcc
libri_export=`pwd`/../asr_s5/export/LibriSpeech/
export=`pwd`/export/corpora

# SRE16 trials
nnet_dir=exp/xvector_nnet_1a

test_set="test_mooc"
train_set="train"

unlabel="train_gowajee"

centering_unlabel=0
train_plda_unlabel=0
eval_unlabel=1
make_unlabel=0

nj=32

stage=3

if [ $1 = "--help" ]; then
    echo "Usage: $0 [option]"
    echo "e.g.: $0 --unlabel train_gowajee --test-set test_gowajee --make-unlabel 0 --centering-unlabel 1 --train-plda-unlabel 1 --eval-unlabel 1 --stage 3"
    echo "Options:"
    echo "--nnet-dir		# nnet path."
    echo "--test-set		# test set."
    echo "--train-set		# train set."
    echo "--unlabel		# unlabel set."
    echo "--centering-unlabel	# If 1, true."
    echo "--train-plda-unlabel  # If 1, true."
    echo "--eval-unlabel	# If 1, true."
    echo "--stage		# 0: make feature test_set, 1: extract xvector for test_set, 2: make feature and extract xvector for unlabel, 3: [centering],[plda],eval."
     exit 1;
fi

. ./utils/parse_options.sh # --foo-bar into foo_bar variable

if [ $stage -le 0 ]; then  
    for test in $test_set; do
        steps/make_mfcc.sh --write-utt2num-frames true --mfcc-config conf/mfcc.conf --nj $nj --cmd "$train_cmd" \
          data/${test} exp/make_mfcc $mfccdir
        utils/fix_data_dir.sh data/${test}
	steps/compute_vad_decision.sh --nj $nj --cmd "$train_cmd" \
          data/${test} exp/make_vad $vaddir
        utils/fix_data_dir.sh data/${test}
    done
fi

if [ $stage -le 1 ]; then  
  for test in $test_set; do
    sid/nnet3/xvector/extract_xvectors.sh --cmd "$train_cmd --mem 6G" --nj $nj \
        $nnet_dir data/${test} exp/xvectors_${test}
    utt="$(head -1 exp/xvectors_${test}/xvector.scp | cut -d " " -f 1)"
    spk_len="$(head -1 exp/xvectors_${test}/spk_xvector.scp | cut -d " " -f 1 |  tr -d '[:space:]' | wc -c)"
    ./inuse_script/make_trials.pl -d ${utt:$(($spk_len)):1} exp/xvectors_${test} data/${test}/trials
  done
fi

if [ $stage -le 2 ]; then
  if [ $make_unlabel -eq 1 ]; then
    steps/make_mfcc.sh --write-utt2num-frames true --mfcc-config conf/mfcc.conf --nj $nj --cmd "$train_cmd" \
       data/${unlabel} exp/make_mfcc $mfccdir
    sid/compute_vad_decision.sh --nj $nj --cmd "$train_cmd" \
        data/${unlabel} exp/make_vad $vaddir
    utils/fix_data_dir.sh data/${unlabel}


    sid/nnet3/xvector/extract_xvectors.sh --cmd "$train_cmd --mem 6G" --nj 32 \
    $nnet_dir data/${unlabel} \
    exp/xvectors_${unlabel}
   fi
fi

if [ $stage -le 3 ]; then


    if [ $centering_unlabel -eq 1 ]; then
        # Compute the mean vector for centering the evaluation xvectors.
        $train_cmd exp/xvectors_${unlabel}/log/compute_mean.log \
          ivector-mean scp:exp/xvectors_${unlabel}/xvector.scp \
          exp/xvectors_${unlabel}/mean.vec || exit 1;
        echo "$0: centering unlabel success."
    fi

    if [ $train_plda_unlabel -eq 1 ]; then
        # This script uses LDA to decrease the dimensionality prior to PLDA.
        lda_dim=200
        $train_cmd exp/xvectors_${train_set}/log/lda.log \
          ivector-compute-lda --total-covariance-factor=0.0 --dim=$lda_dim \
          "ark:ivector-subtract-global-mean scp:exp/xvectors_${train_set}/xvector.scp ark:- |" \
          ark:data/${train_set}/utt2spk exp/xvectors_${train_set}/transform.mat || exit 1;

        # ${train_set} an out-of-domain PLDA model.
        $train_cmd exp/xvectors_${train_set}/log/plda.log \
          ivector-compute-plda ark:data/${train_set}/spk2utt \
          "ark:ivector-subtract-global-mean scp:exp/xvectors_${train_set}/xvector.scp ark:- | transform-vec exp/xvectors_${train_set}/transform.mat ark:- ark:- | ivector-normalize-length ark:-  ark:- |" \
          exp/xvectors_${train_set}/plda || exit 1;

        # Here we adapt the out-of-domain PLDA model to SRE16 major, a pile
        # of unlabeled in-domain data.
        $train_cmd exp/xvectors_${unlabel}/log/plda_adapt.log \
          ivector-adapt-plda --within-covar-scale=0.75 --between-covar-scale=0.25 \
          exp/xvectors_${train_set}/plda \
          "ark:ivector-subtract-global-mean scp:exp/xvectors_${unlabel}/xvector.scp ark:- | transform-vec exp/xvectors_${train_set}/transform.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
          exp/xvectors_${unlabel}/plda_adapt || exit 1;
        echo "$0: ${train_set} plda unlabel success."
    fi

    if [ $eval_unlabel -eq 1 ]; then
        echo "Scoring with speaker x-vector"
        for test in $test_set; do  
            $train_cmd exp/scores_${train_set}_unlabel_${unlabel}/scores_oov/log/${test}_scoring_oov.log \
            ivector-plda-scoring --normalize-length=true \
            "ivector-copy-plda --smoothing=0.0 exp/xvectors_${train_set}/plda - |" \
            "ark:ivector-subtract-global-mean exp/xvectors_${unlabel}/mean.vec scp:exp/xvectors_${test}/spk_xvector.scp ark:- | transform-vec exp/xvectors_${train_set}/transform.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
       "ark:ivector-subtract-global-mean exp/xvectors_${unlabel}/mean.vec scp:exp/xvectors_${test}/xvector.scp ark:- | transform-vec exp/xvectors_${train_set}/transform.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
            "cat data/${test}/trials | cut -d\  --fields=1,2 |" exp/scores_${train_set}_unlabel_${unlabel}/scores_oov/${test}_oov.trials || exit 1;     
            
             eer=$(paste data/${test}/trials exp/scores_${train_set}_unlabel_${unlabel}/scores_oov/${test}_oov.trials | awk '{print $6, $3}' | compute-eer - 2>/dev/null)
              mindcf1=`sid/compute_min_dcf.py --p-target 0.01 exp/scores_${train_set}_unlabel_${unlabel}/scores_oov/${test}_oov.trials data/${test}/trials 2> /dev/null`
              mindcf2=`sid/compute_min_dcf.py --p-target 0.001 exp/scores_${train_set}_unlabel_${unlabel}/scores_oov/${test}_oov.trials data/${test}/trials 2> /dev/null`
              echo "EER: exp/scores_${train_set}_unlabel_${unlabel}/scores_oov/${test}_oov.trials $eer%"
              echo "minDCF(p-target=0.01): $mindcf1"
              echo "minDCF(p-target=0.001): $mindcf2"

              echo "EER: exp/scores/${test}.trials $eer%" > exp/scores_${train_set}_unlabel_${unlabel}/scores_oov/scores_${test}
              echo "minDCF(p-target=0.01): $mindcf1" >> exp/scores_${train_set}_unlabel_${unlabel}/scores_oov/scores_${test}
              echo "minDCF(p-target=0.001): $mindcf2" >> exp/scores_${train_set}_unlabel_${unlabel}/scores_oov/scores_${test}
        done
        echo "End"


    echo "Scoring with speaker x-vector unlabel"
        for test in $test_set; do
            $train_cmd exp/scores_${train_set}_unlabel_${unlabel}/scores_adapt/log/${test}_scoring_adapt.log \
            ivector-plda-scoring --normalize-length=true \
            "ivector-copy-plda --smoothing=0.0 exp/xvectors_${unlabel}/plda_adapt - |" \
            "ark:ivector-subtract-global-mean exp/xvectors_${unlabel}/mean.vec scp:exp/xvectors_${test}/spk_xvector.scp ark:- | transform-vec exp/xvectors_${train_set}/transform.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
       "ark:ivector-subtract-global-mean exp/xvectors_${unlabel}/mean.vec scp:exp/xvectors_${test}/xvector.scp ark:- | transform-vec exp/xvectors_${train_set}/transform.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
            "cat data/${test}/trials | cut -d\  --fields=1,2 |" exp/scores_${train_set}_unlabel_${unlabel}/scores_adapt/${test}_adapt.trials || exit 1;

             eer=$(paste data/${test}/trials exp/scores_${train_set}_unlabel_${unlabel}/scores_adapt/${test}_adapt.trials | awk '{print $6, $3}' | compute-eer - 2>/dev/null)
              mindcf1=`sid/compute_min_dcf.py --p-target 0.01 exp/scores_${train_set}_unlabel_${unlabel}/scores_adapt/${test}_adapt.trials data/${test}/trials 2> /dev/null`
              mindcf2=`sid/compute_min_dcf.py --p-target 0.001 exp/scores_${train_set}_unlabel_${unlabel}/scores_adapt/${test}_adapt.trials data/${test}/trials 2> /dev/null`
              echo "EER: exp/scores/${test}.trials $eer%"
              echo "minDCF(p-target=0.01): $mindcf1"
              echo "minDCF(p-target=0.001): $mindcf2"

              echo "EER: exp/scores/${test}.trials $eer%" >> exp/scores_${train_set}_unlabel_${unlabel}/scores_adapt/scores_${test}
              echo "minDCF(p-target=0.01): $mindcf1" >> exp/scores_${train_set}_unlabel_${unlabel}/scores_adapt/scores_${test}
              echo "minDCF(p-target=0.001): $mindcf2" >> exp/scores_${train_set}_unlabel_${unlabel}/scores_adapt/scores_${test}
        done
        echo "End"
        echo "$0: evaluation unlabel success."
    fi 
fi

exit 0
