#!/usr/bin/perl

# base on sre16 local/make_sre16_eval.pl

# Usage: make_trials.pl test data/test/trials

$delimiter = "-";
$shifted = 0;

do {
  $shifted=0;
  if ($ARGV[0] eq "-d") {
    $delimiter = $ARGV[1];
    shift @ARGV; shift @ARGV;
    $shifted=1
  }
} while ($shifted);

if (@ARGV != 2) {
  print STDERR "Usage: $0 [-d <delimiter> ] <path-to-exp> <path-to-output>\n" .
  "e.g. $0 exp/xvectors_test data/test/trials \n";
  exit(1);
}

$exp_dir = shift @ARGV;
$out_dir = shift @ARGV;

#system "cp $test_dir/utt2spk $test_dir/utt2spk_tmp;";
system "echo $0: Creating trials file in $out_dir";
system "echo $0: Delimiter is $delimiter";

open(XVECTOR, "<", "${exp_dir}/xvector.scp") or die "Could not open ${exp_dir}/xvector.scp";
open(TRIALS, ">", "$out_dir") or die "Could not open $out_dir";

while (<XVECTOR>) {
  chomp;
  my ($utt_id2, $tmp) = split;
  my ($spk2) = split($delimiter, $utt_id2);
  #system "echo $utt_id2 speaker: $spk2";
  open(SPK_VECTOR, "<", "${exp_dir}/spk_xvector.scp") or die "Could not open ${exp_dir}/spk_xvector.scp";
  while (<SPK_VECTOR>) {
      chomp;
      my ($spk1,$tmp) = split;      
      my $target = "nontarget";
      if ($spk1 eq $spk2) {
        $target = "target";
      }
      print TRIALS "$spk1 $utt_id2 $target\n";
  }
  close(SPK_VECTOR) or die;
}  

close(XVECTOR) or die;
close(TRIALS) or die;

#system "rm $test_dir/utt2spk_tmp;";
system "sort -u $out_dir > ${out_dir}_tmp;";
system "rm $out_dir;";
system "mv ${out_dir}_tmp $out_dir;";
system "echo $0: Successfully create trials file in $out_dir";
