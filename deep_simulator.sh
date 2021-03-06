#!/bin/bash

# ----- usage ------ #
function usage()
{
	echo "DeepSimulator v0.21 [Mar-14-2019] "
	echo "    A Deep Learning based Nanopore simulator which can simulate the process of Nanopore sequencing. "
	echo ""
	echo "USAGE:  ./deep_simulator.sh <-i input_genome> [-n simu_read_num] [-o out_root] [-c CPU_num] [-m sample_mode] [-M simulator] "
	echo "                [-C cirular_genome] [-u tune_sampling] [-e event_std] [-f filter_freq] [-s noise_std] [-P perfect] [-H home] "
	echo "Options:"
	echo ""
	echo "***** required arguments *****"
	echo "-i input_genome   : input genome in FASTA format. "
	echo ""
	echo "***** optional arguments *****"
	echo "-n simu_read_num  : the number of reads need to be simulated. [default = 100] "
	echo "                    Set -1 to simulate the whole input sequence without cut (not suitable for genome-level). "
	echo ""
	echo "-K coverage       : this parameter is converted to number of read in the program, if both K and n are given, we use the larger one."
	echo ""
	echo "-o out_root       : Default output would the current directory. [default = './\${input_name}_DeepSimu'] "
	echo ""
	echo "-c CPU_num        : Number of processors. [default = 8]"
	echo ""
	echo "-S Random_seed    : Random seed for controling the read sampling process. [default = 0]"
	echo ""
	echo "-m sample_mode    : choose from the following distribution for the read length. [default = 3] "
	echo "                    1: beta_distribution, 2: alpha_distribution, 3: mixed_gamma_dis. "
	echo ""
	echo "-M simulator      : choose either context-dependent(0) or context-independent(1) simulator. [default = 1] "
	echo ""
	echo "-C cirular_genome : 0 for linear genome and 1 for circular genome. [default = 0] "
	echo ""
	echo "-u tune_sampling  : 1 for tuning sampling rate to around eight and 0 for not. [default = 1] "
	echo ""
	echo "-e event_std      : set the standard deviation (std) of the random noise of the event. [default = 1.0] "
	echo ""
	echo "-f filter_freq    : set the frequency for the low-pass filter. [default = 850] "
	echo ""
	echo "-s noise_std      : set the standard deviation (std) of the random noise of the signal. [default = 1.5] "
	echo "                    '1.0' would give the base-calling accuracy around 92\%, "
	echo "                    '1.5' would give the base-calling accuracy around 90\%, "
	echo "                    '2.0' would give the base-calling accuracy around 85\%, "
	echo ""
	echo "-P perfect        : 0 for normal mode (with length repeat and random noise). [default = 0]"
	echo "                    1 for perfect context-dependent pore model (without length repeat and random noise). "
	echo "                    2 for generating almost perfect reads without any randomness in signals (equal to -e 0 -f 0 -s 0). "
	echo ""
	echo "-H home           : home directory of DeepSimulator. [default = 'current directory'] "
	echo ""
	exit 1
}


#------------------------------------------------------------#
##### ===== get pwd and check BlastSearchHome ====== #########
#------------------------------------------------------------#

#------ current directory ------#
curdir="$(pwd)"

#-------- check usage -------#
if [ $# -lt 1 ];
then
        usage
fi


#---------------------------------------------------------#
##### ===== All arguments are defined here ====== #########
#---------------------------------------------------------#

#------- required arguments ------------#
FULLFILE=""
out_root=""

#------- optioanl parameters -----------#
SAMPLE_NUM=100      #-> by default, we simulate 100 reads
COVERAGE=0          #-> the coverage parameter, we simulate read whichever the larger, SAMPLE_NUM or the number computed from coverage
#-> multiprocess
THREAD_NUM=8        #-> this is the thread (or, CPU) number
#-> simulator mode
SAMPLE_MODE=3       #-> choose from the following distribution: 1: beta_distribution, 2: alpha_distribution, 3: mixed_gamma_dis. default: [3]
SIMULATOR_MODE=1    #-> choose from the following type of simulator: 0: context-dependent, 1: context-independent. default: [1]
GENOME_CIRCULAR=0   #-> 0 for NOT circular and 1 for circular. default: [0]
TUNE_SAMPLING=1     #-> 1 for tuning sampling rate to around 8. default: [1]
#-> read geneartion
RANDOM_SEED=0       #-> random seed for controling sampling, for reproducibility. default: [0]
EVENT_STD=1.0       #-> set the std of random noise of the event, default = 1.0
FILTER_FREQ=850     #-> set the frequency for the low-pass filter. default = 850
NOISE_STD=1.5       #-> set the std of random noise of the signal, default = 1.5
#-> perfect mode
PERFECT_MODE=0      #-> 0 for normal mode (with length repeat and random noise). [default = 0]
                    #-> 1 for perfect context-dependent pore model (without length repeat and random noise).
                    #-> 2 for generating almost perfect reads without any randomness in signals (equal to -e 0 -f 0 -s 0).
#------- home directory -----------------#
home=$curdir


#------- parse arguments ---------------#
while getopts ":i:n:K:o:c:S:m:M:C:u:e:f:s:P:H:" opt;
do
	case $opt in
	#-> required arguments
	i)
		FULLFILE=$OPTARG
		;;
	#-> optional arguments
	o)
		out_root=$OPTARG
		;;
	n)
		SAMPLE_NUM=$OPTARG
		;;
	K)
		COVERAGE=$OPTARG
		;;
	c)
		THREAD_NUM=$OPTARG
		;;
	S)
		RANDOM_SEED=$OPTARG
		;;
	#-> simulator mode
	m)
		SAMPLE_MODE=$OPTARG
		;;
	M)
		SIMULATOR_MODE=$OPTARG
		;;
	C)
		GENOME_CIRCULAR=$OPTARG
		;;
	u)
		TUNE_SAMPLING=$OPTARG
		;;
	#-> simulator parameters
	e)
		EVENT_STD=$OPTARG
		;;
	f)
		FILTER_FREQ=$OPTARG
		;;
	s)
		NOISE_STD=$OPTARG
		;;
	P)
		PERFECT_MODE=$OPTARG
		;;
	#-> home directory
	H)
		home=$OPTARG
		;;
	#-> default
	\?)
		echo "Invalid option: -$OPTARG" >&2
		exit 1
		;;
	:)
		echo "Option -$OPTARG requires an argument." >&2
		exit 1
		;;
	esac
done



#---------------------------------------------------------#
##### ===== Part 0: initial argument check ====== #########
#---------------------------------------------------------#

# ------ check home directory ---------- #
if [ ! -d "$home" ]
then
	echo "home directory $home not exist " >&2
	exit 1
fi
home=`readlink -f $home`

#----------- check input genome  -----------#
if [ -z "$FULLFILE" ]
then
	echo "input input_genome is null !!" >&2
	exit 1
fi
FULLFILE=`readlink -f $FULLFILE`
#-> get query_name
fulnam=`basename $FULLFILE`
relnam=${fulnam%.*}

# ------ check output directory -------- #
if [ "$out_root" == "" ]
then
	out_root=${relnam}_DeepSimu
fi
mkdir -p $out_root
out_root=`readlink -f $out_root`


#--------------------------------------------------------#
##### ===== Part 1: DeepSimulator process ====== #########
#--------------------------------------------------------#

#------- init process -----------------#
FILENAME=$out_root
NUM=$(fgrep -o '>' $FULLFILE | wc -l)
PREFIX="signal"
PREALI="align"

# the input should be a fasta file
# we should make a tmp directory named after the input file to
# store the tmp files
echo "Pre-process input genome..."
source activate tensorflow_cdpm
python2 $home/util/genome_preprocess.py \
	-i $FULLFILE \
	-o $FILENAME/processed_genome \
	-r 1
source deactivate
echo "Pre-process input genome done!"

# preprocessing, sampling the read
# satisfy the converage and length distritubtion requirement
echo "Executing the preprocessing step..."
circular=""
if [ $GENOME_CIRCULAR -eq 1 ]
then
	circular="-c True"
fi
if [ $SAMPLE_NUM -gt 0 ]
then
	source activate tensorflow_cdpm
	python2 $home/util/genome_sampling.py \
		-i $FILENAME/processed_genome \
		-p $FILENAME/sampled_read \
		-n $SAMPLE_NUM \
		-K $COVERAGE \
		-d $SAMPLE_MODE \
		-S $RANDOM_SEED \
		$circular
	source deactivate
else
	mv $FILENAME/processed_genome $FILENAME/sampled_read.fasta
fi
echo "Finished the preprocessing step!"

# pore model translation
# convert the signal to the original range
# signal duplication 
# done within pore model
rm -rf $FILENAME/signal/*
mkdir -p $FILENAME/signal
rm -rf $FILENAME/align/*
mkdir -p $FILENAME/align

#--------- determine running mode -----------#
#-> perfect mode
perf_mode=""
if [ $PERFECT_MODE -eq 1 ]
then
	perf_mode="--perfect True"
elif [ $PERFECT_MODE -eq 2 ]
then
	EVENT_STD=0
	FILTER_FREQ=0
	NOISE_STD=0
fi
#-> official kmer model
model_file=template_median68pA.model

#--------- run different mode of simulator -------------#
if [ $SIMULATOR_MODE -eq 0 ]
then
	echo "Running the context-dependent pore model..."
	#-> context-dependent simulator
	source activate tensorflow_cdpm
	export DeepSimulatorHome=$home
	python2 $home/pore_model/src/context_simulator.py \
		-i $FILENAME/sampled_read.fasta \
		-p $FILENAME/signal/$PREFIX \
		-l $FILENAME/align/$PREALI \
		-t $THREAD_NUM  \
		-f $FILTER_FREQ -s $NOISE_STD \
		-S $RANDOM_SEED \
		-u $TUNE_SAMPLING \
		$perf_mode
	source deactivate
else
	echo "Running the context-independent pore model..."
	#-> contect-independent simulator
	source activate tensorflow_cdpm
	python2 $home/pore_model/src/kmer_simulator.py \
		-i $FILENAME/sampled_read.fasta \
		-p $FILENAME/signal/$PREFIX \
		-l $FILENAME/align/$PREALI \
		-t $THREAD_NUM -m $home/pore_model/model/$model_file \
		-e $EVENT_STD -f $FILTER_FREQ -s $NOISE_STD \
		-S $RANDOM_SEED \
		-u $TUNE_SAMPLING \
		$perf_mode
	source deactivate
fi
echo "Finished generate the simulated signals!"

# change the signal file to fasta5 file
echo "Converting the signal into FAST5 files..."
rm -rf $FILENAME/fast5/*
mkdir -p $FILENAME/fast5
source activate tensorflow_cdpm
python2 $home/util/fast5_modify_signal.py \
	-i $home/util/template.fast5 \
	-s $FILENAME/signal -t $THREAD_NUM \
	-d $FILENAME/fast5 
source deactivate
echo "Finished format converting!"

# basecalling using albacore
echo "Running Albacore..."
FAST5_DIR="$FILENAME/fast5"
FASTQ_DIR="$FILENAME/fastq"
rm -rf $FASTQ_DIR/*
mkdir -p $FASTQ_DIR
source activate basecall
read_fast5_basecaller.py -i $FAST5_DIR -s $FASTQ_DIR \
	-c r94_450bps_linear.cfg -o fastq -t $THREAD_NUM
source deactivate
echo "Basecalling finished!"

# check result
echo "Checking the read accuracy..."
cat $FILENAME/fastq/workspace/pass/*.fastq > $FILENAME/test.fastq
$home/util/minimap2 -Hk19 -t $THREAD_NUM -c $FULLFILE \
	$FILENAME/test.fastq 1> $FILENAME/mapping.paf 2> $FILENAME/err
rm -f $FILENAME/err
accuracy=`awk 'BEGIN{a=0;b=0}{a+=$10/$11;b++}END{print a/b}' $FILENAME/mapping.paf`
passnum=`grep "^@" $FILENAME/test.fastq | wc | awk '{print $1}'`
echo "Here is the mapping identity: $accuracy of $passnum reads passed base-calling."
echo "$accuracy $passnum" > $FILENAME/accuracy

#---------- exit -----------#
exit 0



